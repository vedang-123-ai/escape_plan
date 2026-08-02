"""S3.2 live-API acceptance tests for the agentic inspector (marked `live`,
excluded by default).

Run: cd backend && ANTHROPIC_API_KEY=sk-ant-... python3 -m pytest tests/test_agent_live.py -m live -v

Encodes the S3.2 acceptance criteria from docs/playbook/S3-2.md: on
apartment.json the agent flags the single-point-of-failure exit (d_entry) with
real evidence; on twostory.json it flags the Kids' Bedroom's undersized-only
window (w_kids); zero findings without evidence links; each run < 60s. Written
key-blocked (mirrors tests/test_ai_live.py) so P1's key session can run it
immediately. On first run each case writes tests/golden/agent_<case>.json for
hand review (commit it); later runs assert structural stability — the planted
issue is still flagged — never exact wording.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import pytest

from app import config
from app.ai.agent import AnalysisResult, run_agent_analysis
from app.ai.grounded import valid_source_ids
from app.models import HomeModel
from tests.conftest import load_fixture

pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(
        not os.environ.get("ANTHROPIC_API_KEY"),
        reason="ANTHROPIC_API_KEY not set — live agent tests need the real API",
    ),
]

GOLDEN_DIR = Path(__file__).parent / "golden"


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(
        "BACKEND_BEARER_TOKEN", os.environ.get("BACKEND_BEARER_TOKEN", "live-test")
    )
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _run(fixture_name: str) -> tuple[AnalysisResult, float]:
    home = HomeModel.model_validate(load_fixture(fixture_name))
    start = time.monotonic()
    result = run_agent_analysis(home, config.get_thresholds())
    return result, time.monotonic() - start


def _assert_hard_invariants(result: AnalysisResult, latency: float) -> None:
    """The non-negotiable S3.2 acceptance invariants, regardless of snapshot."""
    assert not result.truncated, "agent hit the iteration cap without submitting"
    assert latency < 60, f"latency {latency:.1f}s over the <60s acceptance budget"
    trace_ids = {t.id for t in result.trace}
    sources = valid_source_ids()
    for f in result.findings:
        assert f.evidence, f"finding without evidence survived validation: {f.finding}"
        assert set(f.evidence) <= trace_ids, (
            f"finding references tool calls not in the trace: {f.evidence}"
        )
        assert f.citation in sources, f"unknown citation '{f.citation}': {f.finding}"


def _snapshot(case: str, result: AnalysisResult, latency: float) -> dict | None:
    """Write the golden on first run (skip for review); return it otherwise.

    Stores findings + dropped + which tools ran — not full trace payloads,
    which are large and nondeterministically ordered.
    """
    GOLDEN_DIR.mkdir(exist_ok=True)
    path = GOLDEN_DIR / f"agent_{case}.json"
    payload = {
        "case": case,
        "latency_s": round(latency, 2),
        "findings": [f.model_dump(mode="json") for f in result.findings],
        "dropped": result.dropped,
        "tools_used": sorted({t.tool_name for t in result.trace}),
    }
    if not path.exists():
        path.write_text(json.dumps(payload, indent=2) + "\n")
        pytest.skip(f"golden snapshot written to {path} — review and commit it")
    return json.loads(path.read_text())


def test_apartment_agent_flags_single_exit():
    """Acceptance: the single-exit apartment's d_entry bottleneck is found."""
    result, latency = _run("apartment.json")
    _assert_hard_invariants(result, latency)
    assert result.findings, "agent found nothing in the planted single-exit apartment"

    keywords = ("d_entry", "single", "bottleneck", "only exit", "one exit")
    flagged = [
        f
        for f in result.findings
        if any(k in f.finding.lower() or k in f.recommendation.lower() for k in keywords)
    ]
    assert flagged, (
        "no finding mentions the single-point-of-failure entry door; findings were: "
        + "; ".join(f.finding for f in result.findings)
    )

    snapshot = _snapshot("apartment", result, latency)
    snapshot_severities = {f["severity"] for f in snapshot["findings"]}
    assert snapshot_severities & {f.severity for f in result.findings}, (
        "severity profile drifted completely from the reviewed snapshot"
    )


def test_twostory_agent_flags_kids_bedroom_window():
    """Acceptance: the Kids' Bedroom's undersized-only window (w_kids) is found."""
    result, latency = _run("twostory.json")
    _assert_hard_invariants(result, latency)
    assert result.findings, "agent found nothing in the planted twostory home"

    flagged = [
        f
        for f in result.findings
        if "r_bed_kids" in f.room_ids
        or "w_kids" in f.finding
        or "kids" in f.finding.lower()
    ]
    assert flagged, (
        "no finding touches the Kids' Bedroom / w_kids window; findings were: "
        + "; ".join(f.finding for f in result.findings)
    )

    snapshot = _snapshot("twostory", result, latency)
    snapshot_rooms = {r for f in snapshot["findings"] for r in f["room_ids"]}
    current_rooms = {r for f in result.findings for r in f.room_ids}
    assert snapshot_rooms & current_rooms, (
        "flagged rooms drifted completely from the reviewed snapshot: "
        f"{sorted(current_rooms)} vs snapshot {sorted(snapshot_rooms)}"
    )


def test_blocked_bungalow_agent_names_the_wardrobe():
    """The check_obstructions half: a real model, given the deterministic
    attribution, must name the object and carry the measured move into its
    advice — not shrug that 'something' blocks the door."""
    result, latency = _run("bungalow-blocked.json")
    _assert_hard_invariants(result, latency)
    assert result.findings, "agent found nothing in the planted blocked bungalow"

    assert "check_obstructions" in {t.tool_name for t in result.trace}, (
        "the agent never called check_obstructions on a home whose bedroom door "
        "is physically blocked; tools used: "
        + ", ".join(sorted({t.tool_name for t in result.trace}))
    )

    flagged = [
        f
        for f in result.findings
        if "wardrobe" in (f.finding + f.recommendation).lower()
        or "o_wardrobe_blocking" in f.finding
    ]
    assert flagged, (
        "no finding names the wardrobe blocking d_living_bedroom; findings were: "
        + "; ".join(f.finding for f in result.findings)
    )

    # The move distance is the engine's, so it must appear verbatim rather than
    # as a number the model found reasonable.
    measured = {
        o["suggested_move_m"]
        for t in result.trace
        if t.tool_name == "check_obstructions"
        for o in t.output["obstructions"]
    }
    advice = " ".join(f.finding + " " + f.recommendation for f in flagged)
    assert any(f"{m:.2f}" in advice or f"{m:.1f}" in advice for m in measured), (
        f"advice quotes no measured distance (engine measured {sorted(measured)}): {advice}"
    )

    _snapshot("bungalow_blocked", result, latency)
