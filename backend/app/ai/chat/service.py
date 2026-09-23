"""Stateless multi-turn chat service (S3.3 prep).

Reuses the S3.1 grounding layer (`app.ai.grounded`): same cached corpus block,
same citable source-id set, same "explain/audit, never route, never invent"
iron rule. The server holds no conversation state — the client resends the
full turn history every call, and the system prompt (rules + corpus + a fresh
house/plan/profile summary) is rebuilt from scratch each time.

Citation contract for chat: any inline `[cite: source-id]` tag in the
assistant's reply must resolve against `sources.json` (same convention as the
corpus markdown and S3.1's structured citations, see `backend/corpus/`). A
reply is free to contain zero citations (small talk, clarifying questions,
911 deferrals need none) — the check only rejects *fabricated* ids, mirroring
`grounded.find_invalid_citations`. Fabricated citations trigger the same
reject-and-retry loop as S3.1's /explain.
"""

from __future__ import annotations

import logging
import re
from typing import Any, Literal, Optional

import anthropic
from pydantic import BaseModel, ConfigDict, Field

from app.ai.grounded import GroundingError, corpus_text, valid_source_ids
from app.ai.chat.summary import summarize_home, summarize_profiles, summarize_route_plan
from app.config import get_settings
from app.models import HomeModel, Profile
from app.routing.plan import RoutePlan

logger = logging.getLogger("app.ai.chat")

# No sampling params: claude-sonnet-5 rejects non-default temperature (400).
# Thinking explicitly disabled for chat responsiveness (adaptive is the Sonnet 5
# default when omitted; see grounded.py / agent.py for the latency evidence).
THINKING = {"type": "disabled"}
MAX_TOKENS = 1024
MAX_CITATION_RETRIES = 2

CITE_RE = re.compile(r"\[cite:\s*([a-z0-9-]+)\]")

CHAT_RULES = """\
You are the chat assistant for Escape Plan, a home safety readiness and
prevention app. It helps a family prepare BEFORE an emergency — for fire,
earthquake and severe weather (tornado). It is not a tool to use during one and
it is not a tool for responders: never describe it as helping firefighters
navigate a burning house. If someone is in danger right now, rule 4 applies and
nothing else matters.

Be honest about how well each peril is quantified. Fire is measured against
codified requirements — the routing engine computes real escape routes and the
egress checker tests real openings against IRC thresholds. Earthquake and severe
weather are readiness guidance drawn from the corpus, not code-checked
measurements; never imply the app measured something it did not.

You are talking directly with a family member. You are given this specific
home's floor plan, its ALREADY-COMPUTED escape routes, and any family
profiles — use them to give house-specific, personalized answers (e.g. "your
kids' bedroom is upstairs — practice the window route with an adult").

Hard rules:

1. NEVER invent, alter, or recompute escape routes. The routes and findings
   below were produced by a deterministic routing engine; describe them, do
   not second-guess the geometry or timing.
2. NEVER give safety guidance that is not in the corpus documents provided in
   this system prompt. If the corpus does not cover what's asked, say so
   honestly and defer — recommend consulting the local fire department or
   emergency management office. Do not improvise advice.
3. Every safety claim you make must carry a citation tag `[cite: source-id]`
   immediately after it, using only ids from this exact list (anything else
   is invalid and will be rejected): {source_ids}
4. If the user's message suggests an actual, present emergency (smoke, fire,
   trapped, injury), your FIRST line is always: get out if safe, then call
   911. Give that before anything else, even before corpus citations.
5. Write for a family: plain language, short sentences, no jargon. Refer to
   rooms by their names, not their ids.
6. Take the routing engine's findings seriously (no_secondary_egress,
   bottlenecks) — explain them plainly, don't soften or hide them.
"""


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    role: Literal["user", "assistant"]
    content: str = Field(min_length=1)


class ChatResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reply: str
    citations: list[str] = Field(default_factory=list)


def _house_context_block(
    home: HomeModel, route_plan: Optional[RoutePlan], profiles: list[Profile]
) -> str:
    parts = [summarize_home(home)]
    if route_plan is not None:
        parts.append(summarize_route_plan(route_plan))
    parts.append(summarize_profiles(profiles, home))
    return "\n\n".join(parts)


def build_chat_system_blocks(
    home: HomeModel, route_plan: Optional[RoutePlan], profiles: list[Profile]
) -> list[dict[str, Any]]:
    """Rules block + cached corpus block (reused from S3.1) + house context.

    The house context block also carries cache_control: a chat session reuses
    the same home/plan/profiles across every turn, so it's a legitimate cache
    breakpoint too, not just the corpus (see decisions.md).
    """
    rules = CHAT_RULES.format(source_ids=", ".join(sorted(valid_source_ids())))
    return [
        {"type": "text", "text": rules},
        {
            "type": "text",
            "text": (
                "The complete grounding corpus follows. It is your ONLY source "
                "of safety guidance.\n\n" + corpus_text()
            ),
            "cache_control": {"type": "ephemeral"},
        },
        {
            "type": "text",
            "text": (
                "This family's home, computed escape plan, and profiles "
                "follow. Ground every house-specific answer in this data, "
                "never in assumptions.\n\n"
                + _house_context_block(home, route_plan, profiles)
            ),
            "cache_control": {"type": "ephemeral"},
        },
    ]


def find_invalid_chat_citations(reply: str) -> list[str]:
    """Fabricated citation ids in `reply` (present but not in sources.json)."""
    valid = valid_source_ids()
    cited = set(CITE_RE.findall(reply))
    return sorted(cited - valid)


class ChatGroundingError(Exception):
    """Model output failed citation validation after all retries."""


def _client() -> anthropic.Anthropic:
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise GroundingError("ANTHROPIC_API_KEY is not configured on the server")
    return anthropic.Anthropic(api_key=settings.anthropic_api_key)


def _log_cache_usage(usage: Any, context: str) -> None:
    created = getattr(usage, "cache_creation_input_tokens", None) or 0
    read = getattr(usage, "cache_read_input_tokens", None) or 0
    logger.info(
        "%s: prompt cache %s (created=%d read=%d input=%d output=%d)",
        context,
        "HIT" if read else "MISS",
        created,
        read,
        usage.input_tokens,
        usage.output_tokens,
    )


def chat(
    history: list[ChatMessage],
    home: HomeModel,
    route_plan: Optional[RoutePlan] = None,
    profiles: Optional[list[Profile]] = None,
    *,
    client: Optional[anthropic.Anthropic] = None,
) -> ChatResponse:
    """Answer the latest turn in `history`, grounded in this home + corpus.

    Stateless: `history` is the full client-held conversation (last message
    must be from the user); nothing is persisted server-side between calls.
    Retries (up to MAX_CITATION_RETRIES) when the reply cites a fabricated
    source id; raises ChatGroundingError if it never produces valid output.
    """
    if not history or history[-1].role != "user":
        raise ValueError("history must be non-empty and end with a user message")

    client = client or _client()
    settings = get_settings()
    system = build_chat_system_blocks(home, route_plan, profiles or [])
    messages: list[dict[str, Any]] = [
        {"role": m.role, "content": m.content} for m in history
    ]

    last_problems: list[str] = []
    for attempt in range(1 + MAX_CITATION_RETRIES):
        response = client.messages.create(
            model=settings.anthropic_model,
            max_tokens=MAX_TOKENS,
            thinking=THINKING,
            system=system,
            messages=messages,
        )
        _log_cache_usage(response.usage, f"chat attempt={attempt}")
        reply = "".join(b.text for b in response.content if b.type == "text")

        last_problems = find_invalid_chat_citations(reply)
        if not last_problems:
            return ChatResponse(reply=reply, citations=sorted(CITE_RE.findall(reply)))

        logger.warning("chat attempt=%d rejected: fabricated citations %s", attempt, last_problems)
        messages.append({"role": "assistant", "content": reply})
        messages.append(
            {
                "role": "user",
                "content": (
                    "That reply cited source id(s) that don't exist: "
                    + ", ".join(last_problems)
                    + ". Every [cite: ...] tag must use one of the source ids "
                    "listed in your instructions. Resubmit your answer to my "
                    "previous question with corrected or removed citations."
                ),
            }
        )

    raise ChatGroundingError(
        "chat citation validation failed after retries: fabricated ids "
        + ", ".join(last_problems)
    )
