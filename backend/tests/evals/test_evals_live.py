"""Score the S11.4 eval set against the real model. Marked `live`, off by default.

This file runs the SAME cases and the SAME graders as `test_evals.py`. The only
difference is where the reply comes from: there, a stub replaying a hand-written
probe; here, the actual Anthropic API. That is the whole design — when the
account is topped up nothing has to be rewritten or re-decided, and a case that
was checked against a probe becomes a case checked against the model.

Run it with:

    ANTHROPIC_API_KEY=sk-... BACKEND_BEARER_TOKEN=live-test \\
      backend/.venv/bin/python -m pytest backend/tests/evals/ -m live -v

Expected outcome on a funded key: **13 cases scored** (11 `chat` + 2 `explain`),
each printing its question, the model's reply and its grader result. Failures
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
from app.ai.chat.service import ChatMessage, chat
from app.models import HomeModel
from app.routing.engine import compute_route_plan
from tests.conftest import load_fixture
from tests.evals.cases import CASES, EvalCase
from tests.evals.test_evals import _grade

pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(
        not os.environ.get("ANTHROPIC_API_KEY"),
        reason="ANTHROPIC_API_KEY not set — the live eval run needs the real API",
    ),
]

LIVE_CASES = [c for c in CASES if c.surface in ("chat", "explain")]
LIVE_IDS = [c.id for c in LIVE_CASES]


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(
        "BACKEND_BEARER_TOKEN", os.environ.get("BACKEND_BEARER_TOKEN", "live-test")
    )
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture(scope="module")
def home_and_plan():
    home = HomeModel.model_validate(load_fixture("twostory.json"))
    return home, compute_route_plan(home, config.get_thresholds())


@pytest.mark.parametrize("case", LIVE_CASES, ids=LIVE_IDS)
def test_the_model_satisfies_the_case(case: EvalCase, home_and_plan, capsys):
    home, plan = home_and_plan
    result = chat([ChatMessage(role="user", content=case.question)], home, plan)
    problems = _grade(case, result.reply)
    with capsys.disabled():
        print(f"\n--- {case.id} ---\nQ: {case.question}\nA: {result.reply}\n")
        print("PASS" if not problems else f"FAIL: {problems}")
    assert problems == [], f"{case.id}: {problems}\n\nreply was:\n{result.reply}"
