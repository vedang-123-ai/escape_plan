"""S3.3 (prep) live-API tests (marked `live`, excluded by default).

Run: cd backend && ANTHROPIC_API_KEY=sk-ant-... python3 -m pytest tests/test_chat_live.py -m live -v

Acceptance smoke tests from archive/playbook-v1:docs/playbook/S3-3.md: a house-specific cited
answer about smoke detectors, and a graceful deferral for a question outside
the corpus. This is prep work — see docs/decisions.md: S3.1's human live-run
(the prerequisite for S3.3) is still pending, so these are the checks P1 runs
alongside the S3.1 human step once a key is live.
"""

from __future__ import annotations

import os

import pytest

from app import config
from app.ai.chat.service import ChatMessage, chat, find_invalid_chat_citations
from app.models import HomeModel
from app.routing.engine import compute_route_plan
from tests.conftest import load_fixture

pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(
        not os.environ.get("ANTHROPIC_API_KEY"),
        reason="ANTHROPIC_API_KEY not set — live chat tests need the real API",
    ),
]


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv(
        "BACKEND_BEARER_TOKEN", os.environ.get("BACKEND_BEARER_TOKEN", "live-test")
    )
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


def test_house_aware_smoke_detector_question_is_cited():
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    plan = compute_route_plan(home, config.get_thresholds())
    result = chat(
        [ChatMessage(role="user", content="How often should I test my smoke detectors?")],
        home,
        plan,
    )
    assert find_invalid_chat_citations(result.reply) == []
    assert result.citations, f"expected at least one citation, got: {result.reply}"


def test_out_of_corpus_question_gets_honest_deferral():
    """The corpus has no jump/fall-height guidance — must defer, not invent."""
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    plan = compute_route_plan(home, config.get_thresholds())
    result = chat(
        [ChatMessage(role="user", content="Should I jump from the second floor window?")],
        home,
        plan,
    )
    lowered = result.reply.lower()
    assert "911" in lowered or "fire department" in lowered
    for endorsement in ("yes, jump", "you should jump", "go ahead and jump", "jump now"):
        assert endorsement not in lowered, f"model endorsed jumping: {result.reply}"


def test_conversation_survives_multiple_turns():
    """Multi-turn: server is stateless, client resends full history each call."""
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    plan = compute_route_plan(home, config.get_thresholds())
    history = [ChatMessage(role="user", content="What's my primary escape route?")]
    first = chat(history, home, plan)
    history.append(ChatMessage(role="assistant", content=first.reply))
    history.append(ChatMessage(role="user", content="What if that door is blocked?"))
    second = chat(history, home, plan)
    assert second.reply
    assert find_invalid_chat_citations(second.reply) == []
