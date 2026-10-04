"""RoomPlan export → HomeModel conversion (pure functions, no I/O).

Entry point: :func:`convert_scan`. Design target is "80% right + flagged
uncertainty": anything the converter can't resolve is kept and demoted to low
confidence for the editor to highlight — never silently dropped, never a crash.
"""

from __future__ import annotations

import math
import statistics
import uuid
from dataclasses import dataclass
from pydantic import ValidationError
from datetime import datetime
from typing import Any, Optional


from app.convert.geometry import (
    EdgePlacement,
    PolygonResult,
    WallSegment,
    place_opening_on_polygon,
    polygon_from_walls,
)
from app.convert.roomplan import RPRoom, RPStructure, RPSurface
from app.schema_migrator import CURRENT_VERSION
from app.models import (
    EXTERIOR_ID,
    Floor,
    FloorObject,
    HomeModel,
    Meta,
    ObjectCategory,
    Opening,
    OpeningKind,
    Point,
    Room,
    RoomType,
    Source,
)

_ID_NAMESPACE = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")  # uuid.NAMESPACE_DNS

UNRESOLVED_DISTANCE_M = 0.5
"""An opening whose center is farther than this from its chosen edge is demoted."""

UNRESOLVED_CONFIDENCE = 0.25
"""Demotion ceiling for unresolved placements (editor highlights <= low)."""

SHARED_DOOR_MAX_DIST_M = 0.35
SHARED_DOOR_PARALLEL_DOT = 0.9

DEFAULT_WALL_HEIGHT_M = 2.4

_SECTION_ROOM_TYPES: dict[str, RoomType] = {
    "bedroom": RoomType.bedroom,
    "livingroom": RoomType.living,
    "diningroom": RoomType.living,
    "kitchen": RoomType.kitchen,
    "bathroom": RoomType.bath,
    "toilet": RoomType.bath,
    "hallway": RoomType.hall,
    "entryway": RoomType.hall,
    "corridor": RoomType.hall,
    "stairs": RoomType.hall,
    "garage": RoomType.garage,
}


_OBJ_CATEGORY_MAP: dict[str, ObjectCategory] = {
    "bed": ObjectCategory.bed,
    "sofa": ObjectCategory.sofa,
    "table": ObjectCategory.table,
    "storage": ObjectCategory.storage,
    "television": ObjectCategory.tv,
    "stove": ObjectCategory.heat_source,
    "oven": ObjectCategory.heat_source,
    "fireplace": ObjectCategory.heat_source,
    "refrigerator": ObjectCategory.appliance,
    "dishwasher": ObjectCategory.appliance,
    "washerDryer": ObjectCategory.appliance,
}

_DROPPED_OBJ_CATS: set[str] = {"chair", "sink", "toilet", "bathtub", "stairs"}


def _slug(identifier: str, prefix: str) -> str:
    """Deterministic short id from a RoomPlan identifier (idempotency depends on this)."""
    return f"{prefix}-{uuid.uuid5(_ID_NAMESPACE, identifier).hex[:8]}"


def _room_type(room: RPRoom) -> tuple[RoomType, Optional[str]]:
    for section in room.sections:
        key = "".join(ch for ch in section.label.lower() if ch.isalnum())
        if key in _SECTION_ROOM_TYPES:
            return _SECTION_ROOM_TYPES[key], section.label
    return RoomType.other, room.sections[0].label if room.sections else None


def _room_identifier(room: RPRoom, index: int) -> str:
    if room.identifier:
        return room.identifier
    if room.walls:
        return "|".join(sorted(w.identifier for w in room.walls))
    return f"room-index-{index}"


@dataclass
class _ConvertedRoom:
    room_id: str
    result: PolygonResult
    floor_y: float
    confidence: float


def _convert_room(room: RPRoom, index: int) -> tuple[Room, _ConvertedRoom]:
    segments = [WallSegment(*w.plan_segment) for w in room.walls]
    result = polygon_from_walls(segments)

    wall_conf = [w.confidence.value_float for w in room.walls]
    base_conf = statistics.fmean(wall_conf) if wall_conf else 0.3
    confidence = round(max(0.05, min(1.0, base_conf * result.quality)), 2)

    floor_y = min((w.bottom_y for w in room.walls), default=0.0)
    room_type, label = _room_type(room)
    room_id = _slug(_room_identifier(room, index), "room")
    name = _humanize(label) if label else f"Room {index + 1}"

    model_room = Room(
        id=room_id,
        name=name,
        type=room_type,
        polygon=result.polygon,
        source=Source.scan,
        confidence=confidence,
    )
    return model_room, _ConvertedRoom(room_id, result, floor_y, confidence)


def _humanize(label: str) -> str:
    # "livingRoom" -> "Living Room"
    out = []
    for ch in label:
        if ch.isupper() and out and out[-1] != " ":
            out.append(" ")
        out.append(ch)
    return "".join(out).strip().title()


# ---------------------------------------------------------------------------
# Shared-door pairing
# ---------------------------------------------------------------------------

@dataclass
class _RawOpening:
    room_index: int
    surface: RPSurface
    kind: OpeningKind


def _pair_shared_doors(raw: list[_RawOpening]) -> list[tuple[_RawOpening, Optional[_RawOpening]]]:
    """Pair door surfaces that appear in two different rooms (same identifier, or
    coincident geometry). Windows are never paired. Returns (primary, partner|None)."""
    pairs: list[tuple[_RawOpening, Optional[_RawOpening]]] = []
    used: set[int] = set()

    doors = [
        (i, r) for i, r in enumerate(raw) if r.kind == OpeningKind.door
    ]

    # Pass 1: identical identifiers across different rooms (merged-structure dedup).
    by_identifier: dict[str, list[int]] = {}
    for i, r in doors:
        by_identifier.setdefault(r.surface.identifier, []).append(i)
    for indices in by_identifier.values():
        if len(indices) >= 2 and raw[indices[0]].room_index != raw[indices[1]].room_index:
            a, b = indices[0], indices[1]
            pairs.append((raw[a], raw[b]))
            used.update((a, b))

    # Pass 2: geometric coincidence among the rest.
    unpaired = [(i, r) for i, r in doors if i not in used]
    for pos, (i, r) in enumerate(unpaired):
        if i in used:
            continue
        ci, di = r.surface.plan_center, r.surface.plan_direction
        for j, s in unpaired[pos + 1:]:
            if j in used or s.room_index == r.room_index:
                continue
            cj, dj = s.surface.plan_center, s.surface.plan_direction
            dot = abs(di[0] * dj[0] + di[1] * dj[1])
            if math.dist(ci, cj) <= SHARED_DOOR_MAX_DIST_M and dot >= SHARED_DOOR_PARALLEL_DOT:
                pairs.append((r, s))
                used.update((i, j))
                break

    for i, r in enumerate(raw):
        if i not in used:
            pairs.append((r, None))
    return pairs


# ---------------------------------------------------------------------------
# Opening conversion
# ---------------------------------------------------------------------------

def _convert_opening(
    primary: _RawOpening,
    partner: Optional[_RawOpening],
    rooms: list[_ConvertedRoom],
    polygons: list[list[Point]],
) -> Opening:
    surface = primary.surface
    host = rooms[primary.room_index]
    placement: EdgePlacement = place_opening_on_polygon(
        polygons[primary.room_index],
        surface.plan_center,
        surface.plan_direction,
        surface.width,
    )

    confidence = surface.confidence.value_float
    if partner is not None:
        confidence = min(confidence, partner.surface.confidence.value_float)
    if placement.distance_m > UNRESOLVED_DISTANCE_M:
        confidence = min(confidence, UNRESOLVED_CONFIDENCE)
    confidence = round(max(0.05, confidence), 2)

    other_room_id = rooms[partner.room_index].room_id if partner else EXTERIOR_ID

    if primary.kind == OpeningKind.window:
        sill = max(0.0, round(surface.bottom_y - host.floor_y, 3))
    else:
        sill = 0.0

    return Opening(
        id=_slug(surface.identifier, "op"),
        kind=primary.kind,
        room_ids=[host.room_id, other_room_id],
        wall_segment={
            "room_id": host.room_id,
            "edge_index": placement.edge_index,
            "t0": placement.t0,
            "t1": placement.t1,
        },
        width_m=round(max(surface.width, 0.01), 3),
        height_m=round(max(surface.height, 0.01), 3),
        sill_height_m=sill,
        source=Source.scan,
        confidence=confidence,
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

class ConversionError(ValueError):
    """The scan is malformed in a way the converter can name. Callers treat it as
    the client's fault (HTTP 422); any other exception out of `convert_scan` is a bug."""


def convert_scan(
    export: dict[str, Any] | RPStructure,
    *,
    home_name: str = "Scanned Home",
    timestamp: datetime,
) -> tuple[HomeModel, list[str]]:
    """Convert a RoomPlan JSON export (see README.md for the assumed format) into a
    validated HomeModel. Deterministic: the same export and timestamp always produce
    an identical model (idempotency is a S1.5 acceptance criterion).

    v1 scope: one floor per scan session (multi-floor homes are scanned one floor at
    a time; stairs are added in the editor).
    """
    if isinstance(export, RPStructure):
        structure = export
    else:
        try:
            structure = RPStructure.parse(export)
        except ValidationError as exc:
            raise ConversionError("not a valid RoomPlan export") from exc

    model_rooms: list[Room] = []
    converted: list[_ConvertedRoom] = []
    warnings: list[str] = []
    for index, room in enumerate(structure.rooms):
        model_room, conv = _convert_room(room, index)
        model_rooms.append(model_room)
        converted.append(conv)
        for note in conv.result.notes:
            warnings.append(f"{model_room.name}: {note}")
    polygons = [list(r.polygon) for r in model_rooms]

    raw: list[_RawOpening] = []
    for index, room in enumerate(structure.rooms):
        for surface in room.doors:
            raw.append(_RawOpening(index, surface, OpeningKind.door))
        # Doorless passages: schema has no "passage" kind; a zero-leaf door is the
        # closest safe mapping and keeps the adjacency edge for routing.
        for surface in room.openings:
            raw.append(_RawOpening(index, surface, OpeningKind.door))
        for surface in room.windows:
            raw.append(_RawOpening(index, surface, OpeningKind.window))

    openings = [
        _convert_opening(primary, partner, converted, polygons)
        for primary, partner in _pair_shared_doors(raw)
    ]
    # Deterministic order regardless of pairing traversal order.
    openings.sort(key=lambda o: o.id)

    model_objects: list[FloorObject] = []
    dropped_objects = 0
    for index, room in enumerate(structure.rooms):
        host_floor_y = converted[index].floor_y
        for obj in room.objects:
            if obj.category in _DROPPED_OBJ_CATS:
                dropped_objects += 1
                continue
            cat = _OBJ_CATEGORY_MAP.get(obj.category, ObjectCategory.other)
            cx, cz = obj.plan_center
            
            elevation = max(0.0, round(obj.center_y - obj.dimensions[1] / 2.0 - host_floor_y, 3))
            if elevation < 0.01:
                elevation = 0.0
            
            height = round(max(obj.dimensions[1], 0.01), 3)
            size_x, _, size_z = obj.dimensions
            size_x = round(max(size_x, 0.01), 3)
            size_z = round(max(size_z, 0.01), 3)
            
            model_objects.append(
                FloorObject(
                    id=_slug(obj.identifier, "obj"),
                    category=cat,
                    center=(round(cx, 3), round(cz, 3)),
                    size_m=(size_x, size_z),
                    height_m=height,
                    rotation_deg=round(obj.rotation_deg, 3),
                    secured=False,
                    elevation_m=elevation,
                    source=Source.scan,
                    confidence=obj.confidence.value_float,
                )
            )
            
    if dropped_objects > 0:
        warnings.append(f"Dropped {dropped_objects} objects of excluded categories.")

    heights = [w.height for room in structure.rooms for w in room.walls]
    height_m = round(statistics.median(heights), 3) if heights else DEFAULT_WALL_HEIGHT_M

    all_surface_ids = sorted(
        s.identifier
        for room in structure.rooms
        for s in (*room.walls, *room.doors, *room.windows, *room.openings)
    )
    home_id = str(uuid.uuid5(_ID_NAMESPACE, "|".join(all_surface_ids) or home_name))

    model = HomeModel(
        schema_version=CURRENT_VERSION,
        home_id=home_id,
        name=home_name,
        floors=[
            Floor(
                id="floor-scan-0",
                level=0,
                name="Scanned Floor",
                height_m=max(height_m, 0.01),
                rooms=model_rooms,
                openings=openings,
                objects=model_objects,
            )
        ],
        stairs=[],
        profiles=[],
        meta=Meta(created=timestamp, modified=timestamp),
    )
    return model, warnings
