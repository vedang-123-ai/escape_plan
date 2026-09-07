"""Grounded explanation service (S3.1).

Iron rule: the model explains and recommends ONLY from the corpus and the
computed RoutePlan. It never invents safety guidance and never computes routes
— the deterministic engine (app.routing) already did that. Every safety claim
must cite a corpus source id; citations are validated server-side and uncited
output is rejected and retried.

Prompt caching: the (large, static) corpus block carries cache_control so
repeated calls hit the Anthropic prompt cache; hits are logged.
"""

from __future__ import annotations

import json
import logging
from functools import lru_cache
from typing import Any, Optional

import anthropic
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.config import CORPUS_DIR, get_settings
from app.models import HomeModel, Profile
from app.routing.plan import RoutePlan

logger = logging.getLogger("app.ai.grounded")

# No sampling params: claude-sonnet-5 rejects non-default temperature/top_p/top_k
# with a 400 ("`temperature` is deprecated for this model"). Output stability comes
# from schema-enforced tool use + citation validation, not sampling.
# Thinking explicitly disabled: claude-sonnet-5 defaults to adaptive thinking when
# the param is omitted, which pushed /explain latency past the p95 < 6s budget.
THINKING = {"type": "disabled"}
MAX_TOKENS = 4096
MAX_CITATION_RETRIES = 2

def _corpus_files_from_sources() -> list[str]:
    """The corpus documents the model is shown, derived from sources.json.

    This used to be a hardcoded fire-only list, and S6.2 added two documents
    (earthquake, severe weather) plus six source ids without updating it. The
    result was a hole in the grounding guarantee rather than a cosmetic drift:
    `valid_source_ids()` reads all ids from sources.json, so citation validation
    accepted `noaa-tornado` on a claim the model invented from pretraining,
    because it had never been shown the document. Deriving both from one place
    makes that desync impossible; `test_corpus_block_matches_sources_json` pins it.
    """
    data = json.loads((CORPUS_DIR / "sources.json").read_text())
    return [cf["file"] for cf in data["corpus_files"]]


CORPUS_FILE_ORDER = _corpus_files_from_sources()


# ---------------------------------------------------------------------------
# Structured output contract (/explain response)


class RoomExplanation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    room_id: str
    room_name: str
    primary_explanation: str = Field(
        description="Plain, family-friendly walkthrough of the primary route."
    )
    secondary_explanation: Optional[str] = Field(
        default=None,
        description=(
            "Walkthrough of the secondary route, or null if the room has none "
            "(then mention the engine's finding in primary_explanation)."
        ),
    )


class Recommendation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    claim: str = Field(description="The safety claim, paraphrased from the corpus.")
    action: str = Field(description="Concrete action for this specific home.")
    source_citation: str = Field(
        description="A corpus source id from the provided source list."
    )


class ExplainResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    summary: str = Field(
        description="2-3 sentence family-friendly overview of the whole plan."
    )
    room_explanations: list[RoomExplanation]
    recommendations: list[Recommendation] = Field(
        description="Top recommendations, most important first."
    )


EXPLAIN_TOOL: dict[str, Any] = {
    "name": "submit_explanation",
    "description": "Submit the structured route explanation and recommendations.",
    # strict guarantees tool input validates against the schema server-side —
    # added 2026-07-23 after a live run produced a stray "action_2" field that
    # crashed model_validate (the schema already carries additionalProperties:
    # false via extra="forbid", which strict mode requires).
    "strict": True,
    "input_schema": ExplainResponse.model_json_schema(),
}


# ---------------------------------------------------------------------------
# Corpus loading + system prompt (cached corpus block)


@lru_cache(maxsize=1)
def valid_source_ids() -> frozenset[str]:
    """Ids the model may cite: exactly the `sources` array of sources.json."""
    data = json.loads((CORPUS_DIR / "sources.json").read_text())
    return frozenset(s["id"] for s in data["sources"])


@lru_cache(maxsize=1)
def corpus_text() -> str:
    parts: list[str] = []
    for name in CORPUS_FILE_ORDER:
        parts.append(f"<corpus_doc file=\"{name}\">\n"
                     f"{(CORPUS_DIR / name).read_text().strip()}\n</corpus_doc>")
    thresholds = (CORPUS_DIR / "egress_thresholds.json").read_text().strip()
    parts.append(f"<corpus_doc file=\"egress_thresholds.json\">\n{thresholds}\n</corpus_doc>")
    return "\n\n".join(parts)


RULES = """\
You are the explanation layer of Escape Plan, a home fire escape planning app.

You are given a home's floor plan (HomeModel) and escape routes ALREADY COMPUTED
by a deterministic routing engine (RoutePlan). Hard rules:

1. NEVER invent, alter, or recompute routes. Describe only the routes and
   findings in the provided RoutePlan, using the room and opening names/ids in
   the HomeModel.
2. NEVER give safety guidance that is not in the corpus documents below. If the
   corpus does not cover a topic, say so honestly and defer — recommend
   consulting the local fire department. Do not improvise advice.
3. Every safety claim you make must carry a citation: a source id from this
   exact list (anything else is invalid): {source_ids}
4. If the user may be in an actual emergency, the first advice is always:
   get out if safe and call 911.
5. Write for a family: plain language, short sentences, no jargon. Refer to
   rooms by their names.
6. Take the routing engine's findings seriously: no_secondary_egress and
   bottleneck findings are safety-relevant facts to explain, not to soften.
"""


def build_system_blocks() -> list[dict[str, Any]]:
    """System prompt: rules block + corpus block, cache_control on the corpus."""
    rules = RULES.format(source_ids=", ".join(sorted(valid_source_ids())))
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
    ]


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


# ---------------------------------------------------------------------------
# Citation validation (server-side, pure)


def find_invalid_citations(response: ExplainResponse) -> list[str]:
    """Every recommendation must cite a real corpus source id. Returns problems."""
    valid = valid_source_ids()
    problems: list[str] = []
    for i, rec in enumerate(response.recommendations):
        cite = rec.source_citation.strip()
        if cite not in valid:
            problems.append(
                f"recommendations[{i}].source_citation '{cite}' is not a known "
                f"corpus source id"
            )
    if not response.recommendations:
        problems.append("no recommendations were produced; produce at least one")
    return problems


class GroundingError(Exception):
    """Model output failed citation validation after all retries."""


# ---------------------------------------------------------------------------
# Calls


def _client() -> anthropic.Anthropic:
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise GroundingError("ANTHROPIC_API_KEY is not configured on the server")
    return anthropic.Anthropic(api_key=settings.anthropic_api_key)


def explain_routes(
    home: HomeModel,
    plan: RoutePlan,
    profile: Optional[Profile] = None,
    *,
    client: Optional[anthropic.Anthropic] = None,
) -> ExplainResponse:
    """Explain a computed RoutePlan with cited recommendations.

    Retries (up to MAX_CITATION_RETRIES) when the model cites a source id that
    does not resolve against sources.json; raises GroundingError if it never
    produces fully cited output.
    """
    client = client or _client()
    settings = get_settings()

    user_payload = {
        "home_model": home.model_dump(mode="json"),
        "route_plan": plan.model_dump(mode="json"),
    }
    if profile is not None:
        user_payload["profile"] = profile.model_dump(mode="json")

    messages: list[dict[str, Any]] = [
        {
            "role": "user",
            "content": (
                "Explain this escape plan and recommend improvements. Use the "
                "submit_explanation tool.\n\n" + json.dumps(user_payload)
            ),
        }
    ]

    last_problems: list[str] = []
    for attempt in range(1 + MAX_CITATION_RETRIES):
        response = client.messages.create(
            model=settings.anthropic_model,
            max_tokens=MAX_TOKENS,
            thinking=THINKING,
            system=build_system_blocks(),
            tools=[EXPLAIN_TOOL],
            tool_choice={"type": "tool", "name": "submit_explanation"},
            messages=messages,
        )
        _log_cache_usage(response.usage, f"explain_routes attempt={attempt}")

        tool_use = next(b for b in response.content if b.type == "tool_use")
        try:
            parsed = ExplainResponse.model_validate(tool_use.input)
        except ValidationError as exc:
            # strict=True on the tool should prevent this; belt-and-suspenders
            # retry instead of a 500 if the schema guarantee ever slips.
            last_problems = [
                f"schema violation at {'.'.join(str(p) for p in e['loc'])}: {e['msg']}"
                for e in exc.errors()
            ]
        else:
            last_problems = find_invalid_citations(parsed)
            if not last_problems:
                return parsed

        logger.warning(
            "explain_routes attempt=%d rejected: %s", attempt, "; ".join(last_problems)
        )
        messages.append({"role": "assistant", "content": response.content})
        messages.append(
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": tool_use.id,
                        "is_error": True,
                        "content": (
                            "Rejected — validation failed:\n- "
                            + "\n- ".join(last_problems)
                            + "\nFollow the tool schema exactly (no extra fields) and "
                            "every source_citation must be one of the source ids "
                            "listed in your instructions. Resubmit."
                        ),
                    }
                ],
            }
        )

    raise GroundingError(
        "validation failed after retries: " + "; ".join(last_problems)
    )


def answer_grounded_question(
    question: str, *, client: Optional[anthropic.Anthropic] = None
) -> str:
    """Answer a free-form safety question under the same grounding rules.

    Used by the S3.1 red-team test today and the S3.3 chat assistant later.
    Plain-text response; topics outside the corpus must get an honest deferral.
    """
    client = client or _client()
    settings = get_settings()
    response = client.messages.create(
        model=settings.anthropic_model,
        max_tokens=1024,
        thinking=THINKING,
        system=build_system_blocks(),
        messages=[{"role": "user", "content": question}],
    )
    _log_cache_usage(response.usage, "answer_grounded_question")
    return "".join(b.text for b in response.content if b.type == "text")
