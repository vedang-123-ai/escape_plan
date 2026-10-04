"""Score the S11.4 eval set against the real model. Marked `live`, off by default.

This file runs the SAME cases and the SAME graders as `test_evals.py`. The only
difference is where the reply comes from: there, a stub replaying a hand-written
probe; here, the actual Anthropic API. That is the whole design — when the
account is topped up nothing has to be rewritten or re-decided, and a case that
was checked against a probe becomes a case checked against the model.

Run it with:

    ANTHROPIC_API_KEY=sk-... BACKEND_BEARER_TOKEN=live-test \\
      backend/.venv/bin/python -m pytest backend/tests/evals/ -m live -v

Expected outcome on a funded key: **18 cases scored** — 13 through `chat()`,
2 through `explain_routes()` and 3 through `run_builder()` (graded on the
BuildResult, since /build returns no prose), each printing its question, what
came back and its grader result. Each case is bound to its OWN fixture, not to one shared home. Failures
here are real findings about the prompt, not flakes — record them in BLOCKERS
rather than loosening a grader to make the run green. The one `agent`-surface
case is not run here: it needs the tool loop, which `tests/test_agent_live.py`
already covers end to end.

Without a key this file is skipped, never failed.
"""

from __future__ import annotations

import os

import pytest

from app import config
from app.ai.builder import run_builder
from app.ai.chat.service import ChatMessage, chat
from app.ai.grounded import explain_routes
from app.models import HomeModel
from app.routing.engine import compute_route_plan
from tests.conftest import load_fixture
from tests.evals.cases import BUILD_CASES, CASES, BuildEvalCase, EvalCase
from tests.evals.test_evals import _grade, _grade_build

pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(
        not os.environ.get("ANTHROPIC_API_KEY"),
        reason="ANTHROPIC_API_KEY not set — the live eval run needs the real API",
    ),
]

# Only `chat` cases run through chat(). The `explain` cases used to be swept in
# here and then driven through chat() anyway, so `grounded.RULES` — a prompt this
# session rewrote — was never exercised live and two cases did not test the
# surface they named (grounding-auditor, N2). They now go through
# `explain_routes`, graded on the text the endpoint actually returns.
CHAT_CASES = [c for c in CASES if c.surface == "chat"]
CHAT_IDS = [c.id for c in CHAT_CASES]

EXPLAIN_CASES = [c for c in CASES if c.surface == "explain"]
EXPLAIN_IDS = [c.id for c in EXPLAIN_CASES]


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(
        "BACKEND_BEARER_TOKEN", os.environ.get("BACKEND_BEARER_TOKEN", "live-test")
    )
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def _home_and_plan(fixture: str):
    home = HomeModel.model_validate(load_fixture(fixture))
    return home, compute_route_plan(home, config.get_thresholds())


def _report(case: EvalCase, reply: str, capsys) -> None:
    problems = _grade(case, reply)
    with capsys.disabled():
        print(f"\n--- {case.id} [{case.surface}/{case.fixture}] ---")
        print(f"Q: {case.question}\nA: {reply}\n")
        print("PASS" if not problems else f"FAIL: {problems}")
    assert problems == [], f"{case.id}: {problems}\n\nreply was:\n{reply}"


@pytest.mark.parametrize("case", CHAT_CASES, ids=CHAT_IDS)
def test_the_chat_assistant_satisfies_the_case(case: EvalCase, capsys):
    home, plan = _home_and_plan(case.fixture)
    result = chat([ChatMessage(role="user", content=case.question)], home, plan)
    _report(case, result.reply, capsys)


@pytest.mark.parametrize("case", EXPLAIN_CASES, ids=EXPLAIN_IDS)
def test_the_explainer_satisfies_the_case(case: EvalCase, capsys):
    """/explain returns structured output, so the graded text is the whole of it.

    The graders read prose, and an ExplainResponse is prose in three places —
    the summary, each room walkthrough, and each recommendation's claim/action.
    Citations live in a typed field rather than a [cite: ...] tag, so they are
    rendered into the graded text in that form; `find_invalid_chat_citations`
    then checks exactly the ids the endpoint would ship.
    """
    home, plan = _home_and_plan(case.fixture)
    response = explain_routes(home, plan)
    parts = [response.summary]
    for room in response.room_explanations:
        parts.append(room.primary_explanation)
        if room.secondary_explanation:
            parts.append(room.secondary_explanation)
    for rec in response.recommendations:
        parts.append(f"{rec.claim} {rec.action} [cite: {rec.source_citation}]")
    _report(case, "\n".join(parts), capsys)


@pytest.mark.parametrize("case", BUILD_CASES, ids=[c.id for c in BUILD_CASES])
def test_the_builder_satisfies_the_case(case: BuildEvalCase, capsys):
    """/build on the case's question, graded on the BuildResult the endpoint returns."""
    result = run_builder(description=case.question)
    problems = _grade_build(case, result)
    rooms = (
        [r.name for f in result.home.floors for r in f.rooms] if result.home else None
    )
    with capsys.disabled():
        print(f"\n--- {case.id} [build] ---")
        print(f"Q: {case.question}\nrooms: {rooms}  truncated: {result.truncated}")
        print(f"tools: {[t.tool_name for t in result.trace]}")
        print("PASS" if not problems else f"FAIL: {problems}")
    assert problems == [], f"{case.id}: {problems}"
