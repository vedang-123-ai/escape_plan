"""S3.5 → S6.7 acceptance: the score is reproducible by hand from the documented
weights, and completing a checklist item moves it by the documented amount.

Every fixture number here is hand-calculated in
docs/preparedness-score-weights.md § Worked examples. If a weight changes, both
this file and that doc must change together — that pairing IS the acceptance
criterion ("a reviewer can reproduce any fixture's score by hand").

S6.7 (2026-09-07) replaced the single summed-weighted-components model (5 fixed
components: primary_routes/secondary_routes/findings/smoke_alarms/practice)
with three independent peril sub-scores (fire/earthquake/severe_weather) and a
weighted composite (0.5×min + 0.25×mid + 0.25×max), capped at 40 whenever any
unresolved checklist item — scoring or not — carries `high` severity. The tests
below that pinned the old component model are rewritten against the new one;
the rest (auth, citations, checklist generation/id stability, egress/routes/
recommendation non-scoring behavior) are unaffected by that change and are
kept as-is.

No network: the grounded-recommendation path is faked. Live coverage is
tests/test_ai_live.py (S3.1), which this session did not extend.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app import config
from app.ai.grounded import GroundingError, Recommendation
from app.main import app
from app.models import HomeModel
from app.routing.engine import compute_route_plan
from app.scoring.checklist import ChecklistItem, build_checklist, finding_items, route_items
from app.scoring.findings import Finding, finding_id
from app.scoring.recommend import _map_recommendations
from app.scoring.score import SEVERITY_DEDUCTIONS, ScoreBreakdown, compute_score

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _scored(fixture: dict, findings=None, state=None) -> ScoreBreakdown:
    home = HomeModel.model_validate(fixture)
    thresholds = config.get_thresholds()
    plan = compute_route_plan(home, thresholds)
    # Call compute_score exactly as POST /score does (app/main.py), so these
    # tests see the same checklist the endpoint returns — the R310 egress-window
    # items, and both peril plans.
    #
    # S11.2: the peril plans were missing here while the comment already claimed
    # parity. It went unnoticed because no tornado item scored, so the omission
    # cost nothing; the moment safe_room.* became scoring, the helper and the
    # endpoint disagreed by 15 severe-weather points.
    tornado_plan = compute_route_plan(home, thresholds, peril="tornado")
    earthquake_plan = compute_route_plan(home, thresholds, peril="earthquake")
    return compute_score(
        home,
        plan,
        findings or [],
        state or {},
        thresholds,
        tornado_plan=tornado_plan,
        earthquake_plan=earthquake_plan,
    )


def _all_done(breakdown: ScoreBreakdown) -> dict[str, bool]:
    return {item.id: True for item in breakdown.checklist if item.scoring}


def _high(room_id: str) -> Finding:
    return Finding(
        severity="high",
        room_ids=[room_id],
        finding="Bedroom has no second way out.",
        evidence=["tool_call_3"],
        recommendation="Add an egress window.",
        citation="irc-2021-r310",
    )


# --- hand-calculated fixture scores (S6.7 composite model) ------------------
# Empty checklist, no agent findings. See docs/preparedness-score-weights.md
# § Worked examples for the arithmetic these numbers reproduce.


def test_bungalow_baseline_score(bungalow: dict):
    # 5 smoke-alarm items (fire), 4 earthquake prep items, 4 tornado items, and
    # 1 practice.meeting_point item (general, counts toward all three).
    # fire        = 100 - 5*5 - 5 = 70
    # earthquake  = 100 - 4*5 - 5 = 75   (move/heavy/tv/latches; no gas appliance)
    # severe_wx   = 100 - 4*5 - 5 = 75
    # composite = 0.5*70 + 0.25*75 + 0.25*75 = 72.5 -> 73 (round-half-up).
    result = _scored(bungalow)
    assert result.sub_scores == {"fire": 70, "earthquake": 75, "severe_weather": 75}
    assert result.score == 73


def test_apartment_baseline_score(apartment: dict):
    # 6 smoke-alarm items, 4 earthquake, 4 tornado, 1 meeting point.
    # fire = 100-30-5=65, earthquake = severe_wx = 100-20-5 = 75.
    # composite = 0.5*65 + 0.25*75 + 0.25*75 = 70.
    result = _scored(apartment)
    assert result.sub_scores == {"fire": 65, "earthquake": 75, "severe_weather": 75}
    assert result.score == 70
    # The single front door means no secondary egress — but routes items are
    # non-scoring, so that fact never shows up as a point deduction.
    route_items_ = [i for i in result.checklist if i.category == "routes"]
    assert route_items_ and all(not i.scoring for i in route_items_)


def test_twostory_baseline_score(twostory: dict):
    # 7 smoke-alarm items, 5 earthquake, 4 tornado, 1 meeting point. Earthquake
    # gets one more item than the bungalow: this home has a water heater, so
    # eq.flexible_gas_connectors is emitted.
    # fire = 100-35-5=60, earthquake = 100-25-5 = 70, severe_wx = 100-20-5 = 75.
    # composite = 0.5*60 + 0.25*70 + 0.25*75 = 66.25 -> 66.
    result = _scored(twostory)
    assert result.sub_scores == {"fire": 60, "earthquake": 70, "severe_weather": 75}
    assert result.score == 66


@pytest.mark.parametrize(
    "fixture_name", ["bungalow", "apartment", "twostory"]
)
def test_fully_checked_scores_reach_100(fixture_name: str, request):
    """All scoring boxes ticked -> every sub-score is 100 -> composite is 100.
    Unlike the old model, the apartment is no longer capped at 75 — its missing
    secondary egress is a `routes` finding, and routes have never been
    scoring."""
    fixture = request.getfixturevalue(fixture_name)
    baseline = _scored(fixture)
    result = _scored(fixture, state=_all_done(baseline))
    assert result.sub_scores == {"fire": 100, "earthquake": 100, "severe_weather": 100}
    assert result.score == 100


# --- checklist completion moves the score deterministically -----------------


def test_one_alarm_item_moves_twostory_fire_by_5(twostory: dict):
    """Every smoke-alarm item is worth a flat 5 fire points (info severity)."""
    baseline = _scored(twostory)
    alarm_items = [i for i in baseline.checklist if i.category == "smoke_alarm"]
    assert len(alarm_items) == 7
    after = _scored(twostory, state={alarm_items[0].id: True})
    assert after.sub_scores["fire"] == baseline.sub_scores["fire"] + 5
    # fire 65 is still the minimum: 0.5*65 + 0.25*70 + 0.25*75 = 68.75 -> 69.
    assert after.score == 69


def test_meeting_point_item_moves_all_three_sub_scores(bungalow: dict):
    """practice.meeting_point is hazard="general" — it counts toward every
    peril's sub-score, not just one."""
    baseline = _scored(bungalow)
    after = _scored(bungalow, state={"practice.meeting_point": True})
    assert after.sub_scores["fire"] == baseline.sub_scores["fire"] + 5
    assert after.sub_scores["earthquake"] == baseline.sub_scores["earthquake"] + 5
    assert after.sub_scores["severe_weather"] == baseline.sub_scores["severe_weather"] + 5
    # (75, 80, 80): 0.5*75 + 0.25*80 + 0.25*80 = 77.5 -> 78.
    assert after.score == 78


def test_each_bungalow_alarm_item_moves_fire_by_5(bungalow: dict):
    # 5 alarm items on a 1-floor/1-bedroom home, each worth 5 fire points.
    baseline = _scored(bungalow)
    alarm_ids = [i.id for i in baseline.checklist if i.category == "smoke_alarm"]
    assert len(alarm_ids) == 5
    # Earthquake (75) and severe weather (75) are now fixed points the composite
    # has to move around, so ticking alarms stops being worth a flat 2.5 each:
    # once fire passes 75 it is no longer the minimum and its weight drops from
    # 0.50 to 0.25. That bend is the "weakest link" rule doing its job.
    expected_score_by_count = [73, 75, 76, 78, 79, 80]
    for count in range(0, 6):
        result = _scored(bungalow, state={i: True for i in alarm_ids[:count]})
        assert result.sub_scores["fire"] == 70 + 5 * count
        assert result.score == expected_score_by_count[count]


def test_non_scoring_items_do_not_move_the_score(apartment: dict):
    """Ticking a routes item must not buy points — the routes components move
    only when the model actually changes and the engine re-runs."""
    baseline = _scored(apartment)
    route_items_ = [i for i in baseline.checklist if i.category == "routes"]
    assert route_items_ and all(not i.scoring for i in route_items_)
    after = _scored(apartment, state={i.id: True for i in route_items_})
    assert after.score == baseline.score


# --- agent findings: cap, not a per-item deduction ---------------------------
# S3.2 agent findings are always scoring=False (finding_items). Under the old
# model they deducted a fixed amount by severity; under S6.7 they instead
# trigger (high severity only) the 40-point composite cap. Bug A fix
# (2026-09-07): the cap check must ignore the `scoring` flag entirely so a
# structural finding like no_viable_route — which is scoring=False by design,
# since it's fixed by changing the home, not by checking a box — still caps
# the score.


def test_high_severity_finding_caps_the_score(apartment: dict):
    result = _scored(apartment, findings=[_high("r_bed1")])
    assert result.score == 40
    assert any(
        i.category == "agent_finding" and i.severity == "high" and not i.done
        for i in result.checklist
    )


def test_multiple_high_severity_findings_do_not_stack(apartment: dict):
    """The cap is a ceiling, not a per-item deduction: three high-severity
    findings cap the score exactly as hard as one."""
    result = _scored(apartment, findings=[_high("r_bed1")] * 3)
    assert result.score == 40


def test_only_high_severity_findings_trigger_the_cap(bungalow: dict):
    """med/low severity agent findings never move the score (they're
    scoring=False and don't meet the cap's severity=="high" bar); a high one
    still caps the composite at 40."""
    med_low = [
        Finding(
            severity="med",
            room_ids=["r_kitchen"],
            finding="Kitchen exit door is narrow.",
            evidence=["tool_call_5"],
            recommendation="Keep it clear.",
            citation="irc-2021-r311",
        ),
        Finding(
            severity="low",
            room_ids=["r_bath"],
            finding="Bathroom window is small.",
            evidence=["tool_call_7"],
            recommendation="Note it in the plan.",
            citation="irc-2021-r310",
        ),
    ]
    baseline = _scored(bungalow)
    result_med_low = _scored(bungalow, findings=med_low)
    assert result_med_low.score == baseline.score

    result_with_high = _scored(bungalow, findings=med_low + [_high("r_bedroom")])
    assert result_with_high.score == 40


def test_high_severity_caps_even_when_everything_else_is_done(apartment: dict):
    """A fully-checked-off home with one unresolved high-severity finding must
    still land at 40 — the cap overrides a perfect checklist. This is the
    "wheelchair user can't get out" scenario the cap exists for."""
    home = HomeModel.model_validate(apartment)
    thresholds = config.get_thresholds()
    plan = compute_route_plan(home, thresholds)
    baseline = compute_score(home, plan, [_high("r_bed1")], {}, thresholds)
    all_done = {i.id: True for i in baseline.checklist if i.scoring}
    breakdown = compute_score(home, plan, [_high("r_bed1")], all_done, thresholds)
    assert breakdown.score == 40
    assert any(i.severity == "high" and not i.done for i in breakdown.checklist)


# --- lapsed recurring items are non-punitive (S6.7 acceptance criterion) ----


def test_lapsed_rescan_does_not_reduce_score(bungalow: dict):
    """rescan.home is scoring=False: staleness never costs a point."""
    baseline = _scored(bungalow)
    checked = _scored(bungalow, state={"rescan.home": True})
    assert checked.score == baseline.score


def test_lapsed_drill_does_not_reduce_score(bungalow: dict):
    """Bug B fix (2026-09-07): practice.drill_recent must be scoring=False for
    the same reason as rescan.home — a lapsed or never-done drill flags
    staleness on the checklist but never lowers the score."""
    baseline = _scored(bungalow)
    drill_item = next(
        i for i in baseline.checklist if i.id == "practice.drill_recent"
    )
    assert drill_item.scoring is False
    checked = _scored(bungalow, state={"practice.drill_recent": True})
    assert checked.score == baseline.score


# --- purity, determinism, and explainability ---------------------------------


def test_score_is_deterministic(twostory: dict):
    state = {"practice.meeting_point": True, "alarm.level.f1": True}
    findings = [_high("r_bed_kids")]
    first = _scored(twostory, findings=findings, state=state)
    second = _scored(twostory, findings=findings, state=state)
    assert first == second


def test_compute_score_does_not_mutate_inputs(bungalow: dict):
    home = HomeModel.model_validate(bungalow)
    plan = compute_route_plan(home, config.get_thresholds())
    before = home.model_dump(mode="json"), plan.model_dump(mode="json")
    compute_score(home, plan, [], {"alarm.level.f1": True})
    assert (home.model_dump(mode="json"), plan.model_dump(mode="json")) == before


def test_largest_deduction_component_shape(twostory: dict):
    """New model: `components` holds 0 or 1 entries — the single largest
    unresolved scoring deduction across all perils — not a fixed set of five.
    See the ScoreComponent doc comment in ScoreModels.swift and the "Largest
    Deduction" section on ScoreScreen. (Replaces the old
    test_components_sum_to_score / test_every_component_explains_itself, which
    pinned the old 5-fixed-components model.)"""
    baseline = _scored(twostory)
    assert len(baseline.components) == 1
    component = baseline.components[0]
    matching_item = next(
        i for i in baseline.checklist if i.id == component.key
    )
    assert component.earned_points == 0.0
    assert component.max_points == SEVERITY_DEDUCTIONS[matching_item.severity]
    assert component.detail and component.rationale

    fully_done = _scored(twostory, state=_all_done(baseline))
    assert fully_done.components == []


def test_ai_recommendations_non_scoring(bungalow: dict, monkeypatch):
    """category == "recommendation" items must never move a sub-score, even a
    (deliberately, adversarially) mis-tagged one with scoring=True and
    severity="high" — the category exclusion in compute_score, not the
    scoring flag, is what recommend.py's non-scoring guarantee rests on.
    test_score_endpoint_appends_recommendations_without_moving_score pins the
    same guarantee at the endpoint level, where recommendations are appended
    after scoring is already computed; this test pins it at the compute_score
    level directly."""
    import app.scoring.score as score_module

    home = HomeModel.model_validate(bungalow)
    thresholds = config.get_thresholds()
    plan = compute_route_plan(home, thresholds)
    baseline = compute_score(home, plan, [], {}, thresholds)

    poison = ChecklistItem(
        id="recommendation.poison",
        category="recommendation",
        hazard="fire",
        title="A recommendation dressed up as high severity",
        detail="If this ever moves a sub-score, the category exclusion broke.",
        done=False,
        scoring=True,
        severity="high",
    )
    real_build_checklist = score_module.build_checklist
    monkeypatch.setattr(
        score_module,
        "build_checklist",
        lambda *a, **k: real_build_checklist(*a, **k) + [poison],
    )
    poisoned = compute_score(home, plan, [], {}, thresholds)
    assert poisoned.sub_scores == baseline.sub_scores
    assert poisoned.score == baseline.score


# --- checklist generation ----------------------------------------------------


def test_checklist_items_are_generated_from_the_home(twostory: dict):
    result = _scored(twostory)
    ids = {i.id for i in result.checklist}
    # one per bedroom, one outside the sleeping area (f2 only — f1 has no
    # bedroom), one per level, plus the two maintenance items
    assert {"alarm.bedroom.r_bed_master", "alarm.bedroom.r_bed_kids"} <= ids
    assert "alarm.sleeping_area.f2" in ids
    assert "alarm.sleeping_area.f1" not in ids
    assert {"alarm.level.f1", "alarm.level.f2"} <= ids
    assert {"alarm.test_monthly", "alarm.replace_10y"} <= ids
    assert {"practice.meeting_point", "practice.drill_recent"} <= ids


def test_checklist_item_ids_are_stable_across_runs(apartment: dict):
    home = HomeModel.model_validate(apartment)
    plan = compute_route_plan(home, config.get_thresholds())
    findings = [_high("r_bed1")]
    first = [i.id for i in build_checklist(home, plan, findings, {})]
    second = [i.id for i in build_checklist(home, plan, findings, {})]
    assert first == second
    assert len(set(first)) == len(first), "checklist item ids must be unique"


def test_apartment_route_findings_become_checklist_items(apartment: dict):
    result = _scored(apartment)
    route_ids = {i.id for i in result.checklist if i.category == "routes"}
    assert "routes.no_secondary_egress.r_bed1" in route_ids


def test_agent_findings_become_cited_checklist_items(apartment: dict):
    result = _scored(apartment, findings=[_high("r_bed1")])
    item = next(i for i in result.checklist if i.category == "agent_finding")
    assert item.title == "Bedroom has no second way out."
    assert item.source_citation == "irc-2021-r310"
    assert item.scoring is False


def test_every_safety_claim_item_carries_a_citation(twostory: dict):
    result = _scored(twostory, findings=[_high("r_bed_kids")])
    # Items whose citation is None by design (engineering choices, not safety
    # claims) are documented as such in the checklist module and are excluded.
    UNCITED_BY_DESIGN = {"rescan.home"}
    for item in result.checklist:
        if item.id in UNCITED_BY_DESIGN:
            continue
        assert item.source_citation, f"{item.id} makes a claim with no citation"


def test_done_state_round_trips(bungalow: dict):
    result = _scored(bungalow, state={"alarm.test_monthly": True})
    done = {i.id for i in result.checklist if i.done}
    assert done == {"alarm.test_monthly"}


def test_weights_in_code_match_docs():
    """Fails if a weight exists in code but not in
    docs/preparedness-score-weights.md."""
    from pathlib import Path

    doc_path = (
        Path(__file__).parent.parent.parent
        / "docs"
        / "preparedness-score-weights.md"
    )
    doc_text = doc_path.read_text()
    for severity, deduction in SEVERITY_DEDUCTIONS.items():
        assert str(int(deduction)) in doc_text, (
            f"Weight {deduction} for {severity} missing from docs"
        )


# --- stable agent-finding ids (2026-07-23) -----------------------------------
# Content-derived ids replace the positional agent_finding.<index> keys, so a
# re-analysis that reorders findings no longer mis-keys saved checkmarks.


def _stamped(severity: str, room_id: str, text: str) -> Finding:
    return Finding(
        id=finding_id(severity, [room_id], text),
        severity=severity,
        room_ids=[room_id],
        finding=text,
        evidence=["tool_call_3"],
        recommendation="Fix it.",
        citation="irc-2021-r310",
    )


def test_finding_ids_stable_under_reordering():
    a = _stamped("high", "r_bed1", "Bedroom has no second way out.")
    b = _stamped("med", "r_kitchen", "Kitchen exit door is narrow.")
    forward = {i.id for i in finding_items([a, b], {})}
    reversed_ = {i.id for i in finding_items([b, a], {})}
    assert forward == reversed_
    assert len(forward) == 2


def test_checklist_keying_survives_reordering():
    a = _stamped("high", "r_bed1", "Bedroom has no second way out.")
    b = _stamped("med", "r_kitchen", "Kitchen exit door is narrow.")
    a_key = f"agent_finding.{a.id}"
    state = {a_key: True}
    done_forward = {i.id for i in finding_items([a, b], state) if i.done}
    done_reversed = {i.id for i in finding_items([b, a], state) if i.done}
    assert done_forward == done_reversed == {a_key}


def test_distinct_findings_get_distinct_ids():
    base = ("high", ["r_bed1"], "Bedroom has no second way out.")
    variants = [
        ("med", ["r_bed1"], "Bedroom has no second way out."),
        ("high", ["r_bed2"], "Bedroom has no second way out."),
        ("high", ["r_bed1"], "Bedroom window sill is too high."),
    ]
    ids = {finding_id(*base)} | {finding_id(*v) for v in variants}
    assert len(ids) == 4


def test_finding_id_ignores_room_order_and_text_punctuation():
    assert finding_id("high", ["r_a", "r_b"], "No way out!") == finding_id(
        "high", ["r_b", "r_a"], "no way out"
    )


def test_idless_findings_fall_back_to_positional_keys():
    legacy = Finding(
        severity="high",
        room_ids=["r_bed1"],
        finding="Bedroom has no second way out.",
        evidence=["tool_call_3"],
        recommendation="Add an egress window.",
        citation="irc-2021-r310",
    )
    items = finding_items([legacy], {"agent_finding.0": True})
    assert items[0].id == "agent_finding.0"
    assert items[0].done is True


# --- grounded recommendations (mocked) --------------------------------------


def test_recommendations_map_to_non_scoring_items():
    items = _map_recommendations(
        [
            Recommendation(
                claim="Every sleeping room needs an escape opening.",
                action="Add an egress window to Bedroom 2.",
                source_citation="irc-2021-r310",
            )
        ],
        {},
    )
    assert len(items) == 1
    assert items[0].scoring is False
    assert items[0].title == "Add an egress window to Bedroom 2."
    assert items[0].source_citation == "irc-2021-r310"


def test_uncited_recommendation_is_refused():
    with pytest.raises(GroundingError, match="totally-made-up"):
        _map_recommendations(
            [
                Recommendation(
                    claim="Sleep with the window open.",
                    action="Open the window.",
                    source_citation="totally-made-up-source",
                )
            ],
            {},
        )


# --- /score endpoint ---------------------------------------------------------


def test_score_endpoint_requires_token(bungalow: dict):
    assert TestClient(app).post("/score", json={"home": bungalow}).status_code == 401


@pytest.mark.parametrize(
    "fixture_name,expected", [("bungalow", 73), ("apartment", 70), ("twostory", 66)]
)
def test_score_endpoint_matches_the_engine(fixture_name: str, expected: int, request):
    fixture = request.getfixturevalue(fixture_name)
    resp = TestClient(app).post("/score", json={"home": fixture}, headers=AUTH)
    assert resp.status_code == 200
    breakdown = ScoreBreakdown.model_validate(resp.json())
    assert breakdown.score == expected
    # Same numbers the in-process engine produces — this is the test that would
    # have caught _scored drifting away from the endpoint (S11.2).
    assert breakdown.sub_scores == _scored(fixture).sub_scores


def test_score_endpoint_accepts_findings_and_state(apartment: dict):
    """The high-severity finding caps the composite at 40 regardless of the
    meeting-point checkbox — the cap overrides ordinary deductions."""
    resp = TestClient(app).post(
        "/score",
        json={
            "home": apartment,
            "findings": [_high("r_bed1").model_dump()],
            "checklist_state": {"practice.meeting_point": True},
        },
        headers=AUTH,
    )
    assert resp.status_code == 200
    assert ScoreBreakdown.model_validate(resp.json()).score == 40


def test_score_endpoint_honours_constraints(twostory: dict):
    """Grandpa's mobility_limited profile bans stairs; upstairs rooms lose
    routes, producing a high-severity no_viable_route finding that caps the
    score — the score reflects the plan on screen."""
    resp = TestClient(app).post(
        "/score",
        json={"home": twostory, "constraints": {"avoid_stairs": True}},
        headers=AUTH,
    )
    assert resp.status_code == 200
    assert ScoreBreakdown.model_validate(resp.json()).score < 78


def test_score_endpoint_appends_recommendations_without_moving_score(
    apartment: dict, monkeypatch
):
    canned = [
        Recommendation(
            claim="Two ways out of every room.",
            action="Add an egress window to Bedroom 1.",
            source_citation="nfpa-escape-planning",
        )
    ]
    monkeypatch.setattr(
        "app.main.recommendation_items",
        lambda *a, **k: _map_recommendations(canned, {}),
    )
    resp = TestClient(app).post(
        "/score",
        json={"home": apartment, "include_recommendations": True},
        headers=AUTH,
    )
    assert resp.status_code == 200
    result = ScoreBreakdown.model_validate(resp.json())
    assert result.score == 70  # unchanged vs. the no-recommendations baseline
    assert [i.title for i in result.checklist if i.category == "recommendation"] == [
        "Add an egress window to Bedroom 1."
    ]


def test_score_endpoint_maps_grounding_error_to_502(apartment: dict, monkeypatch):
    def boom(*a, **k):
        raise GroundingError("citation validation failed after retries")

    monkeypatch.setattr("app.main.recommendation_items", boom)
    resp = TestClient(app).post(
        "/score",
        json={"home": apartment, "include_recommendations": True},
        headers=AUTH,
    )
    assert resp.status_code == 502


def test_score_endpoint_rejects_unknown_fields(bungalow: dict):
    resp = TestClient(app).post(
        "/score", json={"home": bungalow, "unexpected": 1}, headers=AUTH
    )
    assert resp.status_code == 422


def test_score_endpoint_computes_multi_peril_plans(bungalow: dict):
    """The /score endpoint must compute and pass tornado and earthquake plans,
    not just fire, so the checklist contains severe-weather and earthquake items.
    Bungalow's Kitchen carries no exterior opening, so it IS a viable shelter and the home
    gets `safe_room.know` rather than `safe_room.nearby_shelter`. This assertion was
    inverted until 2026-09-06 — see test_perils.test_a_site_built_home_always_gets_an_interior_shelter.
    """
    resp = TestClient(app).post("/score", json={"home": bungalow}, headers=AUTH)
    assert resp.status_code == 200

    breakdown = ScoreBreakdown.model_validate(resp.json())
    ids = {i.id for i in breakdown.checklist}

    # Assert a tornado safe room item was generated. A site-built home with an interior
    # room is told WHERE to shelter, never to leave the house.
    assert "safe_room.know" in ids
    assert "safe_room.nearby_shelter" not in ids
    # Assert earthquake mitigation/cover items are generated (e.g. supply_kit)
    assert "supply_kit.72h" in ids


# ---------------------------------------------------------------------------
# Deterministic egress-window items (IRC R310) — no /analyze required


def test_undersized_bedroom_window_is_flagged_without_running_analyze(twostory):
    """twostory.json's planted kids'-bedroom window.

    The whole-house router raises no RoutePlan finding for it (its secondary
    route legitimately leaves by another exit — docs/decisions.md 2026-07-16),
    so before this check existed the danger appeared on the checklist only if
    someone happened to run /analyze.
    """
    breakdown = _scored(twostory)  # note: no findings passed

    item = next(
        (i for i in breakdown.checklist if i.id == "egress.window.w_kids"), None
    )
    assert item is not None, "undersized bedroom window must be reported"
    assert item.category == "egress"
    assert item.source_citation == "irc-2021-r310"
    assert "0.400m" in item.detail  # the measured failure, not boilerplate


def test_egress_window_items_are_non_scoring(twostory):
    """Fixed by changing the home, not by ticking a box — same rule as routes."""
    breakdown = _scored(twostory)
    egress = [i for i in breakdown.checklist if i.category == "egress"]

    assert egress, "expected at least one egress item on twostory"
    assert all(not i.scoring for i in egress)
    assert all(i.component is None for i in egress)

    ticked = _scored(twostory, state={i.id: True for i in egress})
    assert ticked.score == breakdown.score


def test_compliant_windows_are_not_flagged(bungalow):
    """Only failures appear — a home whose bedroom windows pass stays quiet."""
    breakdown = _scored(bungalow)
    assert [i for i in breakdown.checklist if i.category == "egress"] == []


def test_egress_items_are_omitted_when_no_thresholds_are_supplied(twostory):
    """Backward compatibility for callers predating the thresholds argument."""
    home = HomeModel.model_validate(twostory)
    plan = compute_route_plan(home, config.get_thresholds())
    breakdown = compute_score(home, plan, [], {})  # no thresholds

    assert [i for i in breakdown.checklist if i.category == "egress"] == []


# ---------------------------------------------------------------------------
# narrows_route in the checklist (2026-08-25).


def _narrow_plan(bungalow_narrow):
    return compute_route_plan(
        HomeModel.model_validate(bungalow_narrow), config.get_thresholds()
    )


def test_a_squeeze_is_not_described_as_having_no_way_out(bungalow_narrow) -> None:
    """The trap this pins: `route_items` had an `else` that titled anything it did
    not recognise "<room> has no usable way out". Adding `narrows_route` without a
    branch would have made a passable-but-tight doorway read as a dead end — a
    graver claim than the engine made, and one no citation supports."""
    items = route_items(_narrow_plan(bungalow_narrow), state={})
    squeeze = [i for i in items if "narrows_route" in i.id]
    assert len(squeeze) == 1
    assert "no usable way out" not in squeeze[0].title
    assert squeeze[0].title == "Widen the way out of Bedroom"


def test_squeeze_checklist_item_keys_on_the_object(bungalow_narrow) -> None:
    """Same reason blocked_opening does: one room can have several pinch points,
    and keying on the room alone collapses them onto one checkbox."""
    items = route_items(_narrow_plan(bungalow_narrow), state={})
    squeeze = next(i for i in items if "narrows_route" in i.id)
    assert squeeze.id == "routes.narrows_route.r_bedroom.o_wardrobe_narrowing"


def test_squeeze_checklist_item_is_non_scoring(bungalow_narrow) -> None:
    """Like every route item: fixed by changing the home and re-running the
    engine, which moves the routes components on its own."""
    items = route_items(_narrow_plan(bungalow_narrow), state={})
    squeeze = next(i for i in items if "narrows_route" in i.id)
    assert squeeze.scoring is False


# --- S11.2: peril depth, honest tiering ------------------------------------


def test_every_peril_sub_score_actually_varies(bungalow: dict, twostory: dict):
    """The defect this session exists to fix.

    Before S11.2 neither earthquake nor severe weather had a single scoring item,
    so both sat at a constant 95 on every home and 0.50*min(sub_scores) always
    resolved to fire. Two of the three pillars in the composite carried no
    information at all. If that ever comes back, this goes red.
    """
    for peril in ("fire", "earthquake", "severe_weather"):
        baseline = _scored(bungalow)
        peril_items = [
            i for i in baseline.checklist
            if i.scoring and i.hazard == peril
        ]
        assert peril_items, f"{peril} has no scoring checklist item of its own"
        after = _scored(bungalow, state={peril_items[0].id: True})
        assert after.sub_scores[peril] == baseline.sub_scores[peril] + 5, (
            f"ticking a {peril} item did not move the {peril} sub-score"
        )

    # And the three are not locked together: twostory's water heater gives
    # earthquake one item the bungalow does not have.
    assert _scored(twostory).sub_scores["earthquake"] != _scored(bungalow).sub_scores["earthquake"]


def test_basis_labels_every_peril_and_matches_sub_scores(bungalow: dict):
    result = _scored(bungalow)
    assert result.basis == {
        "fire": "code_quantified",
        "earthquake": "guidance_based",
        "severe_weather": "guidance_based",
    }
    # Keyed exactly like sub_scores, so a client can zip the two without guessing.
    assert result.basis.keys() == result.sub_scores.keys()


def test_basis_is_optional_so_older_clients_still_decode():
    """`basis` must never be required: an iOS build predating S11.2 decodes a
    response without it, and a response it does not understand must not fail."""
    payload = {
        "home_id": "h", "home_name": "H", "score": 50,
        "sub_scores": {"fire": 50, "earthquake": 50, "severe_weather": 50},
        "components": [], "checklist": [],
    }
    assert ScoreBreakdown.model_validate(payload).basis is None


def test_guidance_based_perils_use_the_same_flat_deduction_as_fire(bungalow: dict):
    """The tiering must not become a weighting.

    `basis` reports what kind of evidence a peril rests on. It must not buy a
    guidance-based peril a different deduction, a multiplier, or a decimal the
    sources do not support — that would be exactly the false precision the tier
    exists to flag. Every scoring item, whatever its peril, is worth a flat 5.
    """
    baseline = _scored(bungalow)
    for item in [i for i in baseline.checklist if i.scoring]:
        after = _scored(bungalow, state={item.id: True})
        moved = {
            peril: after.sub_scores[peril] - baseline.sub_scores[peril]
            for peril in baseline.sub_scores
        }
        assert set(moved.values()) <= {0, 5}, (
            f"{item.id} ({item.hazard}) moved sub-scores by {moved}, not a flat 5"
        )


def test_no_authored_earthquake_or_tornado_item_invents_a_threshold(
    bungalow: dict, twostory: dict
):
    """S11.1 established these two perils carry no app-checkable number, and that
    the absence is the finding. A figure appearing in an item this project
    *authored* is the smell of one being invented.

    Scope, stated honestly after the grounding-auditor found the first version
    overclaiming:

    - It covers `title`, `detail` AND `why`. The first version omitted `why`,
      which is exactly where figures live.
    - It covers only items whose text this repo wrote (`eq.*`, `safe_room.*`,
      `alerts.*`). Engine-generated items (`hazard.*`, `engine.*`,
      `mitigation.secure.*`) legitimately state MEASURED geometry — "1.9 m tall,
      1.5 m away" — which is the code-quantified half of the app doing its job,
      not a corpus threshold.
    - Sourced statistics are allowed by name, not by accident. The UCLA Northridge
      figures are verbatim in earthquake-securing-home.md; they are evidence for
      an ordering, not a threshold anything is checked against.

    What it therefore does NOT catch: a spelled-out number ("two straps"). That
    is a real limit, not an oversight — see docs/preparedness-score-weights.md,
    which states the same scope.
    """
    import re as _re

    ALLOWED_SOURCED_FIGURES = {
        # earthquake-securing-home.md:17-20, verbatim from ShakeOut.
        "eq.move_before_fasten": ["55%", "1%", "1994"],
    }

    for fixture in (bungalow, twostory):
        for item in _scored(fixture).checklist:
            if item.hazard not in ("earthquake", "severe_weather"):
                continue
            if not item.id.startswith(("eq.", "safe_room.", "alerts.")):
                continue
            text = f"{item.title} {item.detail} {item.why}"
            for allowed in ALLOWED_SOURCED_FIGURES.get(item.id, []):
                text = text.replace(allowed, "")
            assert not _re.search(r"\d", text), (
                f"{item.id} states a figure ({text!r}). Earthquake and tornado "
                f"guidance in this corpus carries no app-checkable number — see "
                f"decisions.md 2026-09-21. If it is a sourced statistic, add it to "
                f"ALLOWED_SOURCED_FIGURES with the corpus line that carries it."
            )


def test_every_new_peril_item_cites_a_resolvable_source(bungalow: dict, twostory: dict):
    from app.ai.grounded import valid_source_ids

    valid = valid_source_ids()
    seen: set[str] = set()
    for fixture in (bungalow, twostory):
        for item in _scored(fixture).checklist:
            if item.hazard not in ("earthquake", "severe_weather"):
                continue
            assert item.source_citation, f"{item.id} makes a safety claim with no source"
            assert item.source_citation in valid, (
                f"{item.id} cites {item.source_citation!r}, not in sources.json"
            )
            seen.add(item.id)

    # Named explicitly so a silently-dropped item cannot make this vacuous.
    assert {
        "eq.move_before_fasten", "eq.heavy_objects_low", "eq.tv_computer_straps",
        "eq.cabinet_latches", "eq.flexible_gas_connectors", "eq.stay_if_undamaged",
        "safe_room.know", "safe_room.head_protection", "safe_room.practice_the_move",
        "alerts.weather_radio",
    } <= seen


def test_accessible_alert_items_never_lower_the_score(bungalow: dict):
    """A household must not score lower because someone in it is deaf.

    The SAME-receiver and strobe items are real, sourced actions, and they appear
    on the checklist — but they are non-scoring on purpose. See
    docs/preparedness-score-weights.md.
    """
    from app.models import Profile

    home = HomeModel.model_validate(bungalow)
    without = _scored(bungalow)

    home.profiles.append(
        Profile(
            id="p_hoh",
            name="Sam",
            bedroom_room_id=home.floors[0].rooms[0].id,
            tags=["hearing_impaired"],
        )
    )
    thresholds = config.get_thresholds()
    plan = compute_route_plan(home, thresholds)
    with_hoh = compute_score(
        home, plan, [], {}, thresholds,
        tornado_plan=compute_route_plan(home, thresholds, peril="tornado"),
        earthquake_plan=compute_route_plan(home, thresholds, peril="earthquake"),
    )

    accessibility_items = [
        i for i in with_hoh.checklist
        if i.id.startswith(("alerts.same_receiver.", "alerts.strobe."))
    ]
    assert accessibility_items, "hearing_impaired profile produced no alert items"
    assert all(not i.scoring for i in accessibility_items)
    assert with_hoh.sub_scores == without.sub_scores
    assert with_hoh.score == without.score


def test_a_home_with_no_safe_room_never_outscores_one_with_a_safe_room(twostory: dict):
    """Found by the grounding-auditor, S11.2.

    `safe_room.head_protection` and `safe_room.practice_the_move` were first
    written gated on `has_shelter and not seen_no_viable` while being scoring.
    A home with NO safe room therefore had fewer items to fail and scored
    **90** on severe weather where a home with one scored 75. The composite hid
    it behind the high-severity cap, but `sub_scores` is what the UI renders
    next to the `guidance_based` label.

    The fix emits the same three items either way and changes only what they
    point at, so the item COUNT must match — that is what this pins.
    """
    from app.routing.plan import RoutingConstraints

    home = HomeModel.model_validate(twostory)
    thresholds = config.get_thresholds()
    fire = compute_route_plan(home, thresholds)
    quake = compute_route_plan(home, thresholds, peril="earthquake")

    with_shelter = compute_score(
        home, fire, [], {}, thresholds,
        tornado_plan=compute_route_plan(home, thresholds, peril="tornado"),
        earthquake_plan=quake,
    )
    # avoid_stairs strands the upstairs rooms: no reachable interior shelter.
    without_shelter = compute_score(
        home, fire, [], {}, thresholds,
        tornado_plan=compute_route_plan(
            home, thresholds, RoutingConstraints(avoid_stairs=True), peril="tornado"
        ),
        earthquake_plan=quake,
    )

    def scoring_ids(breakdown):
        return {i.id for i in breakdown.checklist
                if i.scoring and i.hazard == "severe_weather"}

    assert scoring_ids(without_shelter) == scoring_ids(with_shelter), (
        "the two branches emit different scoring items, so one of them is "
        "cheaper to satisfy than the other"
    )
    assert (
        without_shelter.sub_scores["severe_weather"]
        <= with_shelter.sub_scores["severe_weather"]
    ), "having no safe room scored BETTER than having one"

    # And the honest signal is still there: a structural high-severity item.
    no_viable = [i for i in without_shelter.checklist if i.id == "safe_room.nearby_shelter"]
    assert no_viable and no_viable[0].severity == "high" and not no_viable[0].scoring


def test_no_deleted_corpus_claim_survives_anywhere_on_the_checklist(
    bungalow: dict, apartment: dict, twostory: dict
):
    """The repo-wide version of the guard, added after the grounding-auditor.

    S11.2's first attempt asserted "adhesive" was absent from `mitigation.secure*`
    items — which is exactly where it had just been removed, and nowhere near
    `object_hazards.py`, where it survived and was in fact the ONLY text a renter
    with a toppling wardrobe was shown (`mitigation_items` suppresses its own item
    for any object that produced a topple hazard). A guard scoped to the place you
    already fixed proves nothing.

    Each phrase below was deleted from the corpus on 2026-09-21 as unsourced, or
    is a figure no source carries. See backend/corpus/earthquake-securing-home.md
    "What this corpus does not claim" and docs/decisions.md 2026-09-21.
    """
    from app.models import Household
    from app.routing.object_hazards import analyze_object_hazards

    banned = [
        "adhesive",            # renter adhesive straps: deleted, unsourced
        "drywall anchor",      # "not strong enough": deleted, unsourced
        "rupture the gas",     # mechanism on no page fetched
        "top and bottom",      # sources say "two metal straps"
        "72-hour",             # no corpus support for the kit or its quantities
        "gallon per person",   # ditto
    ]

    thresholds = config.get_thresholds()
    object_thresholds = config.get_object_hazard_thresholds()

    for fixture in (bungalow, apartment, twostory):
        for tenure in ("rent", "own"):
            home = HomeModel.model_validate(fixture)
            home.household = Household(tenure=tenure)
            fire = compute_route_plan(home, thresholds)
            items = compute_score(
                home, fire, [], {}, thresholds,
                tornado_plan=compute_route_plan(home, thresholds, peril="tornado"),
                earthquake_plan=compute_route_plan(home, thresholds, peril="earthquake"),
                object_hazard_thresholds=object_thresholds,
            ).checklist
            for item in items:
                haystack = f"{item.title} {item.detail} {item.why}".lower()
                for phrase in banned:
                    assert phrase not in haystack, (
                        f"{item.id} ({tenure}) still carries the deleted claim "
                        f"{phrase!r}: {haystack!r}"
                    )

    # And the same sweep over the hazard engine directly, since its strings reach
    # the user through both the checklist and the /analyze agent tools.
    home = HomeModel.model_validate(twostory)
    for hazard in analyze_object_hazards(home, object_thresholds):
        for phrase in banned:
            assert phrase not in hazard.detail.lower(), (
                f"object hazard {hazard.rule_id} still carries {phrase!r}"
            )
