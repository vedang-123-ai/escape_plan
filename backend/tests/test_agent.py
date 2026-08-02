"""S3.2 deterministic tests: tool dispatch, corpus search, evidence/citation
validation, the agent loop (scripted Anthropic client — no network), and the
/analyze endpoint.

No ANTHROPIC_API_KEY is available in this environment, so — unlike S3.1's
test_ai_live.py — there is no live counterpart to these tests yet. Everything
here is exercised against real fixtures and the real deterministic engines;
only the Anthropic model call itself is faked.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import config
from app.ai import agent
from app.ai.agent import (
    MAX_SUBMIT_RETRIES,
    AgentError,
    AnalysisResult,
    Finding,
    ToolCallRecord,
    _dispatch_tool,
    _validate_findings,
    run_agent_analysis,
    search_corpus,
)
from app.main import app
from app.models import HomeModel

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _tool_use(tool_id: str, name: str, tool_input: dict) -> SimpleNamespace:
    return SimpleNamespace(type="tool_use", id=tool_id, name=name, input=tool_input)


class ScriptedClient:
    """Returns a scripted sequence of assistant turns (each a list of content blocks)."""

    def __init__(self, turns: list[list[SimpleNamespace]]):
        self._turns = list(turns)
        self.calls = 0
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        self.calls += 1
        if not self._turns:
            raise AssertionError("ScriptedClient ran out of scripted turns")
        return SimpleNamespace(content=self._turns.pop(0))


@pytest.fixture
def apartment_home_and_thresholds(apartment: dict):
    return HomeModel.model_validate(apartment), config.get_thresholds()


@pytest.fixture
def twostory_home_and_thresholds(twostory: dict):
    return HomeModel.model_validate(twostory), config.get_thresholds()


@pytest.fixture
def blocked_home_and_thresholds(bungalow_blocked: dict):
    return HomeModel.model_validate(bungalow_blocked), config.get_thresholds()


# --- search_corpus (pure) ----------------------------------------------------


def test_search_corpus_finds_window_egress_guidance():
    results = search_corpus("window egress")
    assert results
    assert any(r["source_id"] for r in results)


def test_search_corpus_no_match_returns_empty():
    assert search_corpus("zzqxvbnmqq") == []


# --- tool dispatch (pure, against real fixtures + real engines) -------------


def test_get_home_summary(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    out = _dispatch_tool("get_home_summary", {}, home, thresholds)
    room_ids = {r["id"] for f in out["floors"] for r in f["rooms"]}
    assert "r_hall" in room_ids and "r_bed1" in room_ids


def test_get_room_returns_openings(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    out = _dispatch_tool("get_room", {"room_id": "r_hall"}, home, thresholds)
    opening_ids = {o["id"] for o in out["openings"]}
    assert "d_entry" in opening_ids


def test_get_room_unknown_id(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    out = _dispatch_tool("get_room", {"room_id": "nope"}, home, thresholds)
    assert "error" in out


def test_list_openings(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    out = _dispatch_tool("list_openings", {"floor_id": "f1"}, home, thresholds)
    assert any(o["id"] == "d_entry" for o in out["openings"])


def test_compute_routes_flags_apartment_bottleneck(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    out = _dispatch_tool("compute_routes", {}, home, thresholds)
    bottleneck_ids = {b["opening_id"] for b in out["bottlenecks"]}
    assert "d_entry" in bottleneck_ids


def test_check_egress_flags_undersized_kids_window(twostory_home_and_thresholds):
    home, thresholds = twostory_home_and_thresholds
    out = _dispatch_tool("check_egress", {"opening_id": "w_kids"}, home, thresholds)
    assert out["viable"] is False
    assert any("width" in r for r in out["reasons"])


def test_check_egress_unknown_opening(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    out = _dispatch_tool("check_egress", {"opening_id": "nope"}, home, thresholds)
    assert "error" in out


def test_check_obstructions_names_the_object_and_the_measured_move(
    blocked_home_and_thresholds,
):
    """The point of the tool: not "something blocks this door" but which thing,
    and how far it has to go. Both numbers come from the engine, never the model."""
    home, thresholds = blocked_home_and_thresholds
    out = _dispatch_tool("check_obstructions", {}, home, thresholds)
    assert len(out["obstructions"]) == 1
    found = out["obstructions"][0]
    assert found["kind"] == "blocks_opening"
    assert found["object_ids"] == ["o_wardrobe_blocking"]
    assert found["object_categories"] == ["wardrobe"]
    assert found["opening_id"] == "d_living_bedroom"
    assert found["suggested_move_m"] == pytest.approx(0.85)
    assert found["required_width_m"] == pytest.approx(thresholds.door_min_width_m)
    # The engine's own phrasing rides along so the model re-words a measured
    # sentence instead of inventing a distance that sounds plausible.
    assert "0.85" in found["detail"] and "wardrobe" in found["detail"]


def test_check_obstructions_room_filter_scopes_to_one_room(
    blocked_home_and_thresholds,
):
    home, thresholds = blocked_home_and_thresholds
    assert _dispatch_tool(
        "check_obstructions", {"room_id": "r_bedroom"}, home, thresholds
    )["obstructions"]
    assert (
        _dispatch_tool("check_obstructions", {"room_id": "r_living"}, home, thresholds)[
            "obstructions"
        ]
        == []
    )


def test_check_obstructions_on_a_furniture_free_home_reports_nothing(
    twostory_home_and_thresholds,
):
    """No objects means no culprits — the tool must not manufacture advice for
    a home it has nothing to say about."""
    home, thresholds = twostory_home_and_thresholds
    out = _dispatch_tool("check_obstructions", {}, home, thresholds)
    assert out["obstructions"] == []


def test_check_obstructions_does_not_mutate_the_home(blocked_home_and_thresholds):
    """Every agent tool is read-only. This one re-rasterizes rooms with objects
    withdrawn, which is exactly the shape of code that could leak a mutation."""
    home, thresholds = blocked_home_and_thresholds
    before = home.model_dump(mode="json")
    _dispatch_tool("check_obstructions", {}, home, thresholds)
    assert home.model_dump(mode="json") == before


def test_check_obstructions_is_registered_as_a_tool():
    tool = next(t for t in agent.TOOLS if t["name"] == "check_obstructions")
    # room_id is a filter, not a requirement — the agent must be able to sweep
    # the whole home in one call.
    assert "required" not in tool["input_schema"]
    assert set(tool["input_schema"]["properties"]) == {"room_id"}


def test_dispatch_unknown_tool_raises(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    with pytest.raises(AgentError):
        _dispatch_tool("delete_home", {}, home, thresholds)


# --- evidence + citation validation -----------------------------------------


def _finding(evidence: list[str], citation: str = "irc-2021-r310") -> Finding:
    return Finding(
        severity="high",
        room_ids=["r_bed_kids"],
        finding="Only one viable way out.",
        evidence=evidence,
        recommendation="Replace the window with an egress-compliant one.",
        citation=citation,
    )


def test_validate_findings_keeps_valid_evidence_and_citation():
    trace = [ToolCallRecord(id="toolu_1", tool_name="check_egress", input={}, output={})]
    kept, dropped = _validate_findings([_finding(["toolu_1"])], trace)
    assert len(kept) == 1
    assert dropped == []


def test_validate_findings_drops_missing_evidence():
    kept, dropped = _validate_findings([_finding([])], [])
    assert kept == []
    assert len(dropped) == 1


def test_validate_findings_drops_unresolvable_evidence():
    trace = [ToolCallRecord(id="toolu_1", tool_name="check_egress", input={}, output={})]
    kept, dropped = _validate_findings([_finding(["toolu_999"])], trace)
    assert kept == []
    assert "unknown" in dropped[0]


def test_validate_findings_drops_fabricated_citation():
    trace = [ToolCallRecord(id="toolu_1", tool_name="check_egress", input={}, output={})]
    kept, dropped = _validate_findings(
        [_finding(["toolu_1"], citation="made-up-source")], trace
    )
    assert kept == []
    assert "citation" in dropped[0]


def test_validate_findings_stamps_stable_server_side_ids():
    from app.scoring.findings import finding_id

    trace = [ToolCallRecord(id="toolu_1", tool_name="check_egress", input={}, output={})]
    submitted = _finding(["toolu_1"])
    submitted.id = "model-chose-this"  # server must overwrite, never trust the model
    kept, _ = _validate_findings([submitted], trace)
    assert kept[0].id == finding_id(
        submitted.severity, submitted.room_ids, submitted.finding
    )
    assert kept[0].id != "model-chose-this"
    # Deterministic: validating an identical finding again yields the same id.
    again, _ = _validate_findings([_finding(["toolu_1"])], trace)
    assert again[0].id == kept[0].id


# --- full agent loop (scripted client) --------------------------------------


def test_agent_flags_apartment_single_exit_with_evidence(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    turns = [
        [_tool_use("toolu_1", "get_home_summary", {})],
        [_tool_use("toolu_2", "compute_routes", {})],
        [
            _tool_use(
                "toolu_3",
                "submit_findings",
                {
                    "findings": [
                        {
                            "severity": "high",
                            "room_ids": ["r_bed1", "r_bed2", "r_hall", "r_kitchen", "r_living"],
                            "finding": (
                                "Every room in the apartment depends on the single "
                                "entry door 'd_entry' — there is no other exterior exit."
                            ),
                            "evidence": ["toolu_2"],
                            "recommendation": (
                                "Identify a second exterior exit (e.g. a compliant "
                                "window egress) so a fire near the entry doesn't trap "
                                "the household."
                            ),
                            "citation": "nfpa-escape-planning",
                        }
                    ]
                },
            )
        ],
    ]
    result = run_agent_analysis(home, thresholds, client=ScriptedClient(turns))
    assert result.truncated is False
    assert len(result.findings) == 1
    assert "d_entry" in result.findings[0].finding
    assert result.findings[0].evidence == ["toolu_2"]
    assert result.dropped == []
    # the trace is real tool output, not just an echo of the model's claim
    bottleneck_call = next(t for t in result.trace if t.id == "toolu_2")
    assert any(b["opening_id"] == "d_entry" for b in bottleneck_call.output["bottlenecks"])


def test_agent_flags_kids_room_undersized_window_via_check_egress(
    twostory_home_and_thresholds,
):
    home, thresholds = twostory_home_and_thresholds
    turns = [
        [_tool_use("toolu_1", "get_room", {"room_id": "r_bed_kids"})],
        [_tool_use("toolu_2", "check_egress", {"opening_id": "w_kids"})],
        [
            _tool_use(
                "toolu_3",
                "submit_findings",
                {
                    "findings": [
                        {
                            "severity": "high",
                            "room_ids": ["r_bed_kids"],
                            "finding": (
                                "The Kids' Bedroom's only window (w_kids) is too narrow "
                                "to serve as a code-compliant emergency exit; the door "
                                "to the landing is the room's only real way out."
                            ),
                            "evidence": ["toolu_1", "toolu_2"],
                            "recommendation": (
                                "Replace w_kids with a window that meets the minimum "
                                "clear opening width and area."
                            ),
                            "citation": "irc-2021-r310",
                        }
                    ]
                },
            )
        ],
    ]
    result = run_agent_analysis(home, thresholds, client=ScriptedClient(turns))
    assert len(result.findings) == 1
    assert result.findings[0].room_ids == ["r_bed_kids"]
    egress_call = next(t for t in result.trace if t.tool_name == "check_egress")
    assert egress_call.output["viable"] is False


def test_agent_flags_blocking_wardrobe_with_check_obstructions_evidence(
    blocked_home_and_thresholds,
):
    """The whole reason the tool exists: the agent turns a deterministic
    attribution into cited, actionable advice, and the number in its finding is
    traceable to the engine's measurement rather than to the model."""
    home, thresholds = blocked_home_and_thresholds
    turns = [
        [_tool_use("toolu_1", "get_home_summary", {})],
        [_tool_use("toolu_2", "check_obstructions", {})],
        [_tool_use("toolu_3", "search_corpus", {"topic": "keep exits clear"})],
        [
            _tool_use(
                "toolu_4",
                "submit_findings",
                {
                    "findings": [
                        {
                            "severity": "high",
                            "room_ids": ["r_bedroom"],
                            "finding": (
                                "A wardrobe is standing in front of the Bedroom's "
                                "door (d_living_bedroom) — there is no walkable path "
                                "to it at all."
                            ),
                            "evidence": ["toolu_2"],
                            "recommendation": (
                                "Move the wardrobe about 0.85 m clear of the "
                                "doorway to restore a full-width escape path."
                            ),
                            "citation": "usfa-escape-plans",
                        }
                    ]
                },
            )
        ],
    ]
    result = run_agent_analysis(home, thresholds, client=ScriptedClient(turns))
    assert result.truncated is False
    assert result.dropped == []
    assert len(result.findings) == 1
    # The advice survives validation *because* a real obstruction call backs it.
    obstruction_call = next(
        t for t in result.trace if t.tool_name == "check_obstructions"
    )
    assert result.findings[0].evidence == [obstruction_call.id]
    measured = obstruction_call.output["obstructions"][0]["suggested_move_m"]
    assert f"{measured:.2f}" in result.findings[0].recommendation


def _bad_submission(call_id: str):
    return _tool_use(
        call_id,
        "submit_findings",
        {
            "findings": [
                {
                    "severity": "low",
                    "room_ids": ["r_hall"],
                    "finding": "Unsubstantiated claim.",
                    "evidence": ["toolu_does_not_exist"],
                    "recommendation": "N/A",
                    "citation": "nfpa-escape-planning",
                }
            ]
        },
    )


def test_agent_drops_findings_with_bad_evidence_after_retries(
    apartment_home_and_thresholds,
):
    """A submission that never fixes its evidence is bounced MAX_SUBMIT_RETRIES
    times, then returned as-is with the findings dropped (graceful partial)."""
    home, thresholds = apartment_home_and_thresholds
    turns = [[_tool_use("toolu_1", "get_home_summary", {})]] + [
        [_bad_submission(f"toolu_submit_{i}")] for i in range(1 + MAX_SUBMIT_RETRIES)
    ]
    result = run_agent_analysis(home, thresholds, client=ScriptedClient(turns))
    assert result.findings == []
    assert len(result.dropped) == 1
    assert result.truncated is False


def test_agent_rejected_submission_can_be_corrected_on_resubmit(
    apartment_home_and_thresholds,
):
    """Invalid evidence refs get one corrective round-trip instead of silently
    gutting the result — the corrected resubmission is accepted."""
    home, thresholds = apartment_home_and_thresholds
    good_finding = {
        "severity": "high",
        "room_ids": ["r_hall"],
        "finding": "Every room depends on the single entry door d_entry.",
        "evidence": ["toolu_1"],
        "recommendation": "Establish a second exterior exit.",
        "citation": "nfpa-escape-planning",
    }
    bad_finding = dict(good_finding, evidence=["compute_routes:bottlenecks"])
    turns = [
        [_tool_use("toolu_1", "compute_routes", {})],
        [_tool_use("toolu_2", "submit_findings", {"findings": [bad_finding]})],
        [_tool_use("toolu_3", "submit_findings", {"findings": [good_finding]})],
    ]
    result = run_agent_analysis(home, thresholds, client=ScriptedClient(turns))
    assert len(result.findings) == 1
    assert result.findings[0].evidence == ["toolu_1"]
    assert result.dropped == []
    assert result.truncated is False


def test_agent_truncates_at_iteration_cap(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    turns = [[_tool_use(f"toolu_{i}", "get_home_summary", {})] for i in range(3)]
    result = run_agent_analysis(
        home, thresholds, client=ScriptedClient(turns), max_iterations=3
    )
    assert result.truncated is True
    assert result.findings == []
    assert len(result.trace) == 3


def test_agent_empty_findings_is_valid(apartment_home_and_thresholds):
    home, thresholds = apartment_home_and_thresholds
    turns = [
        [_tool_use("toolu_1", "get_home_summary", {})],
        [_tool_use("toolu_2", "submit_findings", {"findings": []})],
    ]
    result = run_agent_analysis(home, thresholds, client=ScriptedClient(turns))
    assert result.findings == []
    assert result.truncated is False
    assert result.dropped == []


# --- /analyze endpoint -------------------------------------------------------


def test_analyze_endpoint_requires_token(apartment: dict):
    resp = TestClient(app).post("/analyze", json={"home": apartment})
    assert resp.status_code == 401


def test_analyze_endpoint_happy_path(apartment: dict, monkeypatch):
    canned = AnalysisResult(findings=[], trace=[], truncated=False, dropped=[])
    monkeypatch.setattr("app.main.run_agent_analysis", lambda *a, **k: canned)
    resp = TestClient(app).post("/analyze", json={"home": apartment}, headers=AUTH)
    assert resp.status_code == 200
    assert AnalysisResult.model_validate(resp.json()) == canned


def test_analyze_endpoint_maps_agent_error_to_502(apartment: dict, monkeypatch):
    def boom(*a, **k):
        raise AgentError("ANTHROPIC_API_KEY is not configured on the server")

    monkeypatch.setattr("app.main.run_agent_analysis", boom)
    resp = TestClient(app).post("/analyze", json={"home": apartment}, headers=AUTH)
    assert resp.status_code == 502
