"""Pydantic models for the HomeModel contract (schema/homemodel.schema.json v1.1).

These models are the executable half of the contract: JSON Schema checks shape,
these validators check the structural invariants JSON Schema cannot express —
polygon geometry (CCW, non-self-intersecting), cross-references (openings →
rooms/edges, stairs → floors/rooms, profiles → rooms), global id uniqueness,
and the scan-items-carry-confidence rule. Both must pass for a document to be
considered valid.
"""

from __future__ import annotations

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
        _validate_polygon(list(self.polygon), f"room '{self.id}'")
        return self


class Opening(SourcedModel):
    id: str
    kind: OpeningKind
    room_ids: list[str] = Field(min_length=2, max_length=2)
    wall_segment: WallSegmentRef
    width_m: float = Field(gt=0)
    height_m: float = Field(gt=0)
    sill_height_m: float = Field(ge=0)
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
        import math
        if self.id == EXTERIOR_ID:
            raise ValueError(f"'{EXTERIOR_ID}' is a reserved id")
        if not math.isfinite(self.position[0]) or not math.isfinite(self.position[1]):
            raise ValueError(f"safety_point '{self.id}': position must be finite")
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

    @model_validator(mode="after")
    def _check(self) -> "FloorObject":
        if self.id == EXTERIOR_ID:
            raise ValueError(f"'{EXTERIOR_ID}' is a reserved id")
        w, d = self.size_m
        if w <= 0 or d <= 0:
            raise ValueError(f"object '{self.id}': size_m must be positive, got {self.size_m}")
        return self


class Floor(StrictModel):
    id: str
    level: int
    name: str = Field(min_length=1)
    height_m: float = Field(gt=0)
    rooms: list[Room] = Field(min_length=1)
    openings: list[Opening] = Field(default_factory=list)
    objects: list[FloorObject] = Field(default_factory=list)
    safety_points: list[SafetyPoint] = Field(default_factory=list)

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
        _validate_polygon(list(self.footprint), f"stairs '{self.id}' footprint")
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
    schema_version: Literal["2.0"]
    home_id: str
    name: str = Field(min_length=1)
    floors: list[Floor] = Field(min_length=1)
    stairs: list[Stairs] = Field(default_factory=list)
    profiles: list[Profile] = Field(default_factory=list)
    meta: Meta
    household: Optional[Household] = None

    @model_validator(mode="before")
    @classmethod
    def _migrate(cls, data: Any) -> Any:
        from app.schema_migrator import migrate
        return migrate(data)

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
