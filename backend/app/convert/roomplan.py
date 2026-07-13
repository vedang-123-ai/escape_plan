"""Lenient pydantic models for the assumed RoomPlan JSON export format.

See README.md in this package for the full assumed-format contract. These models
deliberately use ``extra="ignore"`` (unlike the strict HomeModel contract): real
CapturedRoom exports carry many fields we don't consume (objects, floors, curve,
polygonCorners, ...), and the parser must not break when Apple adds more.
"""

from __future__ import annotations

from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator

PlanPoint = tuple[float, float]

CONFIDENCE_VALUES: dict[str, float] = {"high": 0.9, "medium": 0.6, "low": 0.3}


class RPConfidence(str, Enum):
    high = "high"
    medium = "medium"
    low = "low"

    @property
    def value_float(self) -> float:
        return CONFIDENCE_VALUES[self.value]


class LenientModel(BaseModel):
    model_config = ConfigDict(extra="ignore", populate_by_name=True)


def _unwrap_enum_object(v: Any) -> Any:
    """Swift's JSONEncoder writes case-less enums as {"high": {}}; unwrap to "high"."""
    if isinstance(v, dict) and len(v) == 1:
        return next(iter(v))
    return v


class RPSurface(LenientModel):
    """One wall/door/window/opening surface from a CapturedRoom."""

    identifier: str
    transform: list[float] = Field(min_length=16, max_length=16)
    dimensions: tuple[float, float, float]
    confidence: RPConfidence = RPConfidence.medium
    category: Optional[str] = None
    parent_identifier: Optional[str] = Field(default=None, alias="parentIdentifier")
    story: Optional[int] = None

    @field_validator("transform", mode="before")
    @classmethod
    def _flatten_transform(cls, v: Any) -> Any:
        # Accept nested [[4],[4],[4],[4]] as well as the flat 16-float form.
        if isinstance(v, list) and len(v) == 4 and all(isinstance(c, list) for c in v):
            return [x for col in v for x in col]
        return v

    @field_validator("dimensions", mode="before")
    @classmethod
    def _pad_dimensions(cls, v: Any) -> Any:
        if isinstance(v, list) and len(v) == 2:
            return [*v, 0.0]
        return v

    @field_validator("confidence", "category", mode="before")
    @classmethod
    def _unwrap(cls, v: Any) -> Any:
        return _unwrap_enum_object(v)

    # ---- geometry accessors (column-major simd_float4x4) ----

    @property
    def plan_center(self) -> PlanPoint:
        return (self.transform[12], self.transform[14])

    @property
    def center_y(self) -> float:
        return self.transform[13]

    @property
    def plan_direction(self) -> PlanPoint:
        """Local x-axis (along-surface direction) projected to the floor plan; unit."""
        dx, dz = self.transform[0], self.transform[2]
        norm = (dx * dx + dz * dz) ** 0.5
        if norm < 1e-9:
            return (1.0, 0.0)
        return (dx / norm, dz / norm)

    @property
    def plan_segment(self) -> tuple[PlanPoint, PlanPoint]:
        (cx, cy), (dx, dy) = self.plan_center, self.plan_direction
        h = self.dimensions[0] / 2.0
        return ((cx - dx * h, cy - dy * h), (cx + dx * h, cy + dy * h))

    @property
    def width(self) -> float:
        return self.dimensions[0]

    @property
    def height(self) -> float:
        return self.dimensions[1]

    @property
    def bottom_y(self) -> float:
        return self.center_y - self.height / 2.0


class RPSection(LenientModel):
    label: str
    center: Optional[tuple[float, float, float]] = None

    @field_validator("label", mode="before")
    @classmethod
    def _unwrap(cls, v: Any) -> Any:
        return _unwrap_enum_object(v)


class RPRoom(LenientModel):
    """One CapturedRoom (one scanned room)."""

    identifier: Optional[str] = None
    walls: list[RPSurface] = Field(default_factory=list)
    doors: list[RPSurface] = Field(default_factory=list)
    windows: list[RPSurface] = Field(default_factory=list)
    openings: list[RPSurface] = Field(default_factory=list)
    sections: list[RPSection] = Field(default_factory=list)


class RPStructure(LenientModel):
    """A CapturedStructure (merged multi-room scan)."""

    rooms: list[RPRoom] = Field(min_length=1)

    @classmethod
    def parse(cls, data: dict[str, Any]) -> "RPStructure":
        """Accept either a CapturedStructure or a bare single CapturedRoom."""
        if "rooms" in data:
            return cls.model_validate(data)
        return cls(rooms=[RPRoom.model_validate(data)])
