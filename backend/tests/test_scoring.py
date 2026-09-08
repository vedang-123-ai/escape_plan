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
    # Pass thresholds exactly as /score does, so these tests see the same
    # checklist the endpoint returns (including the R310 egress-window items).
    return compute_score(home, plan, findings or [], state or {}, thresholds)


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
    # The only `scoring: true` items are 5 smoke-alarm items (fire, info, -5
    # each) and 1 practice.meeting_point item (general, info, -5).
    # fire = 100-30=70, earthquake=severe_weather=100-5=95.
    # composite = 0.5*70 + 0.25*95 + 0.25*95 = 82.5 -> 83 (round-half-up).
    result = _scored(bungalow)
    assert result.sub_scores == {"fire": 70, "earthquake": 95, "severe_weather": 95}
    assert result.score == 83


def test_apartment_baseline_score(apartment: dict):
    # 6 smoke-alarm items + 1 meeting-point item are the only scoring items.
    # fire = 100-35=65, earthquake=severe_weather=95.
    # composite = 0.5*65 + 0.25*95 + 0.25*95 = 80.
    result = _scored(apartment)
    assert result.sub_scores == {"fire": 65, "earthquake": 95, "severe_weather": 95}
    assert result.score == 80
    # The single front door means no secondary egress — but routes items are
    # non-scoring, so that fact never shows up as a point deduction.
    route_items_ = [i for i in result.checklist if i.category == "routes"]
    assert route_items_ and all(not i.scoring for i in route_items_)


def test_twostory_baseline_score(twostory: dict):
    # 7 smoke-alarm items + 1 meeting-point item.
    # fire = 100-40=60, earthquake=severe_weather=95.
    # composite = 0.5*60 + 0.25*95 + 0.25*95 = 77.5 -> 78.
    result = _scored(twostory)
    assert result.sub_scores == {"fire": 60, "earthquake": 95, "severe_weather": 95}
    assert result.score == 78


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
    assert after.score == 80


def test_meeting_point_item_moves_all_three_sub_scores(bungalow: dict):
    """practice.meeting_point is hazard="general" — it counts toward every
    peril's sub-score, not just one."""
    baseline = _scored(bungalow)
    after = _scored(bungalow, state={"practice.meeting_point": True})
    assert after.sub_scores["fire"] == baseline.sub_scores["fire"] + 5
    assert after.sub_scores["earthquake"] == baseline.sub_scores["earthquake"] + 5
    assert after.sub_scores["severe_weather"] == baseline.sub_scores["severe_weather"] + 5
    assert after.score == 88


def test_each_bungalow_alarm_item_moves_fire_by_5(bungalow: dict):
    # 5 alarm items on a 1-floor/1-bedroom home, each worth 5 fire points.
    baseline = _scored(bungalow)
    alarm_ids = [i.id for i in baseline.checklist if i.category == "smoke_alarm"]
    assert len(alarm_ids) == 5
    expected_score_by_count = [83, 85, 88, 90, 93, 95]
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
    "fixture_name,expected", [("bungalow", 83), ("apartment", 80), ("twostory", 78)]
)
def test_score_endpoint_matches_the_engine(fixture_name: str, expected: int, request):
    fixture = request.getfixturevalue(fixture_name)
    resp = TestClient(app).post("/score", json={"home": fixture}, headers=AUTH)
    assert resp.status_code == 200
    assert ScoreBreakdown.model_validate(resp.json()).score == expected


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
    assert result.score == 80  # unchanged vs. the no-recommendations baseline
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
