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


# --- uncited safety claims (S11.44, AUD-030) -----------------------------------

CITED = "Test every smoke alarm once a month [cite: usfa-smoke-alarms]."
UNCITED = "Test every smoke alarm once a month."
MIXED = (
    "Practice the plan twice a year [cite: nfpa-escape-planning]. "
    "Keep a flashlight under every bed."
)


def test_uncited_safety_claim_is_retried_with_a_corrective_message(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fake = FakeClient([UNCITED, CITED])
    seen: list[list[dict]] = []
    create = fake.messages.create
    fake.messages.create = lambda **kw: (seen.append(list(kw["messages"])), create(**kw))[1]
    result = chat(_history("How often should I test alarms?"), home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == 2
    assert result == ChatResponse(reply=CITED, citations=["usfa-smoke-alarms"])
    correction = seen[1][-1]["content"]
    assert UNCITED in correction and "[cite: source-id]" in correction


def test_still_uncited_after_one_retry_becomes_the_deferral(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fake = FakeClient([UNCITED, UNCITED, CITED])
    result = chat(_history("q"), home, plan, client=fake)  # type: ignore[arg-type]
    # One extra call at most for uncited claims, never the full retry budget.
    assert fake.calls == 2
    assert result == ChatResponse(reply=chat_service.UNCITED_DEFERRAL, citations=[])


def test_mixed_cited_and_uncited_reply_is_not_shipped(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fake = FakeClient([MIXED, MIXED])
    result = chat(_history("q"), home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == 2
    assert result.reply == chat_service.UNCITED_DEFERRAL
    assert result.citations == []


@pytest.mark.parametrize(
    "reply",
    [
        "Hi! What would you like to know about your escape plan?",
        "Get out if you safely can, then call 911.",
        "Get out now if it is safe. Call 911 from outside.",
        "My sources don't cover flooding, so I won't guess. Please consult your "
        "local emergency management office.",
        "Your Bedroom's primary route goes through the Hall to the front door.",
        "Do you want me to walk through the Bedroom route?",
        "From the Bedroom, go down the Hall to the front door.",
        "Use the Bedroom window as your second way out.",
        "Feel free to ask anything else!",
        "Check the Plan tab to see both routes.",
    ],
    ids=[
        "small-talk",
        "911-one-sentence",
        "911-two-sentences",
        "deferral",
        "route-description",
        "clarifying-question",
        "route-narration",
        "route-window",
        "sign-off",
        "app-pointer",
    ],
)
def test_legitimate_uncited_replies_pass_untouched(bungalow_home_and_plan, reply):
    home, plan = bungalow_home_and_plan
    fake = FakeClient([reply])
    result = chat(_history("q"), home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == 1
    assert result == ChatResponse(reply=reply, citations=[])


def test_fabricated_id_is_still_rejected_before_the_claim_check(bungalow_home_and_plan):
    """A fabricated id on a cited claim must not be waved through as 'cited'."""
    home, plan = bungalow_home_and_plan
    fake = FakeClient(["Test alarms monthly [cite: made-up-source]."] * 3)
    with pytest.raises(ChatGroundingError, match="made-up-source"):
        chat(_history("q"), home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == 3


@pytest.mark.parametrize(
    "replies,calls,deferred",
    [
        # Two fabricated retries leave no call for the uncited one: defer, no 4th call.
        (["X [cite: made-up-a].", "X [cite: made-up-b].", UNCITED, CITED], 3, True),
        # Fabricated, then uncited: the uncited retry is the 3rd and last call.
        (["X [cite: made-up-a].", UNCITED, CITED], 3, False),
        # Uncited, then fabricated: the uncited retry was the last chance, so defer.
        ([UNCITED, "X [cite: made-up-a].", CITED], 2, True),
    ],
    ids=["fab-fab-uncited", "fab-uncited-ok", "uncited-fab-defers"],
)
def test_total_calls_never_exceed_the_budgeted_three(bungalow_home_and_plan, replies, calls, deferred):
    """S11.27 charges BUDGET_COST_SINGLE_CALL (3) per /chat; the mix of retries cannot exceed it."""
    from app.rate_limit import BUDGET_COST_SINGLE_CALL

    home, plan = bungalow_home_and_plan
    fake = FakeClient(replies)
    result = chat(_history("q"), home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == calls <= BUDGET_COST_SINGLE_CALL == 1 + chat_service.MAX_CITATION_RETRIES
    assert (result.reply == chat_service.UNCITED_DEFERRAL) is deferred


class _Clock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def test_no_time_for_the_retry_defers_instead_of_504(bungalow_home_and_plan):
    """S11.29: with under MIN_START_S left the retry may not start. That is a deferral, not a 504."""
    from app.ai.client import CHAT_DEADLINE_S, MIN_START_S, Deadline

    home, plan = bungalow_home_and_plan
    clock = _Clock()
    fake = FakeClient([UNCITED, CITED])
    create = fake.messages.create

    def slow_create(**kw):
        clock.now += CHAT_DEADLINE_S - MIN_START_S + 1  # leaves 19 s: one under the floor
        return create(**kw)

    fake.messages.create = slow_create
    result = chat(
        _history("q"), home, plan, client=fake, deadline=Deadline(CHAT_DEADLINE_S, clock=clock)  # type: ignore[arg-type]
    )
    assert fake.calls == 1
    assert result == ChatResponse(reply=chat_service.UNCITED_DEFERRAL, citations=[])


def test_exactly_min_start_left_still_gets_the_retry(bungalow_home_and_plan):
    from app.ai.client import CHAT_DEADLINE_S, MIN_START_S, Deadline

    home, plan = bungalow_home_and_plan
    clock = _Clock()
    fake = FakeClient([UNCITED, CITED])
    create = fake.messages.create

    def slow_create(**kw):
        if fake.calls == 0:
            clock.now += CHAT_DEADLINE_S - MIN_START_S  # leaves exactly the floor
        return create(**kw)

    fake.messages.create = slow_create
    result = chat(
        _history("q"), home, plan, client=fake, deadline=Deadline(CHAT_DEADLINE_S, clock=clock)  # type: ignore[arg-type]
    )
    assert fake.calls == 2 and result.reply == CITED


# The emergency path after a rejected reply (grounding-auditor, cases A-D). Before S11.44 an
# emergency reply with one uncited sentence shipped; the retry must never leave the user worse off.
EMERGENCY_Q = "there's smoke in the hallway what do I do"
EMERGENCY_UNCITED = "Get out if safe, then call 911. Stay low under the smoke on your way out."


def test_retry_out_of_time_after_uncited_rejection_defers_not_504(bungalow_home_and_plan):
    """A: the retry starts, takes too long, and a further call cannot start."""
    from app.ai.client import CHAT_DEADLINE_S, Deadline

    home, plan = bungalow_home_and_plan
    clock = _Clock()
    fake = FakeClient([EMERGENCY_UNCITED, "Stay low [cite: made-up-a].", CITED])
    create = fake.messages.create

    def slow_create(**kw):
        clock.now += 50
        return create(**kw)

    fake.messages.create = slow_create
    result = chat(
        _history(EMERGENCY_Q), home, plan, client=fake, deadline=Deadline(CHAT_DEADLINE_S, clock=clock)  # type: ignore[arg-type]
    )
    assert result == ChatResponse(reply=chat_service.UNCITED_DEFERRAL, citations=[])


def test_fabricated_id_after_uncited_rejection_defers_not_502(bungalow_home_and_plan):
    """B: uncited, then fabricated. No further retry, no ChatGroundingError."""
    home, plan = bungalow_home_and_plan
    fake = FakeClient([EMERGENCY_UNCITED, "Stay low [cite: made-up-a].", "Stay low [cite: made-up-b]."])
    result = chat(_history(EMERGENCY_Q), home, plan, client=fake)  # type: ignore[arg-type]
    assert fake.calls == 2
    assert result.reply == chat_service.UNCITED_DEFERRAL


@pytest.mark.parametrize("exc_kind", ["deadline", "api"])
def test_retry_call_raising_after_uncited_rejection_defers(bungalow_home_and_plan, exc_kind):
    """C: the retry call itself fails. The deferral (which leads with 911) is returned instead."""
    import anthropic
    import httpx

    from app.ai.client import DeadlineExceeded

    home, plan = bungalow_home_and_plan
    fake = FakeClient([EMERGENCY_UNCITED])
    create = fake.messages.create

    def failing_second(**kw):
        if fake.calls == 1:
            fake.calls += 1
            if exc_kind == "deadline":
                raise DeadlineExceeded("out of time")
            raise anthropic.APITimeoutError(request=httpx.Request("POST", "https://x"))
        return create(**kw)

    fake.messages.create = failing_second
    result = chat(_history(EMERGENCY_Q), home, plan, client=fake)  # type: ignore[arg-type]
    assert result.reply == chat_service.UNCITED_DEFERRAL


def test_first_call_api_error_still_raises(bungalow_home_and_plan):
    """Without a rejected reply in hand there is nothing to defer from: the endpoint maps the error."""
    import anthropic
    import httpx

    home, plan = bungalow_home_and_plan
    fake = FakeClient([])

    def boom(**kw):
        raise anthropic.APITimeoutError(request=httpx.Request("POST", "https://x"))

    fake.messages.create = boom
    with pytest.raises(anthropic.APITimeoutError):
        chat(_history("q"), home, plan, client=fake)  # type: ignore[arg-type]


def test_retry_that_drops_the_911_line_defers(bungalow_home_and_plan):
    """D: a cited retry that lost the emergency line is not shipped."""
    home, plan = bungalow_home_and_plan
    fake = FakeClient(
        [EMERGENCY_UNCITED, "Stay low under the smoke on your way out [cite: usfa-escape-plans]."]
    )
    result = chat(_history(EMERGENCY_Q), home, plan, client=fake)  # type: ignore[arg-type]
    assert result.reply == chat_service.UNCITED_DEFERRAL
    assert "call 911" in result.reply


def test_retry_that_keeps_the_911_line_and_cites_ships(bungalow_home_and_plan):
    home, plan = bungalow_home_and_plan
    fixed = (
        "Get out if safe, then call 911. Stay low under the smoke on your way out "
        "[cite: usfa-escape-plans]."
    )
    fake = FakeClient([EMERGENCY_UNCITED, fixed])
    result = chat(_history(EMERGENCY_Q), home, plan, client=fake)  # type: ignore[arg-type]
    assert result == ChatResponse(reply=fixed, citations=["usfa-escape-plans"])


def test_the_deferral_reuses_the_prompts_own_wording_and_cites_nothing():
    """No new safety advice: both instructions in it already appear in CHAT_RULES."""
    rules = " ".join(chat_service.CHAT_RULES.lower().split())
    deferral = chat_service.UNCITED_DEFERRAL.lower()
    assert "get out if safe, then call 911" in rules and "get out if safe, then call 911" in deferral
    phrase = "local fire department or emergency management office"
    assert phrase in rules and phrase in deferral
    assert "[cite:" not in deferral
    from app.ai.chat.claims import uncited_safety_claims

    assert uncited_safety_claims(chat_service.UNCITED_DEFERRAL) == []
    # Rule 4: in an emergency the 911 line comes FIRST. The deferral may be answering one.
    from tests.evals.graders import says_call_911_first

    assert says_call_911_first(chat_service.UNCITED_DEFERRAL) is None


def test_the_prompt_example_obeys_the_rule_it_teaches():
    """The CHAT_RULES example used to be an uncited imperative, teaching the shape the server rejects."""
    from app.ai.chat.claims import uncited_safety_claims

    rules = chat_service.CHAT_RULES
    example = rules[rules.index('(e.g. "') + 7 : rules.index('").')]
    assert uncited_safety_claims(" ".join(example.split())) == []


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
