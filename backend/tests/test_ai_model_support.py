"""`ANTHROPIC_MODEL` is checked against what the AI layer actually sends.

The gap this closes: every not-live test injects a stub client, so setting
`ANTHROPIC_MODEL=claude-fable-5-1` passed the whole suite and would have broken
/explain on its first real call, because that model rejects the forced
`tool_choice` grounded.py sends. Two halves:

1. Configuration fails fast: `get_settings()` refuses an unsupported model at
   startup, with a message that says why.
2. The supported set is checked against the REAL requests. Each of the five call
   sites is driven with a client that records every `messages.create` call,
   through one tool round-trip or citation retry where the site has a loop; every
   recorded request is then checked for every supported model. So a
   later change that adds forced tool use to the builder, or an effort level Opus 5
   refuses with thinking disabled, fails here instead of in production.
"""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any

import pytest

from app import config
from app.ai import model_support
from app.ai.agent import run_agent_analysis
from app.ai.builder import run_builder
from app.ai.chat.service import ChatMessage, chat
from app.ai.grounded import answer_grounded_question, explain_routes
from app.models import HomeModel
from app.routing.engine import compute_route_plan
from tests.conftest import load_fixture


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("BACKEND_BEARER_TOKEN", "model-support-test")
    monkeypatch.delenv("ANTHROPIC_MODEL", raising=False)
    config.get_settings.cache_clear()
    yield
    config.get_settings.cache_clear()


# ---------------------------------------------------------------------------
# 1. Configuration fails fast


def test_the_default_model_is_supported() -> None:
    assert config.get_settings().anthropic_model == model_support.DEFAULT_MODEL
    assert model_support.DEFAULT_MODEL in model_support.SUPPORTED_MODELS


def test_render_yaml_pins_a_supported_model() -> None:
    """The deployed value is the one that matters; it lives outside the backend."""
    render = (config.BACKEND_DIR.parent / "render.yaml").read_text()
    lines = render.splitlines()
    key = next(i for i, line in enumerate(lines) if "key: ANTHROPIC_MODEL" in line)
    value = lines[key + 1].split("value:", 1)[1].split("#", 1)[0].strip()
    assert value in model_support.SUPPORTED_MODELS, value


@pytest.mark.parametrize("model", ["claude-fable-5-1", "claude-mythos-5-1", "claude-opus-5-5"])
def test_a_model_that_rejects_forced_tool_use_is_refused_at_startup(
    model: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("ANTHROPIC_MODEL", model)
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match="tool_choice"):
        config.get_settings()


def test_a_model_that_only_rejects_disabled_thinking_is_refused_too(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ANTHROPIC_MODEL", "claude-fable-5")
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match="disabled"):
        config.get_settings()


def test_an_unknown_model_is_refused_rather_than_assumed_fine(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ANTHROPIC_MODEL", "claude-some-future-model")
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match="not been checked"):
        config.get_settings()


def test_the_error_names_the_supported_set(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_MODEL", "claude-fable-5-1")
    config.get_settings.cache_clear()
    with pytest.raises(RuntimeError, match=model_support.DEFAULT_MODEL):
        config.get_settings()


def test_no_model_is_both_supported_and_known_to_reject_a_parameter() -> None:
    rejected = (
        model_support.FORCED_TOOL_CHOICE_REJECTED | model_support.THINKING_DISABLED_REJECTED
    )
    assert not (model_support.SUPPORTED_MODELS & rejected)


# ---------------------------------------------------------------------------
# 2. The supported set is checked against the requests the code really builds


class _Recorded(Exception):
    pass


_USAGE = SimpleNamespace(
    input_tokens=1, output_tokens=1, cache_creation_input_tokens=0, cache_read_input_tokens=0
)


def _tool_use(name: str, tool_input: dict) -> SimpleNamespace:
    return SimpleNamespace(type="tool_use", id="toolu_1", name=name, input=tool_input)


def _text(text: str) -> SimpleNamespace:
    return SimpleNamespace(type="text", text=text)


class RecordingClient:
    """Records the kwargs of EVERY `messages.create` call.

    Replays `scripted` responses first, chosen so each call site makes a second,
    different request (a tool round-trip, or a citation retry), then stops the
    call site at the next call. A parameter added only on a later pass of a loop
    (say, forcing submit_findings on the agent's last iteration) is recorded too.
    """

    def __init__(self, scripted: list[list[SimpleNamespace]]) -> None:
        self._scripted = list(scripted)
        self.requests: list[dict[str, Any]] = []
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs: Any):
        self.requests.append(kwargs)
        if not self._scripted:
            raise _Recorded
        return SimpleNamespace(content=self._scripted.pop(0), usage=_USAGE)


def _home_and_plan():
    home = HomeModel.model_validate(load_fixture("twostory.json"))
    return home, compute_route_plan(home, config.get_thresholds())


_FABRICATED_EXPLANATION = {
    "summary": "s",
    "room_explanations": [
        {"room_id": "r", "room_name": "R", "primary_explanation": "Go out the door."}
    ],
    "recommendations": [
        {"claim": "c", "action": "a", "source_citation": "not-a-real-source"}
    ],
}


def _explain(client):
    home, plan = _home_and_plan()
    explain_routes(home, plan, client=client)


def _answer(client):
    answer_grounded_question("how often should I test smoke alarms?", client=client)


def _chat(client):
    home, plan = _home_and_plan()
    chat([ChatMessage(role="user", content="hi")], home, plan, client=client)


def _agent(client):
    home, _ = _home_and_plan()
    run_agent_analysis(home, config.get_thresholds(), client=client)


def _build(client):
    run_builder(description="a one-room cabin", client=client)


# (call site, the responses that make it issue a second request)
CALL_SITES = {
    # A fabricated citation forces the retry request.
    "explain_routes": (_explain, [[_tool_use("submit_explanation", _FABRICATED_EXPLANATION)]]),
    # One request by design: a plain-text answer, no loop.
    "answer_grounded_question": (_answer, []),
    "chat": (_chat, [[_text("Test them monthly [cite: not-a-real-source].")]]),
    # A tool call forces the next loop iteration.
    "agent": (_agent, [[_tool_use("get_home_summary", {})]]),
    "builder": (_build, [[_tool_use("start_home", {"name": "Cabin"})]]),
}


def _record(site: str) -> list[dict[str, Any]]:
    call, scripted = CALL_SITES[site]
    client = RecordingClient(scripted)
    with pytest.raises(_Recorded):
        call(client)
    assert len(client.requests) == len(scripted) + 1, (
        f"{site}: expected {len(scripted) + 1} requests, got {len(client.requests)}"
    )
    return client.requests


@pytest.mark.parametrize("site", sorted(CALL_SITES))
@pytest.mark.parametrize("model", sorted(model_support.SUPPORTED_MODELS))
def test_every_supported_model_accepts_every_request_the_code_sends(
    site: str, model: str
) -> None:
    for n, request in enumerate(_record(site), start=1):
        problems = model_support.request_incompatibilities(model, request)
        assert problems == [], f"{site} request {n} on {model}: {problems}"


def test_every_call_site_sends_the_configured_model() -> None:
    """The guard is only as good as the assumption that settings pick the model."""
    for site in CALL_SITES:
        for request in _record(site):
            assert request["model"] == model_support.DEFAULT_MODEL, site


def test_the_check_would_have_caught_the_fable_swap() -> None:
    """The BLOCKERS scenario, reproduced: /explain's real request on Fable 5.1."""
    request = _record("explain_routes")[0]
    problems = model_support.request_incompatibilities("claude-fable-5-1", request)
    assert any("tool_choice" in p for p in problems), problems


def test_opus_5_is_refused_disabled_thinking_above_high_effort() -> None:
    """The one conditional rule: a later `effort: xhigh` would 400 on Opus 5."""
    request = {"thinking": {"type": "disabled"}, "output_config": {"effort": "xhigh"}}
    assert model_support.request_incompatibilities("claude-opus-5", request)
    request["output_config"]["effort"] = "high"
    assert model_support.request_incompatibilities("claude-opus-5", request) == []
