"""S3.3 (prep) deterministic tests: house/plan/profile summaries, chat system
prompt construction, the citation retry loop, and the /chat endpoint — no
network, the Anthropic client is faked (mirrors tests/test_ai.py)."""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import config
from app.ai.chat import service as chat_service
from app.ai.chat.service import (
    ChatGroundingError,
    ChatMessage,
    ChatResponse,
    build_chat_system_blocks,
    chat,
    find_invalid_chat_citations,
)
from app.ai.chat.summary import summarize_home, summarize_profiles, summarize_route_plan
from app.ai.grounded import GroundingError, valid_source_ids
from app.main import app
from app.models import HomeModel, Profile, ProfileTag
from app.routing.engine import compute_route_plan

TEST_TOKEN = "test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def bungalow_home_and_plan(bungalow: dict):
    home = HomeModel.model_validate(bungalow)
    plan = compute_route_plan(home, config.get_thresholds())
    return home, plan


# --- summaries ---------------------------------------------------------------


def test_summarize_home_lists_rooms_and_exits(bungalow_home_and_plan):
    home, _ = bungalow_home_and_plan
    text = summarize_home(home)
    for floor in home.floors:
        assert floor.name in text
        for room in floor.rooms:
            assert room.name in text
    assert "exit:" in text


def test_summarize_route_plan_lists_primary_routes_and_findings(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    text = summarize_route_plan(plan)
    for room in plan.rooms:
        assert room.room_name in text
        if room.primary is None:
            assert "NO PRIMARY ROUTE" in text
        for finding in room.findings:
            assert finding.detail in text


def test_summarize_profiles_locates_bedroom(bungalow_home_and_plan):
    home, _ = bungalow_home_and_plan
    first_room = home.floors[0].rooms[0]
    profile = Profile(
        id="p1", name="Jamie", tags=[ProfileTag.child], bedroom_room_id=first_room.id
    )
    text = summarize_profiles([profile], home)
    assert "Jamie" in text
    assert first_room.name in text
    assert "child" in text


def test_summarize_profiles_empty():
    assert summarize_profiles([], object()) == "No family profiles configured yet."


# --- system prompt -----------------------------------------------------------


def test_chat_system_blocks_embed_corpus_and_house_context_with_cache_control(
    bungalow_home_and_plan,
):
    home, plan = bungalow_home_and_plan
    blocks = build_chat_system_blocks(home, plan, [])
    assert len(blocks) == 3
    assert blocks[1]["cache_control"] == {"type": "ephemeral"}
    assert blocks[2]["cache_control"] == {"type": "ephemeral"}
    assert "nfpa-escape-planning" in blocks[0]["text"]
    assert home.name in blocks[2]["text"]
    assert home.floors[0].rooms[0].name in blocks[2]["text"]


def test_chat_system_blocks_work_without_route_plan(bungalow_home_and_plan):
    home, _ = bungalow_home_and_plan
    blocks = build_chat_system_blocks(home, None, [])
    assert len(blocks) == 3


# --- citation validator -------------------------------------------------------


def test_find_invalid_chat_citations_accepts_real_source():
    text = "Test every smoke alarm monthly [cite: nfpa-escape-planning]."
    assert find_invalid_chat_citations(text) == []


def test_find_invalid_chat_citations_rejects_fabricated_source():
    text = "Jump from the window [cite: made-up-source-2026]."
    problems = find_invalid_chat_citations(text)
    assert problems == ["made-up-source-2026"]


def test_find_invalid_chat_citations_allows_zero_citations():
    assert find_invalid_chat_citations("Sure, happy to help!") == []


# --- retry loop (faked client) ------------------------------------------------


class FakeClient:
    """Returns scripted plain-text replies in order (text content blocks)."""

    def __init__(self, replies: list[str]):
        self._replies = list(replies)
        self.calls = 0
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        self.calls += 1
        text = self._replies.pop(0)
        return SimpleNamespace(
            content=[SimpleNamespace(type="text", text=text)],
            usage=SimpleNamespace(
                input_tokens=100,
                output_tokens=50,
                cache_creation_input_tokens=0,
                cache_read_input_tokens=0,
            ),
        )


def _history(question: str) -> list[ChatMessage]:
    return [ChatMessage(role="user", content=question)]


def test_chat_retries_fabricated_citation_then_succeeds(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fake = FakeClient(
        [
            "Test alarms monthly [cite: made-up-source].",
            "Test alarms monthly [cite: nfpa-escape-planning].",
        ]
    )
    result = chat(
        _history("How often should I test smoke alarms?"),
        home,
        plan,
        client=fake,  # type: ignore[arg-type]
    )
    assert fake.calls == 2
    assert result.citations == ["nfpa-escape-planning"]


def test_chat_gives_up_after_retries(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fake = FakeClient(["Bad claim [cite: made-up-source]."] * 3)
    with pytest.raises(ChatGroundingError, match="made-up-source"):
        chat(_history("question"), home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == 1 + chat_service.MAX_CITATION_RETRIES


def test_chat_requires_history_ending_in_user_message(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    with pytest.raises(ValueError):
        chat([], home, plan)
    with pytest.raises(ValueError):
        chat([ChatMessage(role="assistant", content="hi")], home, plan)


def test_chat_response_with_no_citations_returned_as_is(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fake = FakeClient(["Sure, I can help with that."])
    result = chat(_history("hi"), home, plan, client=fake)  # type: ignore[arg-type]
    assert result == ChatResponse(reply="Sure, I can help with that.", citations=[])


# --- /chat endpoint ------------------------------------------------------------


def test_chat_endpoint_requires_token(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    body = {
        "home": home.model_dump(mode="json"),
        "route_plan": plan.model_dump(mode="json"),
        "messages": [{"role": "user", "content": "hi"}],
    }
    assert TestClient(app).post("/chat", json=body).status_code == 401


def test_chat_endpoint_happy_path(bungalow_home_and_plan, monkeypatch):
    home, plan = bungalow_home_and_plan
    canned = ChatResponse(reply="Test your alarms monthly.", citations=["nfpa-escape-planning"])
    monkeypatch.setattr("app.api_chat.chat", lambda *a, **k: canned)
    resp = TestClient(app).post(
        "/chat",
        json={
            "home": home.model_dump(mode="json"),
            "route_plan": plan.model_dump(mode="json"),
            "messages": [{"role": "user", "content": "How often should I test alarms?"}],
        },
        headers=AUTH,
    )
    assert resp.status_code == 200
    assert ChatResponse.model_validate(resp.json()) == canned


def test_chat_endpoint_works_without_route_plan_or_profiles(bungalow_home_and_plan, monkeypatch):
    home, _ = bungalow_home_and_plan
    canned = ChatResponse(reply="Hi there!", citations=[])
    monkeypatch.setattr("app.api_chat.chat", lambda *a, **k: canned)
    resp = TestClient(app).post(
        "/chat",
        json={
            "home": home.model_dump(mode="json"),
            "messages": [{"role": "user", "content": "hi"}],
        },
        headers=AUTH,
    )
    assert resp.status_code == 200


def test_chat_endpoint_maps_grounding_error_to_502(bungalow_home_and_plan, monkeypatch):
    home, plan = bungalow_home_and_plan

    def boom(*a, **k):
        raise ChatGroundingError("chat citation validation failed after retries")

    monkeypatch.setattr("app.api_chat.chat", boom)
    resp = TestClient(app).post(
        "/chat",
        json={
            "home": home.model_dump(mode="json"),
            "route_plan": plan.model_dump(mode="json"),
            "messages": [{"role": "user", "content": "hi"}],
        },
        headers=AUTH,
    )
    assert resp.status_code == 502


def test_chat_endpoint_maps_missing_key_grounding_error_to_502(
    bungalow_home_and_plan, monkeypatch
):
    """Regression: an unset ANTHROPIC_API_KEY raises the base GroundingError
    (not ChatGroundingError) from service._client(); it used to escape the
    handler and surface as a plain-text 500 instead of the deliberate 502
    that /explain and /analyze return (decisions.md 2026-07-22)."""
    home, plan = bungalow_home_and_plan

    def boom(*a, **k):
        raise GroundingError("ANTHROPIC_API_KEY is not configured on the server")

    monkeypatch.setattr("app.api_chat.chat", boom)
    resp = TestClient(app).post(
        "/chat",
        json={
            "home": home.model_dump(mode="json"),
            "route_plan": plan.model_dump(mode="json"),
            "messages": [{"role": "user", "content": "hi"}],
        },
        headers=AUTH,
    )
    assert resp.status_code == 502


def test_chat_endpoint_maps_value_error_to_422(bungalow_home_and_plan, monkeypatch):
    home, plan = bungalow_home_and_plan

    def boom(*a, **k):
        raise ValueError("history must be non-empty and end with a user message")

    monkeypatch.setattr("app.api_chat.chat", boom)
    resp = TestClient(app).post(
        "/chat",
        json={
            "home": home.model_dump(mode="json"),
            "route_plan": plan.model_dump(mode="json"),
            "messages": [{"role": "user", "content": "hi"}],
        },
        headers=AUTH,
    )
    assert resp.status_code == 422
