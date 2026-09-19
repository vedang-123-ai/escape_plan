"""Pure construction actions for the LLM house builder (revamp C1).

The Python mirror of the editor's EditAction vocabulary — NOT a port of the
Swift core. The shared semantics live in the pydantic validators both halves
already agree on: every action mutates a draft dict, and `validate_draft`
(plus the hard gate before /build responds) runs the full HomeModel model.
The only editor logic re-expressed here is parametric opening placement:
span clamping and adjacency-derived room_ids (mirror of
escape_plan/Editor/Core/OpeningPlacement.swift — interior vs EXTERIOR is
geometry, the model is never asked).

Provenance is stamped structurally: everything a builder action creates gets
source="ai_plan" + confidence=0.5, which is what makes the iOS review gate
non-bypassable — the model cannot emit a "trusted" element.

Pure functions over plain dicts; deterministic (caller supplies ids/now).
"""

from __future__ import annotations

import math
from typing import Any

from pydantic import ValidationError

from app.models import EXTERIOR_ID, SCHEMA_VERSION, HomeModel

AI_CONFIDENCE = 0.5
EPS = 1e-6

DOOR_DEFAULTS = {"width_m": 0.9, "height_m": 2.0, "sill_height_m": 0.0}
WINDOW_DEFAULTS = {"width_m": 1.0, "height_m": 1.2, "sill_height_m": 0.8}


class ActionError(Exception):
    """A structured rejection — returned to the model as the tool result."""


# ---------------------------------------------------------------------------
# Geometry (minimal, mirrors Editor/Core semantics)


def _signed_area(polygon: list[list[float]]) -> float:
    area2 = 0.0
    n = len(polygon)
    for i in range(n):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % n]
        area2 += x1 * y2 - x2 * y1
    return area2 / 2.0


def normalize_ccw(polygon: list[list[float]]) -> list[list[float]]:
    """Be forgiving: a clockwise polygon from the model is reversed, not rejected."""
    if _signed_area(polygon) < 0:
        return list(reversed(polygon))
    return polygon


def _point_on_edge(polygon: list[list[float]], edge_index: int, t: float) -> list[float]:
    p = polygon[edge_index]
    q = polygon[(edge_index + 1) % len(polygon)]
    return [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]


def _edge_length(polygon: list[list[float]], edge_index: int) -> float:
    p = polygon[edge_index]
    q = polygon[(edge_index + 1) % len(polygon)]
    return math.hypot(q[0] - p[0], q[1] - p[1])


def _cross(o: list[float], a: list[float], b: list[float]) -> float:
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def segments_overlap_collinearly(
    a: list[float], b: list[float], p: list[float], q: list[float]
) -> bool:
    """True when segment pq is collinear with ab and their 1D projections
    overlap by more than a point — the editor's adjacency test."""
    if abs(_cross(a, b, p)) > EPS or abs(_cross(a, b, q)) > EPS:
        return False
    dx, dy = b[0] - a[0], b[1] - a[1]
    length2 = dx * dx + dy * dy
    if length2 < EPS:
        return False

    def proj(pt: list[float]) -> float:
        return ((pt[0] - a[0]) * dx + (pt[1] - a[1]) * dy) / length2

    lo1, hi1 = 0.0, 1.0
    lo2, hi2 = sorted((proj(p), proj(q)))
    return min(hi1, hi2) - max(lo1, lo2) > EPS


def opening_span(center_t: float, width_m: float, edge_length: float) -> tuple[float, float]:
    """t0/t1 for an opening centered as close to center_t as the edge allows
    (mirror of OpeningPlacement.span). Raises when the wall is too short."""
    if edge_length <= EPS or width_m <= 0 or width_m > edge_length:
        raise ActionError(
            f"wall is too short for a {width_m:.2f}m opening (wall is {edge_length:.2f}m)"
        )
    half_t = (width_m / 2) / edge_length
    clamped = min(1 - half_t, max(half_t, center_t))
    return (clamped - half_t, clamped + half_t)


# ---------------------------------------------------------------------------
# Draft helpers


def new_draft(name: str, home_id: str, now_iso: str) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "home_id": home_id,
        "name": name,
        "floors": [],
        "stairs": [],
        "profiles": [],
        "meta": {"created": now_iso, "modified": now_iso, "address_optional": None},
    }


def _floor(draft: dict, floor_id: str) -> dict:
    for floor in draft["floors"]:
        if floor["id"] == floor_id:
            return floor
    raise ActionError(f"no such floor_id: {floor_id}")


def _room(draft: dict, room_id: str) -> tuple[dict, dict]:
    for floor in draft["floors"]:
        for room in floor["rooms"]:
            if room["id"] == room_id:
                return floor, room
    raise ActionError(f"no such room_id: {room_id}")


def _all_ids(draft: dict) -> set[str]:
    ids: set[str] = set()
    for floor in draft["floors"]:
        ids.add(floor["id"])
        ids.update(r["id"] for r in floor["rooms"])
        ids.update(o["id"] for o in floor["openings"])
        ids.update(o["id"] for o in floor["objects"])
    ids.update(s["id"] for s in draft["stairs"])
    return ids


# ---------------------------------------------------------------------------
# Actions — each mutates `draft` in place and returns a result dict for the
# model. Rejections raise ActionError with an actionable message.


def add_floor(draft: dict, *, floor_id: str, level: int, name: str,
              height_m: float = 2.7) -> dict:
    if any(f["level"] == level for f in draft["floors"]):
        raise ActionError(f"a floor with level {level} already exists")
    if floor_id in _all_ids(draft):
        raise ActionError(f"id '{floor_id}' is already taken")
    if height_m <= 0:
        raise ActionError("height_m must be positive")
    draft["floors"].append({
        "id": floor_id, "level": level, "name": name, "height_m": height_m,
        "rooms": [], "openings": [], "objects": [],
    })
    draft["floors"].sort(key=lambda f: f["level"])
    return {"floor_id": floor_id, "level": level}


def add_room(draft: dict, *, room_id: str, floor_id: str, name: str, type: str,
             polygon: list[list[float]]) -> dict:
    floor = _floor(draft, floor_id)
    if room_id in _all_ids(draft) or room_id == EXTERIOR_ID:
        raise ActionError(f"id '{room_id}' is already taken or reserved")
    if len(polygon) < 3:
        raise ActionError("polygon needs at least 3 vertices")
    poly = normalize_ccw([list(map(float, p)) for p in polygon])
    floor["rooms"].append({
        "id": room_id, "name": name, "type": type, "polygon": poly,
        "source": "ai_plan", "confidence": AI_CONFIDENCE,
    })
    return {"room_id": room_id, "floor_id": floor_id,
            "area_m2": round(abs(_signed_area(poly)), 2)}


def add_opening(draft: dict, *, opening_id: str, kind: str, room_id: str,
                edge_index: int, t: float,
                width_m: float | None = None, height_m: float | None = None,
                sill_height_m: float | None = None) -> dict:
    floor, room = _room(draft, room_id)
    if opening_id in _all_ids(draft) or opening_id == EXTERIOR_ID:
        raise ActionError(f"id '{opening_id}' is already taken or reserved")
    if kind not in ("door", "window"):
        raise ActionError("kind must be 'door' or 'window'")
    poly = room["polygon"]
    if not (0 <= edge_index < len(poly)):
        raise ActionError(
            f"edge_index {edge_index} out of range — room '{room_id}' has {len(poly)} edges"
        )
    defaults = DOOR_DEFAULTS if kind == "door" else WINDOW_DEFAULTS
    width = width_m if width_m is not None else defaults["width_m"]
    height = height_m if height_m is not None else defaults["height_m"]
    sill = sill_height_m if sill_height_m is not None else defaults["sill_height_m"]

    t0, t1 = opening_span(t, width, _edge_length(poly, edge_index))

    # Adjacency decides interior vs EXTERIOR — the model is never asked.
    a = _point_on_edge(poly, edge_index, t0)
    b = _point_on_edge(poly, edge_index, t1)
    other: str = EXTERIOR_ID
    for candidate in floor["rooms"]:
        if candidate["id"] == room_id:
            continue
        cpoly = candidate["polygon"]
        n = len(cpoly)
        if any(
            segments_overlap_collinearly(a, b, cpoly[i], cpoly[(i + 1) % n])
            for i in range(n)
        ):
            other = candidate["id"]
            break

    floor["openings"].append({
        "id": opening_id, "kind": kind, "room_ids": [room_id, other],
        "wall_segment": {"room_id": room_id, "edge_index": edge_index, "t0": t0, "t1": t1},
        "width_m": width, "height_m": height, "sill_height_m": sill,
        "source": "ai_plan", "confidence": AI_CONFIDENCE,
    })
    return {
        "opening_id": opening_id,
        "connects": [room_id, other],
        "is_exit": other == EXTERIOR_ID,
    }


def add_stairs(draft: dict, *, stairs_id: str, from_room_id: str, to_room_id: str,
               kind: str = "straight") -> dict:
    from_floor, from_room = _room(draft, from_room_id)
    to_floor, _to_room = _room(draft, to_room_id)
    if stairs_id in _all_ids(draft) or stairs_id == EXTERIOR_ID:
        raise ActionError(f"id '{stairs_id}' is already taken or reserved")
    if from_floor["id"] == to_floor["id"]:
        raise ActionError("stairs must connect rooms on DIFFERENT floors")
    if kind not in ("straight", "L", "U"):
        raise ActionError("kind must be one of straight | L | U")
    # By schema convention `from` is the lower floor.
    if from_floor["level"] > to_floor["level"]:
        from_floor, to_floor = to_floor, from_floor
        from_room_id, to_room_id = to_room_id, from_room_id
        _ignored, from_room = _room(draft, from_room_id)
    poly = from_room["polygon"]
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    draft["stairs"].append({
        "id": stairs_id,
        "from": {"floor_id": from_floor["id"], "room_id": from_room_id},
        "to": {"floor_id": to_floor["id"], "room_id": to_room_id},
        "footprint": [[cx - 0.5, cy - 0.5], [cx + 0.5, cy - 0.5],
                      [cx + 0.5, cy + 0.5], [cx - 0.5, cy + 0.5]],
        "kind": kind, "source": "ai_plan", "confidence": AI_CONFIDENCE,
    })
    return {"stairs_id": stairs_id, "from": from_room_id, "to": to_room_id}


def add_object(draft: dict, *, object_id: str, floor_id: str, category: str,
               center: list[float], size_m: list[float], height_m: float,
               rotation_deg: float = 0.0) -> dict:
    floor = _floor(draft, floor_id)
    if object_id in _all_ids(draft) or object_id == EXTERIOR_ID:
        raise ActionError(f"id '{object_id}' is already taken or reserved")
    if len(size_m) != 2 or size_m[0] <= 0 or size_m[1] <= 0 or height_m <= 0:
        raise ActionError("size_m must be [width, depth] > 0 and height_m > 0")
    floor["objects"].append({
        "id": object_id, "category": category, "center": list(map(float, center)),
        "size_m": list(map(float, size_m)), "height_m": height_m,
        "rotation_deg": rotation_deg, "source": "ai_plan", "confidence": AI_CONFIDENCE,
    })
    return {"object_id": object_id, "floor_id": floor_id}


def rename_room(draft: dict, *, room_id: str, name: str) -> dict:
    _floor_dict, room = _room(draft, room_id)
    room["name"] = name
    return {"room_id": room_id, "name": name}


def set_room_type(draft: dict, *, room_id: str, type: str) -> dict:
    _floor_dict, room = _room(draft, room_id)
    room["type"] = type
    return {"room_id": room_id, "type": type}


def delete(draft: dict, *, entity_id: str) -> dict:
    """Delete a room, opening, object, or stairs by id (self-correction).
    Deleting a room cascades to its openings and any stairs that land in it."""
    for floor in draft["floors"]:
        for room in list(floor["rooms"]):
            if room["id"] == entity_id:
                floor["rooms"].remove(room)
                floor["openings"] = [
                    o for o in floor["openings"] if entity_id not in o["room_ids"]
                    and o["wall_segment"]["room_id"] != entity_id
                ]
                draft["stairs"] = [
                    s for s in draft["stairs"]
                    if entity_id not in (s["from"]["room_id"], s["to"]["room_id"])
                ]
                return {"deleted": entity_id, "kind": "room"}
        for opening in list(floor["openings"]):
            if opening["id"] == entity_id:
                floor["openings"].remove(opening)
                return {"deleted": entity_id, "kind": "opening"}
        for obj in list(floor["objects"]):
            if obj["id"] == entity_id:
                floor["objects"].remove(obj)
                return {"deleted": entity_id, "kind": "object"}
    for stair in list(draft["stairs"]):
        if stair["id"] == entity_id:
            draft["stairs"].remove(stair)
            return {"deleted": entity_id, "kind": "stairs"}
    raise ActionError(f"no entity with id '{entity_id}'")


# ---------------------------------------------------------------------------
# Inspection + validation


def inspect(draft: dict) -> dict:
    """Compact summary the model can re-orient from."""
    return {
        "name": draft["name"],
        "floors": [
            {
                "id": f["id"], "level": f["level"], "name": f["name"],
                "rooms": [
                    {"id": r["id"], "name": r["name"], "type": r["type"],
                     "polygon": r["polygon"]}
                    for r in f["rooms"]
                ],
                "openings": [
                    {"id": o["id"], "kind": o["kind"], "connects": o["room_ids"]}
                    for o in f["openings"]
                ],
                "objects": [
                    {"id": o["id"], "category": o["category"], "center": o["center"]}
                    for o in f["objects"]
                ],
            }
            for f in draft["floors"]
        ],
        "stairs": [
            {"id": s["id"], "from": s["from"]["room_id"], "to": s["to"]["room_id"]}
            for s in draft["stairs"]
        ],
    }


def validate_draft(draft: dict) -> list[str]:
    """Full-model validation via the same pydantic gate everything else uses.
    Returns actionable error strings ([] = valid)."""
    if not draft["floors"]:
        return ["the home has no floors yet — add_floor first"]
    try:
        HomeModel.model_validate(draft)
        return []
    except ValidationError as exc:
        return [
            f"{'.'.join(str(loc) for loc in e['loc'])}: {e['msg']}" for e in exc.errors()
        ]
