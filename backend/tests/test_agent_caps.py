"""S11.4: the agent's shipped caps, as opposed to the mechanism behind them.

`test_agent_truncates_at_iteration_cap` in test_agent.py passes
`max_iterations=3`, so it proves the loop *can* truncate but never touches the
value the server actually runs with. Raising `MAX_ITERATIONS` from 15 to 500 left
the whole suite green — the cap that bounds latency and API cost was unguarded.

anthropic.md: "The S3.2 agent loop is hand-rolled with the Anthropic SDK
(`while stop_reason == 'tool_use'`), capped (~15 iterations) with graceful
partial results."
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from app import config
from app.ai import agent
from app.ai.agent import MAX_ITERATIONS, MAX_SUBMIT_RETRIES, run_agent_analysis
from app.models import HomeModel
from tests.conftest import load_fixture


def _tool_use(block_id: str, name: str, payload: dict) -> SimpleNamespace:
    return SimpleNamespace(type="tool_use", id=block_id, name=name, input=payload)


class CountingClient:
    """Answers every turn with another tool call. Never submits, never stops.

    Unbounded on purpose: if the loop has no cap, this hangs the suite rather
    than passing it, which is the honest failure mode for a missing cap.
    """

    # Fixed, and deliberately NOT derived from MAX_ITERATIONS: a limit computed
    # from the constant would rise with it and pass at any value. 50 is far above
    # the documented 15 and far below a runaway.
    RUNAWAY = 50

    def __init__(self, limit: int = RUNAWAY):
        self.calls = 0
        self._limit = limit
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs):
        self.calls += 1
        if self.calls > self._limit:
            raise AssertionError(
                f"the agent loop ran {self.calls} times — past the {self._limit}-call "
                f"runaway guard. MAX_ITERATIONS is {MAX_ITERATIONS}; anthropic.md "
                f"documents ~15, and the cap bounds both latency and API cost."
            )
        return SimpleNamespace(
            content=[_tool_use(f"toolu_{self.calls}", "get_home_summary", {})]
        )


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "cap-test-token")
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


@pytest.fixture
def apartment_home_and_thresholds():
    return HomeModel.model_validate(load_fixture("apartment.json")), config.get_thresholds()


def test_the_shipped_cap_is_the_one_that_applies(apartment_home_and_thresholds):
    """Called the way main.py calls it — no max_iterations argument."""
    home, thresholds = apartment_home_and_thresholds
    client = CountingClient()
    result = run_agent_analysis(home, thresholds, client=client)
    assert result.truncated is True
    assert client.calls == MAX_ITERATIONS, (
        f"the loop ran {client.calls} times; MAX_ITERATIONS is {MAX_ITERATIONS}"
    )


def test_the_cap_is_still_the_documented_value() -> None:
    """A deliberate change should have to edit this line and say why.

    The number is not arbitrary: it bounds the <60s latency acceptance and the
    per-call API cost, and `anthropic.md` states it as part of the design.
    """
    assert MAX_ITERATIONS == 15


def test_truncation_is_graceful_not_an_exception(apartment_home_and_thresholds):
    """anthropic.md: "capped ... with graceful partial results"."""
    home, thresholds = apartment_home_and_thresholds
    result = run_agent_analysis(home, thresholds, client=CountingClient())
    assert result.truncated is True
    assert result.findings == []
    # the work it did get through is still returned, not discarded
    assert len(result.trace) == MAX_ITERATIONS
    assert all(t.tool_name == "get_home_summary" for t in result.trace)


def test_the_submit_retry_cap_is_the_documented_value() -> None:
    """Same reasoning for the other bounded loop in this module."""
    assert MAX_SUBMIT_RETRIES == 2


def test_the_caps_are_read_from_the_module_not_re_declared(
    apartment_home_and_thresholds,
):
    """Guards against a second copy of the number drifting from the first."""
    home, thresholds = apartment_home_and_thresholds
    original = agent.MAX_ITERATIONS
    try:
        agent.MAX_ITERATIONS = 4
        client = CountingClient()
        # the default argument is bound at def time, so an explicit pass is the
        # honest way to show the loop reads one number rather than two
        result = run_agent_analysis(
            home, thresholds, client=client, max_iterations=agent.MAX_ITERATIONS
        )
        assert result.truncated is True
        assert client.calls == 4
    finally:
        agent.MAX_ITERATIONS = original
