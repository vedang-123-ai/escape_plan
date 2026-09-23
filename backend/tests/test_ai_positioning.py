"""S11.4: the positioning the whole project is defended on, pinned as a test.

`CLAUDE.md`: "It is not a tool for firefighters to use mid-fire (a working
firefighter told us so). It is a prevention and readiness app." Before S11.4 all
four system prompts opened with "a home fire escape planning app" — fire-only,
written when fire was the only peril, and silent on the prevention framing.

Prose in a prompt file is the easiest thing in this repo to regress, because
nothing compiles it and no live test can run without credits. These tests are
what make the framing checkable with no key.
"""

from __future__ import annotations

import re

import pytest

from app.ai import agent, builder, grounded
from app.ai.chat import service as chat_service

# Every system prompt shipped to the model, by the name a reader would use.
PROMPTS: dict[str, str] = {
    "grounded.RULES": grounded.RULES,
    "agent.AGENT_SYSTEM_PROMPT": agent.AGENT_SYSTEM_PROMPT,
    "chat.CHAT_RULES": chat_service.CHAT_RULES,
    "builder.BUILDER_SYSTEM_PROMPT": builder.BUILDER_SYSTEM_PROMPT,
}

# Prompts that give the user safety guidance. The builder is excluded on purpose:
# it builds geometry and is explicitly forbidden from giving safety advice at all,
# so the 911 rule and the citation rule do not belong in it.
GUIDANCE_PROMPTS = {
    k: v for k, v in PROMPTS.items() if k != "builder.BUILDER_SYSTEM_PROMPT"
}


@pytest.mark.parametrize("name", sorted(PROMPTS))
def test_no_prompt_calls_this_a_fire_only_app(name: str) -> None:
    text = PROMPTS[name].lower()
    assert "fire escape planning app" not in text, (
        f"{name} still describes a fire-only app; the scope is fire, earthquake "
        f"and severe weather"
    )


# Claims the app must never make. Written as patterns because the prompts are
# *required* to mention firefighters — they tell the model to defer to the local
# fire department — so a bare substring check would be both unmaintainable and
# wrong. The first draft of this test was exactly that, and it failed on the
# sentence "never describe it as helping firefighters navigate a burning house":
# it could not tell a prohibition from a claim. Hence the per-sentence negation
# check below rather than a whole-text search.
RESPONDER_CLAIMS = [
    r"help\w* firefighters navigate",
    r"for firefighters to use",
    r"first responders? (?:can|will|should) use",
    r"use (?:it|this app) during (?:a|the|an) (?:fire|emergency)",
]

NEGATORS = re.compile(r"\b(?:never|not|don't|do not|no)\b")


def _sentences(prompt: str) -> list[str]:
    return [" ".join(s.lower().split()) for s in re.split(r"(?<=[.:])\s+", prompt) if s.strip()]


@pytest.mark.parametrize("name", sorted(PROMPTS))
def test_no_prompt_positions_this_as_a_responder_tool(name: str) -> None:
    """The claim a working firefighter told us not to make (CLAUDE.md).

    A sentence may contain the claim only while forbidding it.
    """
    for sentence in _sentences(PROMPTS[name]):
        for pattern in RESPONDER_CLAIMS:
            if re.search(pattern, sentence):
                assert NEGATORS.search(sentence), (
                    f"{name} asserts the responder claim /{pattern}/ without negating "
                    f"it, in: {sentence!r}"
                )


@pytest.mark.parametrize("name", sorted(GUIDANCE_PROMPTS))
def test_every_guidance_prompt_explicitly_disowns_the_responder_claim(name: str) -> None:
    """Not making the claim is not the same as refusing it.

    A model that has never been told will happily say "so firefighters can find
    you" when a user asks what the app is for. The prompts say not to.
    """
    text = " ".join(GUIDANCE_PROMPTS[name].lower().split())
    assert re.search(r"(?:never|not a tool)[^.]*(?:firefighter|responder|during)", text), (
        f"{name} never tells the model this is not a mid-emergency or responder tool"
    )


@pytest.mark.parametrize("name", sorted(PROMPTS))
def test_every_prompt_names_the_three_perils_or_says_it_builds_geometry(name: str) -> None:
    text = PROMPTS[name].lower()
    assert "earthquake" in text and (
        "severe weather" in text or "tornado" in text
    ), f"{name} does not mention the non-fire perils at all"


# Surfaces where a user can tell the app they are in danger right now. The agent
# is deliberately absent: /analyze takes a HomeModel and returns a findings list,
# with no user message in it at all, so there is no emergency for it to detect and
# a call-911 rule there would be instruction noise on a prompt already carrying
# seven. This scope is stated rather than assumed — the first version of this test
# asserted 911 across every guidance prompt and failed on the agent, which is how
# the distinction got noticed.
CONVERSATIONAL_PROMPTS = {
    "grounded.RULES": grounded.RULES,
    "chat.CHAT_RULES": chat_service.CHAT_RULES,
}


@pytest.mark.parametrize("name", sorted(CONVERSATIONAL_PROMPTS))
def test_every_conversational_prompt_still_says_call_911_first(name: str) -> None:
    """S11.4 rewrote positioning; it must not have cost a safety behaviour.

    `.claude/rules/vendors/anthropic.md`: "emergencies -> call 911 first".
    """
    text = CONVERSATIONAL_PROMPTS[name].lower()
    assert "911" in text, f"{name} lost the call-911-first rule"


@pytest.mark.parametrize("name", sorted(CONVERSATIONAL_PROMPTS))
def test_every_conversational_prompt_still_demands_an_honest_deferral(name: str) -> None:
    """`anthropic.md`: "uncorpused topics -> honest deferral, never invented advice"."""
    text = CONVERSATIONAL_PROMPTS[name].lower()
    assert "defer" in text, f"{name} lost the honest-deferral rule"
    assert "improvise" in text, f"{name} lost the do-not-improvise rule"


def test_the_agent_refuses_uncorpused_topics_even_without_the_word_defer() -> None:
    """The agent's version of the deferral rule, pinned in its own terms.

    It has no user message to defer *to*, so it carries the same guarantee as a
    scope restriction instead: every recommendation must come from search_corpus,
    and anything the app does not model is off-limits.
    """
    text = " ".join(agent.AGENT_SYSTEM_PROMPT.lower().split())
    assert "grounded by search_corpus" in text
    assert re.search(r"do not guess about", text)
    assert re.search(r"not modeled in the app", text)


@pytest.mark.parametrize("name", sorted(GUIDANCE_PROMPTS))
def test_every_guidance_prompt_still_forbids_recomputing_routes(name: str) -> None:
    """The separation the whole "isn't this an AI wrapper?" answer rests on."""
    text = " ".join(GUIDANCE_PROMPTS[name].lower().split())
    assert re.search(r"never (?:invent|compute)", text), (
        f"{name} lost the never-invent-a-route rule"
    )


@pytest.mark.parametrize("name", sorted(GUIDANCE_PROMPTS))
def test_every_guidance_prompt_is_honest_about_what_is_quantified(name: str) -> None:
    """Scope lock: "Fire is fully code-quantified; earthquake and tornado are
    FEMA/NOAA-grounded readiness modules and must be labeled honestly."

    S11.2 made the same distinction load-bearing in the score (`sub_scores` and
    the `basis` map). The prompts were the half that still said nothing.
    """
    text = " ".join(GUIDANCE_PROMPTS[name].lower().split())
    assert "guidance" in text, f"{name} never says the non-fire perils are guidance"
    assert re.search(r"code[- ]?(?:quantified|checked)|codified", text), (
        f"{name} never says fire is the code-quantified one"
    )


def test_the_builder_still_refuses_to_give_safety_advice() -> None:
    """Re-positioning the builder must not have turned it into an advisor."""
    text = builder.BUILDER_SYSTEM_PROMPT.lower()
    assert "never give safety advice" in text
    assert "never invent routes" in text
    assert "draft" in text


def test_the_search_corpus_tool_does_not_advertise_a_fire_only_corpus() -> None:
    """The agent picks tools off these descriptions.

    It read "Search the fire-safety grounding corpus", which is a reason not to
    call it for an earthquake question — on a corpus that has covered earthquake
    and severe weather since S6.2.
    """
    tool = next(t for t in agent.TOOLS if t["name"] == "search_corpus")
    desc = tool["description"].lower()
    assert "fire-safety grounding corpus" not in desc
    assert "earthquake" in desc and ("severe weather" in desc or "tornado" in desc)
