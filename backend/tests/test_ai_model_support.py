"""`ANTHROPIC_MODEL` is checked against what the AI layer actually sends.

The gap this closes: every not-live test injects a stub client, so setting
`ANTHROPIC_MODEL=claude-fable-5-1` passed the whole suite and would have broken
/explain on its first real call, because that model rejects the forced
`tool_choice` grounded.py sends. Two halves:

1. Configuration fails fast: `get_settings()` refuses an unsupported model at
   startup, with a message that says why.
2. The supported set is checked against the REAL requests. Each of the five call
   sites is driven with a client that records the `messages.create` kwargs and
   stops; every recorded request is then checked for every supported model. So a
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


class RecordingClient:
    """Records the first `messages.create` kwargs and stops the call there."""

    def __init__(self) -> None:
        self.kwargs: dict[str, Any] | None = None
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kwargs: Any):
        self.kwargs = kwargs
        raise _Recorded


def _home_and_plan():
    home = HomeModel.model_validate(load_fixture("twostory.json"))
    return home, compute_route_plan(home, config.get_thresholds())


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


CALL_SITES = {
    "explain_routes": _explain,
    "answer_grounded_question": _answer,
    "chat": _chat,
    "agent": _agent,
    "builder": _build,
}


def _record(call_site) -> dict[str, Any]:
    client = RecordingClient()
    with pytest.raises(_Recorded):
        call_site(client)
    assert client.kwargs is not None
    return client.kwargs


@pytest.mark.parametrize("site", sorted(CALL_SITES))
@pytest.mark.parametrize("model", sorted(model_support.SUPPORTED_MODELS))
def test_every_supported_model_accepts_every_request_the_code_sends(
    site: str, model: str
) -> None:
    request = _record(CALL_SITES[site])
    problems = model_support.request_incompatibilities(model, request)
    assert problems == [], f"{site} on {model}: {problems}"


def test_every_call_site_sends_the_configured_model() -> None:
    """The guard is only as good as the assumption that settings pick the model."""
    for site, call in CALL_SITES.items():
        assert _record(call)["model"] == model_support.DEFAULT_MODEL, site


def test_the_check_would_have_caught_the_fable_swap() -> None:
    """The BLOCKERS scenario, reproduced: /explain's real request on Fable 5.1."""
    request = _record(_explain)
    problems = model_support.request_incompatibilities("claude-fable-5-1", request)
    assert any("tool_choice" in p for p in problems), problems


def test_opus_5_is_refused_disabled_thinking_above_high_effort() -> None:
    """The one conditional rule: a later `effort: xhigh` would 400 on Opus 5."""
    request = {"thinking": {"type": "disabled"}, "output_config": {"effort": "xhigh"}}
    assert model_support.request_incompatibilities("claude-opus-5", request)
    request["output_config"]["effort"] = "high"
    assert model_support.request_incompatibilities("claude-opus-5", request) == []
