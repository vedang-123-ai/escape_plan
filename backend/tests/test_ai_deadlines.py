"""S11.29 (AUD-035): AI calls time out, and every AI loop stops at a wall-clock deadline.

Nothing here calls Anthropic. A stub client stands in, and time is a fake clock the stub moves
forward, so no test sleeps. The thing under test is that each loop STOPS (calls made, not just an
exception raised), that the factory sets a timeout and a single retry, and that the endpoints hand
the loops a deadline shorter than the phone's own timeout.

The live check that a slow /build really stops server-side needs a funded key and is owed to
S11.49 (BLOCKERS).
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import config, rate_limit
from app.ai import agent, builder, client as ai_client
from app.ai import grounded
from app.ai.agent import run_agent_analysis
from app.ai.builder import BuildResult, run_builder
from app.ai.chat import service as chat_service
from app.ai.chat.service import ChatMessage, ChatResponse, chat
from app.ai.client import (
    ANALYZE_DEADLINE_S,
    BUILD_DEADLINE_S,
    CHAT_DEADLINE_S,
    EXPLAIN_DEADLINE_S,
    MAX_RETRIES,
    MIN_ATTEMPT_S,
    Deadline,
    DeadlineExceeded,
    build_client,
)
from app.main import app
from app.models import HomeModel
from app.routing.engine import compute_route_plan
from tests.conftest import load_fixture

TEST_TOKEN = "deadline-test-token-not-a-secret"
AUTH = {"Authorization": f"Bearer {TEST_TOKEN}"}


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", TEST_TOKEN)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key-not-real")
    monkeypatch.setenv("AI_RATE_PER_MIN", "100000")
    monkeypatch.setenv("AI_RATE_BURST", "100000")
    monkeypatch.setenv("AI_DAILY_CALL_BUDGET", "100000")
    config.get_settings.cache_clear()
    rate_limit.budget.reset()
    yield
    config.get_settings.cache_clear()
    rate_limit.budget.reset()


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class SlowClient:
    """Every model call 'takes' `step` seconds of fake time and returns `make(call_number)`.

    Records the keyword arguments of each call so a test can read the `timeout` that was sent.
    """

    def __init__(self, clock: FakeClock, step: float, make) -> None:
        self._clock = clock
        self._step = step
        self._make = make
        self.calls = 0
        self.kwargs: list[dict] = []
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        self.calls += 1
        self.kwargs.append(kwargs)
        self._clock.now += self._step
        return self._make(self.calls)


USAGE = SimpleNamespace(
    input_tokens=1, output_tokens=1, cache_creation_input_tokens=0, cache_read_input_tokens=0
)


def _tool_use(block_id: str, name: str, payload: dict) -> SimpleNamespace:
    return SimpleNamespace(type="tool_use", id=block_id, name=name, input=payload)


# --- the Deadline itself ------------------------------------------------------


def test_deadline_counts_down_with_its_clock():
    clock = FakeClock()
    d = Deadline(100, clock=clock)
    assert d.remaining() == pytest.approx(100)
    clock.now += 30
    assert d.remaining() == pytest.approx(70)
    assert not d.expired()
    clock.now += 71
    assert d.expired()


def test_a_call_is_refused_when_too_little_time_is_left():
    clock = FakeClock()
    d = Deadline(MIN_ATTEMPT_S + 5, clock=clock)
    d.require_time("x")  # plenty
    clock.now += 6  # now MIN_ATTEMPT_S - 1 left
    with pytest.raises(DeadlineExceeded):
        d.require_time("x")


def test_attempt_timeout_leaves_room_for_the_sdk_retry():
    """Half of what is left, so attempt + one retry stays inside the budget."""
    clock = FakeClock()
    d = Deadline(100, clock=clock)
    assert d.attempt_timeout() == pytest.approx(50)
    clock.now += 85  # 15 left: half would be 7.5, under the floor
    assert d.attempt_timeout() == MIN_ATTEMPT_S


# --- the factory --------------------------------------------------------------


def test_factory_sets_an_explicit_timeout_and_one_retry():
    c = build_client("k")
    assert c.max_retries == MAX_RETRIES == 1
    assert c.timeout.read == BUILD_DEADLINE_S
    assert c.timeout.connect < 10


@pytest.mark.parametrize(
    "module", [grounded, agent, builder, chat_service], ids=lambda m: m.__name__
)
def test_every_ai_module_builds_its_client_through_the_factory(module):
    """The four modules used to each call anthropic.Anthropic(...) with SDK defaults
    (600 s, 2 retries). If one regresses, its client loses the explicit settings."""
    c = module._client()
    assert c.max_retries == 1
    assert c.timeout.read == BUILD_DEADLINE_S


def test_each_model_call_carries_a_timeout_that_fits_the_remaining_budget():
    clock = FakeClock()
    d = Deadline(60, clock=clock)
    stub = SlowClient(clock, 1, lambda n: SimpleNamespace(content=[]))
    ai_client.create_message(stub, d, "x", model="m")
    sent = stub.kwargs[0]["timeout"]
    assert MIN_ATTEMPT_S <= sent <= 60 / 2 + 1e-6


# --- each loop stops at its deadline ------------------------------------------


def test_builder_stops_at_the_deadline_and_never_returns_a_half_built_home():
    clock = FakeClock()
    stub = SlowClient(
        clock,
        30,  # each call eats 30 s of a 100 s budget
        lambda n: SimpleNamespace(
            content=[_tool_use(f"t{n}", "start_home", {"name": "X"})]
        ),
    )
    with pytest.raises(DeadlineExceeded):
        run_builder(description="x", client=stub, deadline=Deadline(100, clock=clock))
    # 100 s budget, 30 s per call, 10 s floor: calls start with 100, 70, 40 and 10 s left
    # (10 is not under the floor); a fifth would start with -20 s and is refused.
    assert stub.calls == 4
    assert stub.calls < builder.MAX_ITERATIONS


def test_agent_stops_at_the_deadline_with_an_honest_truncated_result():
    clock = FakeClock()
    home = HomeModel.model_validate(load_fixture("apartment.json"))
    stub = SlowClient(
        clock,
        20,
        lambda n: SimpleNamespace(content=[_tool_use(f"toolu_{n}", "get_home_summary", {})]),
    )
    result = run_agent_analysis(
        home, config.get_thresholds(), client=stub, deadline=Deadline(100, clock=clock)
    )
    assert result.truncated is True
    assert result.findings == []
    assert len(result.trace) == stub.calls  # the evidence gathered so far is kept
    assert stub.calls == 5  # 100, 80, 60, 40, 20 left; the 6th would start at 0
    assert stub.calls < agent.MAX_ITERATIONS


def test_grounded_citation_retries_respect_the_deadline():
    """A model that keeps citing nonsense used to get all 3 attempts regardless of time."""
    clock = FakeClock()
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    plan = compute_route_plan(home, config.get_thresholds())
    bad = {
        "summary": "s",
        "recommendations": [
            {"title": "t", "detail": "d", "priority": "high", "source_citation": "nope"}
        ],
    }
    stub = SlowClient(
        clock,
        20,
        lambda n: SimpleNamespace(content=[_tool_use(f"toolu_{n}", "submit_explanation", bad)], usage=USAGE),
    )
    with pytest.raises(DeadlineExceeded):
        grounded.explain_routes(home, plan, client=stub, deadline=Deadline(25, clock=clock))
    # 25 s budget: first call starts (25 left), runs 20 s, 5 left is under the floor.
    assert stub.calls == 1
    assert stub.calls < 1 + grounded.MAX_CITATION_RETRIES


def test_chat_citation_retries_respect_the_deadline():
    clock = FakeClock()
    home = HomeModel.model_validate(load_fixture("bungalow.json"))
    stub = SlowClient(
        clock,
        20,
        lambda n: SimpleNamespace(
            content=[SimpleNamespace(type="text", text="Do it [cite: made-up-source].")],
            usage=USAGE,
        ),
    )
    with pytest.raises(DeadlineExceeded):
        chat(
            [ChatMessage(role="user", content="hi")],
            home,
            client=stub,
            deadline=Deadline(25, clock=clock),
        )
    assert stub.calls == 1
    assert stub.calls < 1 + chat_service.MAX_CITATION_RETRIES


# --- the caps still hold when time is plentiful -------------------------------


def test_iteration_caps_still_apply_with_a_generous_deadline():
    clock = FakeClock()
    stub = SlowClient(
        clock,
        0.001,
        lambda n: SimpleNamespace(
            content=[_tool_use(f"t{n}", "start_home", {"name": "X"})]
        ),
    )
    result = run_builder(
        description="x", client=stub, max_iterations=4, deadline=Deadline(10_000, clock=clock)
    )
    assert result.truncated is True and result.home is None
    assert stub.calls == 4


# --- the endpoints give the loops a deadline under the phone's timeout --------

# The iOS request.timeoutInterval values read from escape_plan/Networking on 2026-10-04.
# They are copied here on purpose: the test pins the relationship "server gives up first".
PHONE_TIMEOUT_S = {"build": 180, "analyze": 90, "chat": 60, "explain": 90}


def test_server_deadlines_are_under_the_phones_timeouts():
    assert BUILD_DEADLINE_S < PHONE_TIMEOUT_S["build"]
    assert ANALYZE_DEADLINE_S < PHONE_TIMEOUT_S["analyze"]
    assert CHAT_DEADLINE_S < PHONE_TIMEOUT_S["chat"]
    assert EXPLAIN_DEADLINE_S < PHONE_TIMEOUT_S["explain"]


@pytest.fixture
def http() -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


def test_build_endpoint_passes_its_deadline_and_maps_expiry_to_504(
    http: TestClient, monkeypatch: pytest.MonkeyPatch
):
    seen: dict = {}

    def boom(**kwargs):
        seen["deadline"] = kwargs["deadline"]
        raise DeadlineExceeded("build ran out of time")

    monkeypatch.setattr("app.main.run_builder", boom)
    r = http.post("/build", json={"description": "a small bungalow"}, headers=AUTH)
    assert r.status_code == 504
    assert "took too long" in r.json()["detail"]
    assert seen["deadline"].seconds == BUILD_DEADLINE_S


def test_analyze_endpoint_passes_its_deadline(
    http: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    seen: dict = {}

    def fake(home, thresholds, **kwargs):
        seen["deadline"] = kwargs["deadline"]
        raise DeadlineExceeded("analysis ran out of time")

    monkeypatch.setattr("app.main.run_agent_analysis", fake)
    r = http.post("/analyze", json={"home": bungalow}, headers=AUTH)
    assert r.status_code == 504
    assert seen["deadline"].seconds == ANALYZE_DEADLINE_S


def test_chat_endpoint_passes_its_deadline(
    http: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    seen: dict = {}

    def fake(*args, **kwargs):
        seen["deadline"] = kwargs["deadline"]
        return ChatResponse(reply="Test monthly.", citations=[])

    monkeypatch.setattr("app.api_chat.chat", fake)
    r = http.post(
        "/chat",
        json={"home": bungalow, "messages": [{"role": "user", "content": "hi"}]},
        headers=AUTH,
    )
    assert r.status_code == 200
    assert seen["deadline"].seconds == CHAT_DEADLINE_S


def test_explain_endpoint_passes_its_deadline(
    http: TestClient, bungalow: dict, monkeypatch: pytest.MonkeyPatch
):
    seen: dict = {}

    def fake(home, plan, profile=None, **kwargs):
        seen["deadline"] = kwargs["deadline"]
        raise DeadlineExceeded("explain ran out of time")

    monkeypatch.setattr("app.main.explain_routes", fake)
    plan = http.post("/routes", json={"home": bungalow}, headers=AUTH).json()
    r = http.post("/explain", json={"home": bungalow, "route_plan": plan}, headers=AUTH)
    assert r.status_code == 504
    assert seen["deadline"].seconds == EXPLAIN_DEADLINE_S


def test_the_request_contracts_are_unchanged(http: TestClient, monkeypatch: pytest.MonkeyPatch):
    """The deadline is server-side only: /build still accepts exactly the old body."""
    monkeypatch.setattr(
        "app.main.run_builder",
        lambda **kw: BuildResult(home=None, trace=[], truncated=True, issues=["x"]),
    )
    r = http.post("/build", json={"description": "a house"}, headers=AUTH)
    assert r.status_code == 200
    assert r.json()["truncated"] is True


# --- the builder's image is cacheable -------------------------------------------


def test_builder_marks_the_image_turn_cacheable_and_text_only_builds_have_no_marker():
    clock = FakeClock()
    turn = lambda n: SimpleNamespace(content=[_tool_use(f"t{n}", "start_home", {"name": "X"})])
    with_image = SlowClient(clock, 0.001, turn)
    run_builder(
        image_b64="aGVsbG8=", client=with_image, max_iterations=2, deadline=Deadline(1000, clock=clock)
    )
    first_turn = with_image.kwargs[0]["messages"][0]["content"]
    image_block = next(b for b in first_turn if b["type"] == "image")
    assert image_block["cache_control"] == {"type": "ephemeral"}
    assert all("cache_control" not in b for b in first_turn if b["type"] == "text")

    text_only = SlowClient(clock, 0.001, turn)
    run_builder(description="x", client=text_only, max_iterations=1, deadline=Deadline(1000, clock=clock))
    assert all("cache_control" not in b for b in text_only.kwargs[0]["messages"][0]["content"])
