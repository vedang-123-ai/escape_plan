"""Which Claude models the AI layer's request shape is valid on.

`ANTHROPIC_MODEL` looks like a free choice and is not. Two parameters the AI
layer sends are rejected with a 400 by some current models:

- `tool_choice={"type": "tool", ...}` (forced tool use, `grounded.explain_routes`)
  is not supported on Claude Fable 5.1, Claude Mythos 5.1 and Claude Opus 5.5.
- `thinking={"type": "disabled"}` (all of grounded, chat and agent, set for a
  measured latency reason recorded in each file) is rejected by the Fable/Mythos 5
  and 5.1 models and by Claude Opus 5.5, whose thinking cannot be turned off;
  Claude Opus 5 accepts it only at effort `high` or below.

Every not-live test injects a stub client, so a model swap that breaks /explain
at runtime would pass the whole suite. `app.config.get_settings` therefore
refuses to start with a model outside `SUPPORTED_MODELS`, the same fail-fast
stance it takes on a too-short JWT secret, and `tests/test_ai_model_support.py`
checks the requests the code actually builds against these tables.

Facts from Anthropic's current API reference (claude-api skill, cached
2026-06-24), checked 2026-09-24. `SUPPORTED_MODELS` means "this request shape is
accepted", not "behaviour verified": only `claude-sonnet-5` has been exercised
live. Add a model here only after confirming it accepts both parameters above.
"""

from __future__ import annotations

from typing import Any, Mapping

DEFAULT_MODEL = "claude-sonnet-5"

FORCED_TOOL_CHOICE_REJECTED: frozenset[str] = frozenset(
    {"claude-fable-5-1", "claude-mythos-5-1", "claude-opus-5-5"}
)
"""Models that return 400 on `tool_choice` of type `tool` or `any`."""

THINKING_DISABLED_REJECTED: frozenset[str] = frozenset(
    {
        "claude-fable-5",
        "claude-fable-5-1",
        "claude-mythos-5",
        "claude-mythos-5-1",
        "claude-opus-5-5",
    }
)
"""Models that return 400 on `thinking={"type": "disabled"}` at any effort."""

THINKING_DISABLED_EFFORT_CEILING: Mapping[str, frozenset[str]] = {
    # Claude Opus 5 accepts disabled thinking only at effort high or below.
    "claude-opus-5": frozenset({"low", "medium", "high"}),
}
"""Models that accept disabled thinking only at some effort levels. The AI layer
sends no `output_config.effort`, which means the default (`high`)."""

SUPPORTED_MODELS: frozenset[str] = frozenset(
    {
        "claude-sonnet-5",
        "claude-opus-5",
        "claude-opus-4-8",
        "claude-opus-4-7",
        "claude-opus-4-6",
        "claude-sonnet-4-6",
    }
)
"""Models that accept every parameter the AI layer sends today."""


def request_incompatibilities(model: str, request: Mapping[str, Any]) -> list[str]:
    """Why `model` would reject this `messages.create` request ([] = it would not).

    `request` is the keyword arguments a call site passes to
    `client.messages.create`. Only the parameters this module knows a model can
    reject are checked; everything else is assumed accepted.
    """
    problems: list[str] = []
    tool_choice = request.get("tool_choice") or {}
    if tool_choice.get("type") in {"tool", "any"} and model in FORCED_TOOL_CHOICE_REJECTED:
        problems.append(
            f"{model} rejects forced tool use (tool_choice type "
            f"'{tool_choice.get('type')}') with a 400"
        )
    thinking = request.get("thinking") or {}
    if thinking.get("type") == "disabled":
        effort = (request.get("output_config") or {}).get("effort", "high")
        if model in THINKING_DISABLED_REJECTED:
            problems.append(f"{model} rejects thinking type 'disabled' with a 400")
        elif (
            model in THINKING_DISABLED_EFFORT_CEILING
            and effort not in THINKING_DISABLED_EFFORT_CEILING[model]
        ):
            problems.append(
                f"{model} rejects thinking type 'disabled' at effort '{effort}' with a 400"
            )
    return problems


def unsupported_model_reason(model: str) -> str | None:
    """None if `model` is safe to configure, else an operator-facing reason."""
    if model in SUPPORTED_MODELS:
        return None
    known: list[str] = []
    if model in FORCED_TOOL_CHOICE_REJECTED:
        known.append("forced tool use (tool_choice), which /explain sends")
    if model in THINKING_DISABLED_REJECTED:
        known.append(
            "thinking={'type': 'disabled'}, which /explain, /chat and /analyze send"
        )
    why = (
        "it rejects " + " and ".join(known) + " with a 400"
        if known
        else "it has not been checked against the parameters the AI layer sends"
    )
    return (
        f"ANTHROPIC_MODEL={model!r} is not supported: {why}. "
        f"Supported: {', '.join(sorted(SUPPORTED_MODELS))}. "
        "See backend/app/ai/model_support.py before adding one."
    )
