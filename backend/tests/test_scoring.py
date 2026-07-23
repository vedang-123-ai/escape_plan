"""S3.5 acceptance: the score is reproducible by hand from the documented
weights, and completing a checklist item moves it by the documented amount.

Every expected number here is hand-calculated in
docs/preparedness-score-weights.md § Worked examples. If a weight changes, both
this file and that doc must change together — that pairing IS the acceptance
criterion ("a reviewer can reproduce any fixture's score by hand").

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
from app.scoring.checklist import build_checklist, finding_items
from app.scoring.findings import Finding, finding_id
from app.scoring.recommend import _map_recommendations
from app.scoring.score import ScoreBreakdown, compute_score

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
    plan = compute_route_plan(home, config.get_thresholds())
    return compute_score(home, plan, findings or [], state or {})


def _component(breakdown: ScoreBreakdown, key: str):
    return next(c for c in breakdown.components if c.key == key)


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


# --- hand-calculated fixture scores -----------------------------------------
# Empty checklist, no agent findings. See the weights doc for the arithmetic.


def test_bungalow_baseline_score_is_75(bungalow: dict):
    # 4/4 primary = 30, 4/4 secondary = 25, no findings = 20, alarms 0/5 = 0,
    # practice 0/2 = 0  ->  75
    result = _scored(bungalow)
    assert result.score == 75
    assert _component(result, "primary_routes").earned_points == 30.0
    assert _component(result, "secondary_routes").earned_points == 25.0
    assert _component(result, "findings").earned_points == 20.0
    assert _component(result, "smoke_alarms").earned_points == 0.0
    assert _component(result, "practice").earned_points == 0.0


def test_apartment_baseline_score_is_50(apartment: dict):
    # The single-exit apartment: 5/5 primary = 30, 0/5 secondary = 0,
    # no findings = 20, alarms 0/6 = 0, practice 0/2 = 0  ->  50
    result = _scored(apartment)
    assert result.score == 50
    assert _component(result, "secondary_routes").earned_points == 0.0
    assert "0 of 5 rooms" in _component(result, "secondary_routes").detail


def test_twostory_baseline_score_is_75(twostory: dict):
    # 7/7 primary = 30, 7/7 secondary = 25, no findings = 20, alarms 0/7 = 0,
    # practice 0/2 = 0  ->  75
    result = _scored(twostory)
    assert result.score == 75


@pytest.mark.parametrize(
    "fixture_name,expected", [("bungalow", 100), ("apartment", 75), ("twostory", 100)]
)
def test_fully_checked_scores(fixture_name: str, expected: int, request):
    """All boxes ticked: alarms 15 + practice 10 land in full. The apartment
    still caps at 75 — no checklist can buy it a second way out."""
    fixture = request.getfixturevalue(fixture_name)
    baseline = _scored(fixture)
    result = _scored(fixture, state=_all_done(baseline))
    assert result.score == expected


# --- checklist completion moves the score deterministically -----------------


def test_one_alarm_item_moves_twostory_by_15_over_7(twostory: dict):
    """7 alarm items on the two-story → 15/7 ≈ 2.142857 points each.
    75 + 2.142857 = 77.14 → 77."""
    baseline = _scored(twostory)
    alarm_items = [i for i in baseline.checklist if i.component == "smoke_alarms"]
    assert len(alarm_items) == 7
    after = _scored(twostory, state={alarm_items[0].id: True})
    assert after.score == 77
    delta = (
        _component(after, "smoke_alarms").earned_points
        - _component(baseline, "smoke_alarms").earned_points
    )
    assert delta == pytest.approx(15 / 7)


def test_meeting_point_item_is_worth_5(bungalow: dict):
    baseline = _scored(bungalow)
    after = _scored(bungalow, state={"practice.meeting_point": True})
    assert _component(after, "practice").earned_points == 5.0
    assert after.score == baseline.score + 5


def test_each_bungalow_alarm_item_is_worth_3(bungalow: dict):
    # 5 alarm items on a 1-floor/1-bedroom home → 15/5 = 3.00 each, exactly.
    baseline = _scored(bungalow)
    alarm_ids = [i.id for i in baseline.checklist if i.component == "smoke_alarms"]
    assert len(alarm_ids) == 5
    for count in range(1, 6):
        result = _scored(bungalow, state={i: True for i in alarm_ids[:count]})
        assert result.score == 75 + 3 * count


def test_non_scoring_items_do_not_move_the_score(apartment: dict):
    """Ticking a routes item must not buy points — the routes components move
    only when the model actually changes and the engine re-runs."""
    baseline = _scored(apartment)
    route_items = [i for i in baseline.checklist if i.category == "routes"]
    assert route_items and all(not i.scoring for i in route_items)
    after = _scored(apartment, state={i.id: True for i in route_items})
    assert after.score == baseline.score


# --- findings component ------------------------------------------------------


def test_high_severity_finding_costs_10(apartment: dict):
    result = _scored(apartment, findings=[_high("r_bed1")])
    assert _component(result, "findings").earned_points == 10.0
    assert result.score == 40  # 50 - 10


def test_findings_component_floors_at_zero(apartment: dict):
    result = _scored(apartment, findings=[_high("r_bed1")] * 3)
    assert _component(result, "findings").earned_points == 0.0
    assert result.score == 30


def test_mixed_severities_deduct_per_documented_table(bungalow: dict):
    findings = [
        _high("r_bedroom"),
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
    # 20 - (10 + 4 + 1) = 5
    result = _scored(bungalow, findings=findings)
    assert _component(result, "findings").earned_points == 5.0
    assert result.score == 60


# --- purity and explainability ----------------------------------------------


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


def test_components_sum_to_score(twostory: dict):
    result = _scored(twostory, state={"practice.meeting_point": True})
    assert sum(c.earned_points for c in result.components) == pytest.approx(80.0)
    assert result.score == 80


def test_every_component_explains_itself(bungalow: dict):
    result = _scored(bungalow)
    assert [c.key for c in result.components] == [
        "primary_routes",
        "secondary_routes",
        "findings",
        "smoke_alarms",
        "practice",
    ]
    assert sum(c.max_points for c in result.components) == 100.0
    for component in result.components:
        assert component.detail and component.rationale
        assert 0.0 <= component.earned_points <= component.max_points


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
    for item in result.checklist:
        assert item.source_citation, f"{item.id} makes a claim with no citation"


def test_done_state_round_trips(bungalow: dict):
    result = _scored(bungalow, state={"alarm.test_monthly": True})
    done = {i.id for i in result.checklist if i.done}
    assert done == {"alarm.test_monthly"}


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
    "fixture_name,expected", [("bungalow", 75), ("apartment", 50), ("twostory", 75)]
)
def test_score_endpoint_matches_the_engine(fixture_name: str, expected: int, request):
    fixture = request.getfixturevalue(fixture_name)
    resp = TestClient(app).post("/score", json={"home": fixture}, headers=AUTH)
    assert resp.status_code == 200
    assert ScoreBreakdown.model_validate(resp.json()).score == expected


def test_score_endpoint_accepts_findings_and_state(apartment: dict):
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
    assert ScoreBreakdown.model_validate(resp.json()).score == 45  # 50 - 10 + 5


def test_score_endpoint_honours_constraints(twostory: dict):
    """Grandpa's mobility_limited profile bans stairs; upstairs rooms lose routes
    and the score must drop accordingly — the score reflects the plan on screen."""
    resp = TestClient(app).post(
        "/score",
        json={"home": twostory, "constraints": {"avoid_stairs": True}},
        headers=AUTH,
    )
    assert resp.status_code == 200
    assert ScoreBreakdown.model_validate(resp.json()).score < 75


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
    assert result.score == 50  # unchanged vs. the no-recommendations baseline
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
