"""Pydantic models for the HomeModel contract (schema/homemodel.schema.json v2.1).

These models are the executable half of the contract: JSON Schema checks shape,
these validators check the structural invariants JSON Schema cannot express —
polygon geometry (CCW, non-self-intersecting), cross-references (openings →
rooms/edges, stairs → floors/rooms, profiles → rooms), global id uniqueness,
and the scan-items-carry-confidence rule. Both must pass for a document to be
considered valid.
"""

from __future__ import annotations

import math
import sys
from datetime import datetime
from enum import Enum
from typing import Annotated, Optional, Literal, Any

from pydantic import BaseModel, ConfigDict, Field, model_validator

EXTERIOR_ID = "EXTERIOR"
"""Reserved pseudo-room id: an opening with room_ids [room, "EXTERIOR"] is an exit."""

Point = tuple[float, float]
Polygon = Annotated[list[Point], Field(min_length=3)]


class RoomType(str, Enum):
    bedroom = "bedroom"
    living = "living"
    kitchen = "kitchen"
    hall = "hall"
    bath = "bath"
    garage = "garage"
    other = "other"


class OpeningKind(str, Enum):
    door = "door"
    window = "window"


class Source(str, Enum):
    scan = "scan"
    manual = "manual"
    ai_plan = "ai_plan"


class ObjectCategory(str, Enum):
    bed = "bed"
    sofa = "sofa"
    table = "table"
    wardrobe = "wardrobe"
    appliance = "appliance"
    storage = "storage"
    other = "other"
    # v2.1 (S7.1). One category covers fixed stoves/ovens/fireplaces and portable
    # heaters alike: the clearance rule that reads it is the same for all of them.
    bookcase = "bookcase"
    tv = "tv"
    water_heater = "water_heater"
    heat_source = "heat_source"


class StairKind(str, Enum):
    straight = "straight"
    L = "L"
    U = "U"


class Tenure(str, Enum):
    rent = "rent"
    own = "own"

class Equipment(str, Enum):
    smoke_alarm = "smoke_alarm"
    co_detector = "co_detector"
    extinguisher = "extinguisher"
    generator = "generator"

class SafetyPointKind(str, Enum):
    gas_shutoff = "gas_shutoff"
    water_shutoff = "water_shutoff"
    electrical_panel = "electrical_panel"

class ProfileTag(str, Enum):
    child = "child"
    elderly = "elderly"
    mobility_limited = "mobility_limited"
    pet = "pet"
    hearing_impaired = "hearing_impaired"
    vision_impaired = "vision_impaired"


class StrictModel(BaseModel):
    """Base: reject unknown fields — the schema is a closed contract."""

    model_config = ConfigDict(extra="forbid")


# ---------------------------------------------------------------------------
# Geometry helpers (pure; shared with the routing engine)
# ---------------------------------------------------------------------------

def signed_area(polygon: list[Point]) -> float:
    """Shoelace signed area: positive iff the polygon is counter-clockwise."""
    area = 0.0
    n = len(polygon)
    for i in range(n):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return area / 2.0


def _orient(p: Point, q: Point, r: Point) -> float:
    return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])


def _on_segment(p: Point, q: Point, r: Point) -> bool:
    return (
        min(p[0], r[0]) <= q[0] <= max(p[0], r[0])
        and min(p[1], r[1]) <= q[1] <= max(p[1], r[1])
    )


def _segments_intersect(a1: Point, a2: Point, b1: Point, b2: Point) -> bool:
    d1 = _orient(b1, b2, a1)
    d2 = _orient(b1, b2, a2)
    d3 = _orient(a1, a2, b1)
    d4 = _orient(a1, a2, b2)
    if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and (
        (d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)
    ):
        return True
    if d1 == 0 and _on_segment(b1, a1, b2):
        return True
    if d2 == 0 and _on_segment(b1, a2, b2):
        return True
    if d3 == 0 and _on_segment(a1, b1, a2):
        return True
    if d4 == 0 and _on_segment(a1, b2, a2):
        return True
    return False


def is_simple_polygon(polygon: list[Point]) -> bool:
    """True if no two non-adjacent edges intersect and no edge is degenerate."""
    n = len(polygon)
    edges = [(polygon[i], polygon[(i + 1) % n]) for i in range(n)]
    for (p, q) in edges:
        if p == q:
            return False
    for i in range(n):
        for j in range(i + 1, n):
            # skip adjacent edges (they share a vertex by construction)
            if j == i + 1 or (i == 0 and j == n - 1):
                continue
            if _segments_intersect(*edges[i], *edges[j]):
                return False
    return True


def _validate_polygon(polygon: list[Point], owner: str) -> None:
    if not is_simple_polygon(polygon):
        raise ValueError(
            f"{owner}: polygon is degenerate or self-intersecting"
        )
    if signed_area(polygon) <= 0:
        raise ValueError(
            f"{owner}: polygon must be counter-clockwise (signed area > 0); "
            "reverse the vertex order"
        )


# ---------------------------------------------------------------------------
# Size bounds (S11.25, AUD-004)
# ---------------------------------------------------------------------------
#
# HomeModel validation used to check topology but never size, so one valid
# request could pin the free Render instance for hours. `build_room_grid`
# rasterizes each room's BOUNDING BOX at CELL_M = 0.1 m, so cost is linear in
# bounding-box cells — NOT in room area. A 75 m² diagonal sliver spanning
# 150 m × 150 m is 2,250,000 cells, 300× more than its area justifies, which is
# why an area cap alone does not close AUD-004.
#
# Measured on 2026-09-30 (three perils, as `/score` runs them): ~26 µs per
# bounding-box cell. Budget: a home at the maximum finishes a 3-peril `/score`
# in under 7 s on a 2026 Mac (measured 6.11 s at 252,491 cells).
#
# These numbers are mirrored in `escape_plan/Editor/Core/EditorValidation.swift`
# (`HomeSizeBounds`) so the editor can never build a home the server rejects.
# Change them in both places, or the editor starts producing 422s.
# See docs/decisions.md, 2026-09-30, for the headroom each bound carries.

MAX_COORD_M = 200.0
"""Any x or y in the home, in metres. Also rejects NaN and infinity."""

MAX_POLYGON_VERTICES = 64
"""Vertices in a room polygon or stairs footprint (`is_simple_polygon` is O(n²))."""

MAX_ROOM_SPAN_M = 60.0
"""Either side of a single room's bounding box."""

MAX_ROOM_AREA_M2 = 500.0
"""Absolute area of a single room polygon."""

MAX_ROOM_GRID_CELLS = 90_000
"""Bounding-box cells for one room: 900 m² of bounding box at CELL_M = 0.1 m."""

MAX_TOTAL_GRID_CELLS = 250_000
"""Bounding-box cells summed over every room on every floor. The binding bound."""

MAX_FLOORS = 8
MAX_ROOMS = 200
"""Rooms across the whole home, not per floor."""

MAX_OPENINGS_PER_FLOOR = 400
MAX_OBJECTS_PER_FLOOR = 500
MAX_SAFETY_POINTS_PER_FLOOR = 100
MAX_STAIRS = 50
MAX_PROFILES = 50

MAX_FLOOR_HEIGHT_M = 20.0
MAX_OPENING_DIM_M = 20.0
"""Width, height or sill height of one opening."""

MAX_OBJECT_SIZE_M = 50.0
MAX_OBJECT_HEIGHT_M = 20.0
MAX_OBJECT_ELEVATION_M = 100.0

_CELL_M = 0.1
"""Mirror of app.routing.nav_grid.CELL_M. Duplicated to keep models.py import-free
of the routing package (routing imports models, not the other way round);
`test_home_bounds.py` asserts the two stay equal."""


def bbox_cell_count(polygon: list[Point]) -> int:
    """Navigation-grid cells `build_room_grid` would rasterize for this polygon.

    Mirrors nav_grid.build_room_grid's `cols * rows` exactly: the bounding box at
    CELL_M, never fewer than one cell per axis. Pure; the bounds test and the
    validator share it.

    A non-finite extent returns `sys.maxsize` rather than raising, so this stays
    total for every input and agrees with `HomeSizeBounds.gridCellCount` in
    `EditorValidation.swift`, which saturates for the same reason (`Int(_:)` traps
    on NaN in Swift). Callers read a saturated value as "over every bound", which
    it is. `_validate_polygon_bounds` rejects a non-finite coordinate before it
    ever gets here, so this guard is for the next caller, not for the validator.
    """
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]

    def axis_cells(values: list[float]) -> int:
        # Every value, not just the extent: max()/min() silently SKIP a non-leading
        # NaN (all its comparisons are False), so `max(xs) - min(xs)` can come back
        # finite for a polygon that contains one.
        if not all(math.isfinite(v) for v in values):
            return sys.maxsize
        return max(1, int(math.ceil((max(values) - min(values)) / _CELL_M)))

    cols, rows = axis_cells(xs), axis_cells(ys)
    if sys.maxsize in (cols, rows):
        return sys.maxsize
    return cols * rows


def _check_coord(value: float, owner: str, axis: str) -> None:
    # NaN and infinity are a different bug from an oversized home (a converter
    # divided by zero, not a mansion), so they keep their own message.
    if not math.isfinite(value):
        raise ValueError(f"{owner}: {axis} coordinate must be finite, got {value}")
    if not (-MAX_COORD_M <= value <= MAX_COORD_M):
        raise ValueError(
            f"{owner}: {axis} coordinate {value} is outside the supported range "
            f"±{MAX_COORD_M:g} m. This app models a single residence; check the "
            "scan's origin if a converter produced this."
        )


def _validate_polygon_bounds(polygon: list[Point], owner: str) -> None:
    """Coordinate range, vertex count, span and grid cost for one polygon."""
    if len(polygon) > MAX_POLYGON_VERTICES:
        raise ValueError(
            f"{owner}: {len(polygon)} vertices exceeds the maximum of "
            f"{MAX_POLYGON_VERTICES}. Simplify the outline."
        )
    for (x, y) in polygon:
        _check_coord(x, owner, "x")
        _check_coord(y, owner, "y")
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    width, depth = max(xs) - min(xs), max(ys) - min(ys)
    if width > MAX_ROOM_SPAN_M or depth > MAX_ROOM_SPAN_M:
        raise ValueError(
            f"{owner}: bounding box {width:.1f} m × {depth:.1f} m exceeds the "
            f"maximum span of {MAX_ROOM_SPAN_M:g} m on a side."
        )
    cells = bbox_cell_count(polygon)
    if cells > MAX_ROOM_GRID_CELLS:
        raise ValueError(
            f"{owner}: its bounding box needs {cells:,} navigation-grid cells, "
            f"over the per-room maximum of {MAX_ROOM_GRID_CELLS:,}. A long thin "
            "room costs as much as the whole box it spans — split it or "
            "straighten it."
        )


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class WallSegmentRef(StrictModel):
    """Parametric placement on a room polygon edge (edge i = vertex i → i+1 mod n)."""

    room_id: str
    edge_index: int = Field(ge=0)
    t0: float = Field(ge=0.0, le=1.0)
    t1: float = Field(ge=0.0, le=1.0)

    @model_validator(mode="after")
    def _t_range(self) -> "WallSegmentRef":
        if not self.t0 < self.t1:
            raise ValueError(
                f"wall_segment on room '{self.room_id}': t0 ({self.t0}) must be < t1 ({self.t1})"
            )
        return self


class EgressAssessment(StrictModel):
    """Computed by the S1.1 egress annotator; never authored by hand or by the AI."""

    viable: bool
    reasons: list[str] = Field(default_factory=list)


class SourcedModel(StrictModel):
    """Common provenance fields; machine-derived items must carry confidence."""

    source: Source
    confidence: Optional[float] = Field(default=None, ge=0.0, le=1.0)

    @model_validator(mode="after")
    def _machine_source_needs_confidence(self) -> "SourcedModel":
        if self.source in (Source.scan, Source.ai_plan) and self.confidence is None:
            ident = getattr(self, "id", "?")
            raise ValueError(
                f"'{ident}': {self.source.value}-derived items must carry a confidence value"
            )
        return self


class Room(SourcedModel):
    id: str
    name: str = Field(min_length=1)
    type: RoomType
    polygon: Polygon

    @model_validator(mode="after")
    def _check(self) -> "Room":
        if self.id == EXTERIOR_ID:
            raise ValueError(f"'{EXTERIOR_ID}' is a reserved pseudo-room id")
        owner = f"room '{self.id}'"
        _validate_polygon(list(self.polygon), owner)
        _validate_polygon_bounds(list(self.polygon), owner)
        area = abs(signed_area(list(self.polygon)))
        if area > MAX_ROOM_AREA_M2:
            raise ValueError(
                f"{owner}: area {area:.1f} m² exceeds the maximum of "
                f"{MAX_ROOM_AREA_M2:g} m² for a single room."
            )
        return self


class Opening(SourcedModel):
    id: str
    kind: OpeningKind
    room_ids: list[str] = Field(min_length=2, max_length=2)
    wall_segment: WallSegmentRef
    width_m: float = Field(gt=0, le=MAX_OPENING_DIM_M)
    height_m: float = Field(gt=0, le=MAX_OPENING_DIM_M)
    sill_height_m: float = Field(ge=0, le=MAX_OPENING_DIM_M)
    egress: Optional[EgressAssessment] = None

    @model_validator(mode="after")
    def _check(self) -> "Opening":
        a, b = self.room_ids
        if a == b:
            raise ValueError(f"opening '{self.id}': room_ids must be distinct")
        if a == EXTERIOR_ID and b == EXTERIOR_ID:
            raise ValueError(
                f"opening '{self.id}': at least one side must be a real room"
            )
        if self.wall_segment.room_id not in self.room_ids:
            raise ValueError(
                f"opening '{self.id}': wall_segment.room_id "
                f"'{self.wall_segment.room_id}' must be one of room_ids {self.room_ids}"
            )
        if self.wall_segment.room_id == EXTERIOR_ID:
            raise ValueError(
                f"opening '{self.id}': wall_segment must be hosted on a real room, "
                f"not '{EXTERIOR_ID}'"
            )
        return self

    @property
    def is_exit(self) -> bool:
        return EXTERIOR_ID in self.room_ids


class SafetyPoint(SourcedModel):
    id: str
    kind: SafetyPointKind
    position: Point

    @model_validator(mode="after")
    def _check(self) -> "SafetyPoint":
        if self.id == EXTERIOR_ID:
            raise ValueError(f"'{EXTERIOR_ID}' is a reserved id")
        # _check_coord rejects NaN and infinity as well as out-of-range values,
        # so it subsumes the isfinite check this validator used to carry.
        owner = f"safety_point '{self.id}'"
        _check_coord(self.position[0], owner, "x")
        _check_coord(self.position[1], owner, "y")
        return self

class Household(StrictModel):
    tenure: Optional[Tenure] = None
    existing_equipment: list[Equipment] = Field(default_factory=list)

    @model_validator(mode="after")
    def _check(self) -> "Household":
        if len(set(self.existing_equipment)) != len(self.existing_equipment):
            raise ValueError("duplicate equipment")
        return self

class FloorObject(SourcedModel):
    """A large object as a rotated box primitive (v1.1). Rendered as a prism; treated as an
    obstacle by within-room routing. No room_id on purpose — containment is derived
    geometrically, so moving a room can never dangle an object reference."""

    id: str
    category: ObjectCategory
    center: Point
    size_m: tuple[float, float]
    height_m: float = Field(gt=0)
    rotation_deg: float = 0.0
    secured: bool = False
    # v2.1 (S7.1). Base height above the floor: the prism spans
    # elevation_m .. elevation_m + height_m, so height_m stays the object's OWN
    # height and 0 keeps every pre-2.1 object meaning exactly what it meant.
    elevation_m: float = Field(default=0.0, ge=0.0)
    # v2.1 (S7.1). How it is installed, not whether it is strapped — `secured`
    # answers that, and merging the two would make an unstrapped wardrobe look
    # safe the moment someone hung a picture.
    mounted: bool = False

    @model_validator(mode="after")
    def _check(self) -> "FloorObject":
        if self.id == EXTERIOR_ID:
            raise ValueError(f"'{EXTERIOR_ID}' is a reserved id")
        owner = f"object '{self.id}'"
        _check_coord(self.center[0], owner, "x")
        _check_coord(self.center[1], owner, "y")
        w, d = self.size_m
        if w <= 0 or d <= 0:
            raise ValueError(f"object '{self.id}': size_m must be positive, got {self.size_m}")
        if not (w <= MAX_OBJECT_SIZE_M and d <= MAX_OBJECT_SIZE_M):
            raise ValueError(
                f"{owner}: size_m {self.size_m} exceeds the maximum of "
                f"{MAX_OBJECT_SIZE_M:g} m on a side."
            )
        if not (self.height_m <= MAX_OBJECT_HEIGHT_M):
            raise ValueError(
                f"{owner}: height_m {self.height_m} exceeds the maximum of "
                f"{MAX_OBJECT_HEIGHT_M:g} m."
            )
        if not (self.elevation_m <= MAX_OBJECT_ELEVATION_M):
            raise ValueError(
                f"{owner}: elevation_m {self.elevation_m} exceeds the maximum of "
                f"{MAX_OBJECT_ELEVATION_M:g} m."
            )
        if not math.isfinite(self.rotation_deg):
            raise ValueError(f"{owner}: rotation_deg must be finite")
        return self


class Floor(StrictModel):
    id: str
    level: int
    name: str = Field(min_length=1)
    height_m: float = Field(gt=0, le=MAX_FLOOR_HEIGHT_M)
    rooms: list[Room] = Field(min_length=1, max_length=MAX_ROOMS)
    openings: list[Opening] = Field(default_factory=list, max_length=MAX_OPENINGS_PER_FLOOR)
    objects: list[FloorObject] = Field(default_factory=list, max_length=MAX_OBJECTS_PER_FLOOR)
    safety_points: list[SafetyPoint] = Field(
        default_factory=list, max_length=MAX_SAFETY_POINTS_PER_FLOOR
    )

    @model_validator(mode="after")
    def _check(self) -> "Floor":
        if self.id == EXTERIOR_ID:
            raise ValueError(f"'{EXTERIOR_ID}' is a reserved id")
        room_by_id = {r.id: r for r in self.rooms}
        for op in self.openings:
            for rid in op.room_ids:
                if rid != EXTERIOR_ID and rid not in room_by_id:
                    raise ValueError(
                        f"opening '{op.id}' references room '{rid}' which does not "
                        f"exist on floor '{self.id}'"
                    )
            host = room_by_id[op.wall_segment.room_id]
            if op.wall_segment.edge_index >= len(host.polygon):
                raise ValueError(
                    f"opening '{op.id}': edge_index {op.wall_segment.edge_index} is "
                    f"out of range for room '{host.id}' "
                    f"({len(host.polygon)} edges)"
                )
        return self


class StairEnd(StrictModel):
    floor_id: str
    room_id: str


class Stairs(SourcedModel):
    id: str
    from_: StairEnd = Field(alias="from")
    to: StairEnd
    footprint: Polygon
    kind: StairKind

    model_config = ConfigDict(extra="forbid", populate_by_name=True, serialize_by_alias=True)

    @model_validator(mode="after")
    def _check(self) -> "Stairs":
        if self.from_.floor_id == self.to.floor_id:
            raise ValueError(
                f"stairs '{self.id}': endpoints must be on different floors "
                f"(both on '{self.to.floor_id}')"
            )
        owner = f"stairs '{self.id}' footprint"
        _validate_polygon(list(self.footprint), owner)
        _validate_polygon_bounds(list(self.footprint), owner)
        return self


class Profile(StrictModel):
    id: str
    name: str = Field(min_length=1)
    tags: list[ProfileTag] = Field(default_factory=list)
    bedroom_room_id: str

    @model_validator(mode="after")
    def _check(self) -> "Profile":
        if len(set(self.tags)) != len(self.tags):
            raise ValueError(f"profile '{self.id}': duplicate tags")
        return self


class Meta(StrictModel):
    created: datetime
    modified: datetime
    address_optional: Optional[str] = None
    last_scanned: Optional[datetime] = None


class HomeModel(StrictModel):
    schema_version: Literal["2.1"]
    home_id: str
    name: str = Field(min_length=1)
    floors: list[Floor] = Field(min_length=1, max_length=MAX_FLOORS)
    stairs: list[Stairs] = Field(default_factory=list, max_length=MAX_STAIRS)
    profiles: list[Profile] = Field(default_factory=list, max_length=MAX_PROFILES)
    meta: Meta
    household: Optional[Household] = None

    @model_validator(mode="before")
    @classmethod
    def _migrate(cls, data: Any) -> Any:
        from app.schema_migrator import migrate
        return migrate(data)

    @model_validator(mode="after")
    def _size_bounds(self) -> "HomeModel":
        """Home-wide size bounds (S11.25, AUD-004). Per-item bounds are on the items;
        these are the two that only exist across the whole document."""
        room_count = sum(len(fl.rooms) for fl in self.floors)
        if room_count > MAX_ROOMS:
            raise ValueError(
                f"home has {room_count} rooms across {len(self.floors)} floors, over "
                f"the maximum of {MAX_ROOMS}. This app models a single residence."
            )
        total_cells = sum(
            bbox_cell_count(list(r.polygon)) for fl in self.floors for r in fl.rooms
        )
        if total_cells > MAX_TOTAL_GRID_CELLS:
            raise ValueError(
                f"home needs {total_cells:,} navigation-grid cells, over the maximum "
                f"of {MAX_TOTAL_GRID_CELLS:,}. Routing cost is proportional to this "
                "number, so a larger home would take minutes to route. Split it into "
                "separate homes, or simplify long thin rooms."
            )
        return self

    @model_validator(mode="after")
    def _cross_references(self) -> "HomeModel":
        # Unique levels
        levels = [f.level for f in self.floors]
        if len(set(levels)) != len(levels):
            raise ValueError(f"floor levels must be unique, got {sorted(levels)}")

        # Global id uniqueness across every entity kind
        seen: dict[str, str] = {}
        def claim(entity_id: str, kind: str) -> None:
            if entity_id in seen:
                raise ValueError(
                    f"duplicate id '{entity_id}' ({kind} vs {seen[entity_id]}); "
                    "ids must be unique across the whole home"
                )
            seen[entity_id] = kind

        floor_by_id: dict[str, Floor] = {}
        rooms_by_floor: dict[str, set[str]] = {}
        all_room_ids: set[str] = set()
        for fl in self.floors:
            claim(fl.id, "floor")
            floor_by_id[fl.id] = fl
            rooms_by_floor[fl.id] = set()
            for r in fl.rooms:
                claim(r.id, "room")
                rooms_by_floor[fl.id].add(r.id)
                all_room_ids.add(r.id)
            for op in fl.openings:
                claim(op.id, "opening")
            for obj in fl.objects:
                claim(obj.id, "object")
            for sp in fl.safety_points:
                claim(sp.id, "safety_point")

        for st in self.stairs:
            claim(st.id, "stairs")
            for label, end in (("from", st.from_), ("to", st.to)):
                if end.floor_id not in floor_by_id:
                    raise ValueError(
                        f"stairs '{st.id}' {label}: floor '{end.floor_id}' does not exist"
                    )
                if end.room_id not in rooms_by_floor[end.floor_id]:
                    raise ValueError(
                        f"stairs '{st.id}' {label}: room '{end.room_id}' does not "
                        f"exist on floor '{end.floor_id}'"
                    )

        for p in self.profiles:
            claim(p.id, "profile")
            if p.bedroom_room_id not in all_room_ids:
                raise ValueError(
                    f"profile '{p.id}': bedroom_room_id '{p.bedroom_room_id}' does "
                    "not reference an existing room"
                )
        return self
