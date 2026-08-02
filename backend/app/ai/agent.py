"""Agentic home analysis (S3.2): the "AI safety inspector."

Iron rule (same as S3.1's grounded.py): the agent NEVER computes or invents
routes or egress verdicts — it calls the S1.2 routing engine and S1.1 egress
checker as tools and reports what they say. Its job is to walk the home
systematically and surface findings, each backed by a real tool call recorded
in the trace. Findings whose evidence doesn't resolve to an actual trace entry,
or whose citation isn't a real corpus source id, are dropped server-side before
the response goes out — "zero findings without evidence" is enforced here, not
just requested of the model.
"""

from __future__ import annotations

import json
import logging
import re
from functools import lru_cache
from typing import Any, Literal, Optional

import anthropic
from pydantic import BaseModel, ConfigDict, Field

from app.ai.grounded import valid_source_ids
from app.config import CORPUS_DIR, get_settings
from app.models import HomeModel
from app.routing.egress import EgressThresholds, check_egress
from app.routing.engine import compute_route_plan
from app.routing.obstructions import analyze_obstructions
from app.routing.plan import RoutePlan, RoutingConstraints
from app.scoring.findings import finding_id

logger = logging.getLogger("app.ai.agent")

# No sampling params: claude-sonnet-5 rejects non-default temperature (400).
# Thinking is explicitly disabled: claude-sonnet-5 runs adaptive thinking when the
# param is omitted, which blew the S3.2 <60s latency budget (71s measured) across
# the 15-iteration loop. The prescriptive system prompt keeps tool use reliable.
THINKING = {"type": "disabled"}
MAX_TOKENS = 4096
MAX_ITERATIONS = 15
"""Cap per playbook S3.2: bounds both latency (<60s acceptance) and API cost."""

MAX_SUBMIT_RETRIES = 2
"""How many times a submit_findings call that fails evidence/citation validation
is bounced back for correction before we return the gutted result as-is. Added
2026-07-23: with thinking disabled, claude-sonnet-5 sometimes writes descriptive
evidence refs ('check_egress:w_kids') instead of literal toolu_ ids; one
corrective round-trip reliably fixes it."""

CORPUS_DOC_FILES = [
    "escape-planning-nfpa.md",
    "egress-windows-irc.md",
    "smoke-alarms-usfa.md",
    "home-fire-escape-redcross.md",
    "fire-facts-stats.md",
    "special-considerations.md",
]


# ---------------------------------------------------------------------------
# Structured output contract (/analyze response)


class Finding(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(
        default="",
        description="Leave empty — assigned server-side (content hash; see app.scoring.findings.finding_id).",
    )
    severity: Literal["high", "med", "low"]
    room_ids: list[str] = Field(default_factory=list)
    finding: str = Field(description="What's wrong, in plain language.")
    evidence: list[str] = Field(
        description=(
            "The literal id(s) of tool_use blocks from this conversation that "
            "support this finding, copied verbatim (they start with 'toolu_'). "
            "Never invent descriptive names like 'check_egress:w_kids'."
        )
    )
    recommendation: str
    citation: str = Field(description="A corpus source id from the provided source list.")


class AnalysisSubmission(BaseModel):
    model_config = ConfigDict(extra="forbid")

    findings: list[Finding]


class ToolCallRecord(BaseModel):
    """One tool invocation, for the returned trace (also demo material)."""

    model_config = ConfigDict(extra="forbid")

    id: str
    tool_name: str
    input: dict[str, Any]
    output: Any


class AnalysisResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    findings: list[Finding]
    trace: list[ToolCallRecord]
    truncated: bool = Field(
        description="True if the iteration cap was hit before the agent submitted findings."
    )
    dropped: list[str] = Field(
        default_factory=list,
        description="Findings the model submitted that failed evidence/citation validation and were removed.",
    )


class AgentError(Exception):
    """The agent loop could not produce a validated result."""


# ---------------------------------------------------------------------------
# Tools exposed to the model — each is a thin, read-only wrapper over
# HomeModel/RoutePlan data or the deterministic engines. No tool ever lets the
# model write to the home or invent a route/egress verdict.


TOOLS: list[dict[str, Any]] = [
    {
        "name": "get_home_summary",
        "description": (
            "Get a high-level summary of the home: floors, rooms per floor "
            "(id/name/type), opening counts, and stairs. Start here."
        ),
        "input_schema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "get_room",
        "description": "Get full detail for one room: polygon, type, and every opening attached to it.",
        "input_schema": {
            "type": "object",
            "properties": {"room_id": {"type": "string"}},
            "required": ["room_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "list_openings",
        "description": "List every opening (door/window) on a floor, with dimensions and which rooms it connects.",
        "input_schema": {
            "type": "object",
            "properties": {"floor_id": {"type": "string"}},
            "required": ["floor_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "compute_routes",
        "description": (
            "Run the deterministic routing engine: primary/secondary escape routes for "
            "every room, plus bottleneck (single-point-of-failure) findings. Optionally "
            "constrain the search (e.g. avoid_stairs for a mobility-limited profile)."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "avoid_stairs": {"type": "boolean"},
                "avoid_windows": {"type": "boolean"},
                "max_sill_height_m": {"type": "number"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "check_egress",
        "description": (
            "Run the deterministic egress checker on one opening against the codified "
            "IRC thresholds (door/window minimum size, max window sill height). Returns "
            "viable: bool and the specific reasons if not."
        ),
        "input_schema": {
            "type": "object",
            "properties": {"opening_id": {"type": "string"}},
            "required": ["opening_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "check_obstructions",
        "description": (
            "Run the deterministic obstruction analysis: which piece of furniture is "
            "in the way of which doorway, and how far it has to move. Returns, per "
            "finding, kind ('blocks_opening' = no path to that doorway at all; "
            "'narrows_route' = passable but a squeeze), the culprit object id(s) and "
            "categories, the measured passable width, the required door width, and the "
            "measured distance to move. Optionally scope to one room. Use this whenever "
            "a room has furniture — the routing engine reports that a doorway is "
            "unreachable, but only this tool names the object responsible."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "room_id": {
                    "type": "string",
                    "description": "Optional — restrict to one room. Omit to check the whole home.",
                }
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "search_corpus",
        "description": (
            "Search the fire-safety grounding corpus for guidance on a topic (e.g. "
            "'window egress', 'smoke alarms', 'mobility'). Returns matching passages "
            "with their citable source ids. Use this before writing any recommendation "
            "or citation."
        ),
        "input_schema": {
            "type": "object",
            "properties": {"topic": {"type": "string"}},
            "required": ["topic"],
            "additionalProperties": False,
        },
    },
    {
        "name": "submit_findings",
        "description": (
            "Submit your final findings list and end the inspection. Call this once you "
            "have systematically checked every room. Every finding's evidence must list "
            "the tool_use_id(s) of the tool calls that actually support it."
        ),
        "input_schema": AnalysisSubmission.model_json_schema(),
    },
]


AGENT_SYSTEM_PROMPT = """\
You are the agentic home safety inspector for Escape Plan, a home fire escape \
planning app. You are given tools to walk a specific home room by room. \
Hard rules:

1. NEVER invent a route, an egress verdict, a blocked doorway, or a safety \
   fact. Every factual claim about routes or egress must come from \
   compute_routes or check_egress; every claim that furniture is in the way, \
   and every distance you tell someone to move it, must come from \
   check_obstructions. Never estimate a clearance or a move distance yourself. \
   Every safety recommendation must be grounded by search_corpus and cite a \
   real source id it returned.
2. Inspect systematically: get_home_summary first, then examine every room \
   (get_room / list_openings), run compute_routes to see the engine's own \
   bottleneck and no_secondary_egress findings, check_egress on any \
   opening that looks marginal (small windows, high sills), and \
   check_obstructions to find furniture standing in the way of a doorway.
3. A finding without a real tool call behind it is worthless and will be \
   discarded — always call the tool, look at its actual output, THEN write \
   the finding, and reference the exact tool_use_id(s) you used as evidence. \
   Evidence entries are the literal ids of your own tool_use blocks, copied \
   verbatim — they start with 'toolu_'. Never write descriptive labels like \
   'check_egress:w_kids' or 'compute_routes:avoid_stairs=true'.
4. Report findings at the severity the evidence supports: high = no viable \
   route or no secondary egress from an occupied room, or a 'blocks_opening' \
   obstruction on a sleeping room's only way out; med = marginal egress \
   (fails a threshold), a bottleneck opening, or any other 'blocks_opening'; \
   low = best-practice gaps with no acute failure, including 'narrows_route' \
   squeezes. An obstruction finding is worth writing even when it is easy to \
   fix — moving a wardrobe is the cheapest safety improvement in the house — \
   so name the object, say which doorway, and quote the measured distance \
   check_obstructions returned.
5. When you have checked every room, call submit_findings exactly once with \
   your complete findings list. If you have nothing to report, submit an \
   empty findings list — do not pad it.
"""


# ---------------------------------------------------------------------------
# Corpus search (paragraph-level; grounded.py's corpus_text() is doc-level and
# used for the /explain system prompt instead)


@lru_cache(maxsize=1)
def _corpus_paragraphs() -> list[tuple[str, str]]:
    """(source_id, paragraph_text) pairs across every corpus doc's body."""
    pairs: list[tuple[str, str]] = []
    for name in CORPUS_DOC_FILES:
        text = (CORPUS_DIR / name).read_text()
        match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
        if not match:
            continue
        front_matter, body = match.group(1), match.group(2)
        id_match = re.search(r"^id:\s*(\S+)", front_matter, re.MULTILINE)
        doc_id = id_match.group(1) if id_match else name
        for para in body.split("\n\n"):
            para = para.strip()
            if para and not para.startswith("#"):
                pairs.append((doc_id, para))
    return pairs


def search_corpus(topic: str, *, max_results: int = 5) -> list[dict[str, str]]:
    """Keyword search over corpus paragraphs; returns [{source_id, excerpt}, ...]."""
    words = [w for w in re.findall(r"[a-z0-9]+", topic.lower()) if len(w) > 2]
    if not words:
        return []
    scored: list[tuple[int, str, str]] = []
    for doc_id, para in _corpus_paragraphs():
        low = para.lower()
        score = sum(low.count(w) for w in words)
        if score > 0:
            scored.append((score, doc_id, para))
    scored.sort(key=lambda t: t[0], reverse=True)
    return [{"source_id": doc_id, "excerpt": para} for _, doc_id, para in scored[:max_results]]


# ---------------------------------------------------------------------------
# Tool dispatch — reads HomeModel/RoutePlan, calls the deterministic engines.
# Never mutates the home; never fabricates a value the engines didn't produce.


def _room_and_floor(home: HomeModel, room_id: str):
    for floor in home.floors:
        for room in floor.rooms:
            if room.id == room_id:
                return floor, room
    return None, None


def _dispatch_tool(
    name: str, tool_input: dict[str, Any], home: HomeModel, thresholds: EgressThresholds
) -> Any:
    if name == "get_home_summary":
        return {
            "home_id": home.home_id,
            "name": home.name,
            "floors": [
                {
                    "id": f.id,
                    "name": f.name,
                    "level": f.level,
                    "rooms": [
                        {"id": r.id, "name": r.name, "type": r.type.value} for r in f.rooms
                    ],
                    "opening_count": len(f.openings),
                }
                for f in home.floors
            ],
            "stairs": [
                {"id": s.id, "from": s.from_.room_id, "to": s.to.room_id} for s in home.stairs
            ],
        }

    if name == "get_room":
        floor, room = _room_and_floor(home, tool_input["room_id"])
        if room is None:
            return {"error": f"no such room_id: {tool_input['room_id']}"}
        openings = [o for o in floor.openings if room.id in o.room_ids]
        return {
            "id": room.id,
            "name": room.name,
            "type": room.type.value,
            "floor_id": floor.id,
            "polygon": room.polygon,
            "openings": [
                {
                    "id": o.id,
                    "kind": o.kind.value,
                    "room_ids": o.room_ids,
                    "is_exit": o.is_exit,
                    "width_m": o.width_m,
                    "height_m": o.height_m,
                    "sill_height_m": o.sill_height_m,
                }
                for o in openings
            ],
        }

    if name == "list_openings":
        floor = next((f for f in home.floors if f.id == tool_input["floor_id"]), None)
        if floor is None:
            return {"error": f"no such floor_id: {tool_input['floor_id']}"}
        return {
            "floor_id": floor.id,
            "openings": [
                {
                    "id": o.id,
                    "kind": o.kind.value,
                    "room_ids": o.room_ids,
                    "is_exit": o.is_exit,
                    "width_m": o.width_m,
                    "height_m": o.height_m,
                    "sill_height_m": o.sill_height_m,
                }
                for o in floor.openings
            ],
        }

    if name == "compute_routes":
        constraints = RoutingConstraints(
            avoid_stairs=tool_input.get("avoid_stairs", False),
            avoid_windows=tool_input.get("avoid_windows", False),
            max_sill_height_m=tool_input.get("max_sill_height_m"),
        )
        plan: RoutePlan = compute_route_plan(home, thresholds, constraints=constraints)
        return plan.model_dump(mode="json")

    if name == "check_egress":
        opening_id = tool_input["opening_id"]
        for floor in home.floors:
            grade = floor.level <= 0
            for opening in floor.openings:
                if opening.id == opening_id:
                    assessment = check_egress(opening, thresholds, grade_floor=grade)
                    return {
                        "opening_id": opening_id,
                        "viable": assessment.viable,
                        "reasons": assessment.reasons,
                    }
        return {"error": f"no such opening_id: {opening_id}"}

    if name == "check_obstructions":
        room_id = tool_input.get("room_id")
        found = analyze_obstructions(home, thresholds)
        if room_id is not None:
            found = [o for o in found if o.room_id == room_id]
        return {
            "obstructions": [
                {
                    "kind": o.kind,
                    "room_id": o.room_id,
                    "room_name": o.room_name,
                    "floor_id": o.floor_id,
                    "opening_id": o.opening_id,
                    "object_ids": list(o.object_ids),
                    "object_categories": list(o.object_categories),
                    "passable_width_m": o.passable_width_m,
                    "required_width_m": o.required_width_m,
                    "suggested_move_m": o.suggested_move_m,
                    # The engine's own phrasing, carried so the model re-words a
                    # measured sentence instead of composing numbers of its own.
                    "detail": o.detail,
                }
                for o in found
            ]
        }

    if name == "search_corpus":
        return {"results": search_corpus(tool_input["topic"])}

    raise AgentError(f"unknown tool: {name}")


# ---------------------------------------------------------------------------
# Server-side evidence + citation validation — the enforcement behind
# "zero findings without evidence links" (S3.2 acceptance).


def _validate_findings(
    findings: list[Finding], trace: list[ToolCallRecord]
) -> tuple[list[Finding], list[str]]:
    trace_ids = {t.id for t in trace}
    valid_sources = valid_source_ids()
    kept: list[Finding] = []
    dropped: list[str] = []
    for f in findings:
        problems: list[str] = []
        if not f.evidence:
            problems.append("no evidence tool_use_ids")
        else:
            unknown = [e for e in f.evidence if e not in trace_ids]
            if unknown:
                problems.append(f"evidence references unknown tool call(s): {unknown}")
        if f.citation not in valid_sources:
            problems.append(f"citation '{f.citation}' is not a known corpus source id")
        if problems:
            dropped.append(f"[{f.finding[:60]!r}] " + "; ".join(problems))
        else:
            # Stamp the stable content-derived id here, overwriting anything the
            # model put in the field — ids are server-assigned, never model-chosen.
            f.id = finding_id(f.severity, f.room_ids, f.finding)
            kept.append(f)
    return kept, dropped


# ---------------------------------------------------------------------------
# The loop


def _client() -> anthropic.Anthropic:
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise AgentError("ANTHROPIC_API_KEY is not configured on the server")
    return anthropic.Anthropic(api_key=settings.anthropic_api_key)


def run_agent_analysis(
    home: HomeModel,
    thresholds: EgressThresholds,
    *,
    client: Optional[anthropic.Anthropic] = None,
    max_iterations: int = MAX_ITERATIONS,
) -> AnalysisResult:
    """Run the tool-use inspection loop and return validated findings + trace."""
    client = client or _client()
    settings = get_settings()

    messages: list[dict[str, Any]] = [
        {
            "role": "user",
            "content": (
                "Inspect this home for fire escape safety issues. Use the tools to "
                "gather real evidence about every room, then call submit_findings."
            ),
        }
    ]
    trace: list[ToolCallRecord] = []
    resubmits_left = MAX_SUBMIT_RETRIES

    for _ in range(max_iterations):
        response = client.messages.create(
            model=settings.anthropic_model,
            max_tokens=MAX_TOKENS,
            thinking=THINKING,
            system=AGENT_SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )
        messages.append({"role": "assistant", "content": response.content})

        tool_uses = [b for b in response.content if b.type == "tool_use"]
        if not tool_uses:
            break

        tool_results: list[dict[str, Any]] = []
        for tu in tool_uses:
            if tu.name == "submit_findings":
                submission = AnalysisSubmission.model_validate(tu.input)
                kept, dropped = _validate_findings(submission.findings, trace)
                if not dropped or resubmits_left == 0:
                    return AnalysisResult(
                        findings=kept, trace=trace, truncated=False, dropped=dropped
                    )
                # Some findings failed evidence/citation validation. Rather than
                # silently returning a gutted result, reject the submission and
                # let the model resubmit with corrected references — bounded so
                # a model that can't fix them still returns gracefully.
                resubmits_left -= 1
                logger.warning(
                    "submit_findings rejected (%d invalid), asking for resubmit: %s",
                    len(dropped), "; ".join(dropped),
                )
                valid_ids = ", ".join(t.id for t in trace) or "(none yet)"
                tool_results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": tu.id,
                        "is_error": True,
                        "content": (
                            "Submission rejected — these findings failed validation:\n- "
                            + "\n- ".join(dropped)
                            + "\nEach evidence entry must be the LITERAL id of a tool_use "
                            "block from this conversation, copied verbatim (they start "
                            "with 'toolu_'). Never invent names like 'check_egress:x'. "
                            f"Valid ids so far: {valid_ids}. Each citation must be a "
                            "source id returned by search_corpus. Resubmit your FULL "
                            "findings list with corrected evidence and citations."
                        ),
                    }
                )
                continue
            output = _dispatch_tool(tu.name, tu.input, home, thresholds)
            trace.append(ToolCallRecord(id=tu.id, tool_name=tu.name, input=tu.input, output=output))
            tool_results.append(
                {"type": "tool_result", "tool_use_id": tu.id, "content": json.dumps(output, default=str)}
            )
        messages.append({"role": "user", "content": tool_results})

    logger.warning("agent analysis hit the %d-iteration cap without submitting", max_iterations)
    return AnalysisResult(findings=[], trace=trace, truncated=True)
