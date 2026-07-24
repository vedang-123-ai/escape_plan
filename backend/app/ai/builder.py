"""LLM house builder (revamp C1): a hand-rolled tool-use loop that constructs a
HomeModel DRAFT from a text description and/or floor-plan image.

Iron rules, same family as agent.py:
- The builder gets NO routing or egress tools. It builds geometry; the
  deterministic engine routes it LATER, after a human reviews the draft.
- Everything it creates is stamped source="ai_plan" + confidence=0.5 by the
  action layer (app/builder/actions.py) — structurally, not by request — which
  is what makes the iOS review gate non-bypassable.
- The response never carries an invalid model: the draft is hard-validated
  server-side before /build responds; failure at the cap is a structured
  error, not a broken home.
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Callable, Optional

import anthropic
from pydantic import BaseModel, ConfigDict, Field

from app.builder import actions
from app.builder.actions import ActionError
from app.config import get_settings
from app.models import HomeModel

logger = logging.getLogger("app.ai.builder")

TEMPERATURE = 0.2
MAX_TOKENS = 4096
MAX_ITERATIONS = 40
"""Higher than the inspector's 15: construction takes one tool call per room/
opening/object, so a 3-bed two-story home legitimately needs ~30 calls."""


class ToolCallRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    tool_name: str
    input: dict[str, Any]
    output: Any


class BuildResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home: Optional[HomeModel]
    trace: list[ToolCallRecord]
    truncated: bool
    issues: list[str] = Field(
        default_factory=list,
        description="Validation errors when the loop ended without a valid home.",
    )


class BuilderError(Exception):
    """The builder could not run at all (configuration, not model output)."""


# ---------------------------------------------------------------------------
# Tools — construction only. No routing, no egress, nothing that would let the
# model claim safety facts.

_POINT = {"type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 2}

TOOLS: list[dict[str, Any]] = [
    {
        "name": "start_home",
        "description": "Start a new empty home draft. Call exactly once, first.",
        "input_schema": {
            "type": "object",
            "properties": {"name": {"type": "string"}},
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "add_floor",
        "description": "Add a floor. level 0 = ground, 1 = second story, -1 = basement.",
        "input_schema": {
            "type": "object",
            "properties": {
                "level": {"type": "integer"},
                "name": {"type": "string"},
                "height_m": {"type": "number"},
            },
            "required": ["level", "name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "add_room",
        "description": (
            "Add a room to a floor. The polygon is the room's footprint in meters "
            "(floor-local frame, vertex list, do NOT repeat the first vertex; "
            "counter-clockwise preferred but clockwise is auto-corrected). Adjacent "
            "rooms MUST share wall lines exactly (same coordinates) so doors between "
            "them derive as interior."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "floor_id": {"type": "string"},
                "name": {"type": "string"},
                "type": {
                    "type": "string",
                    "enum": ["bedroom", "living", "kitchen", "hall", "bath", "garage", "other"],
                },
                "polygon": {"type": "array", "items": _POINT, "minItems": 3},
            },
            "required": ["floor_id", "name", "type", "polygon"],
            "additionalProperties": False,
        },
    },
    {
        "name": "add_opening",
        "description": (
            "Place a door or window on a room's wall. edge_index i is the wall from "
            "polygon vertex i to vertex i+1 (mod n); t in [0,1] is where along that "
            "wall the opening centers. Interior vs exterior is DERIVED from geometry "
            "— a door on a wall shared with another room connects them; on an outside "
            "wall it is an exit. Omit width/height/sill for sensible defaults."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "kind": {"type": "string", "enum": ["door", "window"]},
                "room_id": {"type": "string"},
                "edge_index": {"type": "integer", "minimum": 0},
                "t": {"type": "number", "minimum": 0, "maximum": 1},
                "width_m": {"type": "number"},
                "height_m": {"type": "number"},
                "sill_height_m": {"type": "number"},
            },
            "required": ["kind", "room_id", "edge_index", "t"],
            "additionalProperties": False,
        },
    },
    {
        "name": "add_stairs",
        "description": "Connect two rooms on DIFFERENT floors with a staircase.",
        "input_schema": {
            "type": "object",
            "properties": {
                "from_room_id": {"type": "string"},
                "to_room_id": {"type": "string"},
                "kind": {"type": "string", "enum": ["straight", "L", "U"]},
            },
            "required": ["from_room_id", "to_room_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "add_object",
        "description": (
            "Place a large object (furniture) as a box: center [x,y] meters, "
            "size_m [width,depth], height_m, optional rotation_deg CCW."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "floor_id": {"type": "string"},
                "category": {
                    "type": "string",
                    "enum": ["bed", "sofa", "table", "wardrobe", "appliance", "storage", "other"],
                },
                "center": _POINT,
                "size_m": _POINT,
                "height_m": {"type": "number"},
                "rotation_deg": {"type": "number"},
            },
            "required": ["floor_id", "category", "center", "size_m", "height_m"],
            "additionalProperties": False,
        },
    },
    {
        "name": "rename_room",
        "description": "Rename a room.",
        "input_schema": {
            "type": "object",
            "properties": {"room_id": {"type": "string"}, "name": {"type": "string"}},
            "required": ["room_id", "name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "set_room_type",
        "description": "Change a room's type.",
        "input_schema": {
            "type": "object",
            "properties": {
                "room_id": {"type": "string"},
                "type": {
                    "type": "string",
                    "enum": ["bedroom", "living", "kitchen", "hall", "bath", "garage", "other"],
                },
            },
            "required": ["room_id", "type"],
            "additionalProperties": False,
        },
    },
    {
        "name": "delete",
        "description": "Delete a room, opening, object, or stairs by id (to fix mistakes).",
        "input_schema": {
            "type": "object",
            "properties": {"entity_id": {"type": "string"}},
            "required": ["entity_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "inspect_model",
        "description": "See the current draft: floors, rooms (with polygons), openings, objects, stairs.",
        "input_schema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "validate_model",
        "description": (
            "Run the full schema validation on the draft. Returns a list of "
            "actionable errors ([] = valid). Call before submitting."
        ),
        "input_schema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "submit_home",
        "description": (
            "Finish: submit the draft. Only succeeds when validate_model returns no "
            "errors and every floor has at least one exterior door or viable path out."
        ),
        "input_schema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
]


BUILDER_SYSTEM_PROMPT = """\
You are the house-plan builder for Escape Plan, a home fire escape planning app. \
From the user's description and/or floor-plan image you construct a structured \
model of their home using the tools. Hard rules:

1. You build GEOMETRY only. You never give safety advice, never invent routes, \
   and never claim the home is safe — a deterministic engine computes escape \
   routes later, after a human reviews your draft in the editor.
2. Work in meters in a consistent floor-local frame per floor (x right, y up on \
   the plan). Typical rooms are 3–5 m on a side; keep proportions from the \
   plan. When the input gives dimensions, use them exactly.
3. Rooms that touch MUST share wall lines exactly (identical coordinates along \
   the shared stretch) — that is how a door between them derives as interior. \
   Doors to the outside go on outside walls (they become exits automatically).
4. Every home needs at least one exterior door, and every bedroom should have \
   a window. Multi-floor homes need stairs connecting them.
5. Build step by step: start_home → add_floor → add_room per room → \
   add_opening per door/window → add_stairs → add_object for large furniture \
   the input mentions. Use inspect_model to re-orient and validate_model to \
   check; fix problems with delete/re-add. When validate_model returns no \
   errors, call submit_home.
6. If the input is not a home description/floor plan at all, or is too vague to \
   place a single room, submit nothing: call validate_model, then respond in \
   plain text explaining what you need — do not invent a house the user never \
   described.
"""


# ---------------------------------------------------------------------------
# Dispatch


def _make_ids() -> Callable[[str], str]:
    counters: dict[str, int] = {}

    def next_id(prefix: str) -> str:
        counters[prefix] = counters.get(prefix, 0) + 1
        return f"{prefix}_{counters[prefix]}"

    return next_id


def _dispatch(
    name: str,
    tool_input: dict[str, Any],
    draft: dict | None,
    next_id: Callable[[str], str],
    home_id: str,
    now_iso: str,
) -> tuple[Any, dict | None]:
    """Returns (tool output, new draft)."""
    if name == "start_home":
        if draft is not None:
            return {"error": "start_home was already called"}, draft
        draft = actions.new_draft(tool_input["name"], home_id, now_iso)
        return {"ok": True, "home_id": home_id}, draft

    if draft is None:
        return {"error": "call start_home first"}, None

    try:
        if name == "add_floor":
            fid = next_id("floor")
            return actions.add_floor(
                draft, floor_id=fid, level=tool_input["level"],
                name=tool_input["name"], height_m=tool_input.get("height_m", 2.7),
            ), draft
        if name == "add_room":
            rid = next_id("room")
            return actions.add_room(
                draft, room_id=rid, floor_id=tool_input["floor_id"],
                name=tool_input["name"], type=tool_input["type"],
                polygon=tool_input["polygon"],
            ), draft
        if name == "add_opening":
            oid = next_id(tool_input["kind"])
            return actions.add_opening(
                draft, opening_id=oid, kind=tool_input["kind"],
                room_id=tool_input["room_id"], edge_index=tool_input["edge_index"],
                t=tool_input["t"], width_m=tool_input.get("width_m"),
                height_m=tool_input.get("height_m"),
                sill_height_m=tool_input.get("sill_height_m"),
            ), draft
        if name == "add_stairs":
            sid = next_id("stairs")
            return actions.add_stairs(
                draft, stairs_id=sid, from_room_id=tool_input["from_room_id"],
                to_room_id=tool_input["to_room_id"],
                kind=tool_input.get("kind", "straight"),
            ), draft
        if name == "add_object":
            oid = next_id("object")
            return actions.add_object(
                draft, object_id=oid, floor_id=tool_input["floor_id"],
                category=tool_input["category"], center=tool_input["center"],
                size_m=tool_input["size_m"], height_m=tool_input["height_m"],
                rotation_deg=tool_input.get("rotation_deg", 0.0),
            ), draft
        if name == "rename_room":
            return actions.rename_room(
                draft, room_id=tool_input["room_id"], name=tool_input["name"]
            ), draft
        if name == "set_room_type":
            return actions.set_room_type(
                draft, room_id=tool_input["room_id"], type=tool_input["type"]
            ), draft
        if name == "delete":
            return actions.delete(draft, entity_id=tool_input["entity_id"]), draft
        if name == "inspect_model":
            return actions.inspect(draft), draft
        if name == "validate_model":
            return {"errors": actions.validate_draft(draft)}, draft
    except ActionError as exc:
        return {"error": str(exc)}, draft
    except (KeyError, TypeError, ValueError) as exc:
        return {"error": f"bad input: {exc}"}, draft

    return {"error": f"unknown tool: {name}"}, draft


# ---------------------------------------------------------------------------
# The loop


def _client() -> anthropic.Anthropic:
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise BuilderError("ANTHROPIC_API_KEY is not configured on the server")
    return anthropic.Anthropic(api_key=settings.anthropic_api_key)


def run_builder(
    *,
    description: str | None = None,
    image_b64: str | None = None,
    image_media_type: str = "image/png",
    client: Optional[anthropic.Anthropic] = None,
    max_iterations: int = MAX_ITERATIONS,
    home_id: str | None = None,
    now_iso: str | None = None,
) -> BuildResult:
    """Run the construction loop. At least one of description/image required."""
    if not description and not image_b64:
        raise BuilderError("provide a description, a floor-plan image, or both")
    client = client or _client()
    settings = get_settings()
    home_id = home_id or str(uuid.uuid4())
    now_iso = now_iso or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    next_id = _make_ids()

    content: list[dict[str, Any]] = []
    if image_b64:
        content.append({
            "type": "image",
            "source": {"type": "base64", "media_type": image_media_type, "data": image_b64},
        })
    if image_b64 and description:
        what = "floor plan and description"
    elif image_b64:
        what = "floor plan"
    else:
        what = "home description"
    content.append({
        "type": "text",
        "text": f"Build the structured home model for this {what}"
        + (f":\n\n{description}" if description else "."),
    })
    messages: list[dict[str, Any]] = [{"role": "user", "content": content}]

    trace: list[ToolCallRecord] = []
    draft: dict | None = None

    for _ in range(max_iterations):
        response = client.messages.create(
            model=settings.anthropic_model,
            max_tokens=MAX_TOKENS,
            temperature=TEMPERATURE,
            system=BUILDER_SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )
        messages.append({"role": "assistant", "content": response.content})

        tool_uses = [b for b in response.content if b.type == "tool_use"]
        if not tool_uses:
            break

        submit = next((t for t in tool_uses if t.name == "submit_home"), None)
        tool_results: list[dict[str, Any]] = []
        for tu in tool_uses:
            if tu.name == "submit_home":
                continue
            output, draft = _dispatch(tu.name, tu.input, draft, next_id, home_id, now_iso)
            trace.append(ToolCallRecord(id=tu.id, tool_name=tu.name,
                                        input=dict(tu.input), output=output))
            tool_results.append({
                "type": "tool_result", "tool_use_id": tu.id,
                "content": json.dumps(output, default=str),
            })

        if submit is not None:
            issues = actions.validate_draft(draft) if draft is not None else [
                "nothing was built — call start_home first"
            ]
            if not issues:
                home = HomeModel.model_validate(draft)
                trace.append(ToolCallRecord(id=submit.id, tool_name="submit_home",
                                            input={}, output={"ok": True}))
                return BuildResult(home=home, trace=trace, truncated=False)
            # Reject the submission with the validation errors so the model
            # can fix the draft and resubmit within the budget.
            trace.append(ToolCallRecord(id=submit.id, tool_name="submit_home",
                                        input={}, output={"errors": issues}))
            tool_results.append({
                "type": "tool_result", "tool_use_id": submit.id,
                "content": json.dumps({"rejected": True, "errors": issues}),
            })

        messages.append({"role": "user", "content": tool_results})

    issues = actions.validate_draft(draft) if draft is not None else [
        "the model did not construct a home"
    ]
    logger.warning("builder ended without a valid submission (%d issues)", len(issues))
    return BuildResult(home=None, trace=trace, truncated=True, issues=issues)
