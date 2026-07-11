"""RoutePlan models: the routing engine's output contract (consumed by the iOS
renderer, the /routes endpoint, and the S3.2 agent)."""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class RoutingConstraints(BaseModel):
    """Profile-derived constraints applied before path search (S3.4 hook).

    Deterministic tag mapping (documented for judges):
    mobility_limited → avoid_stairs + avoid_windows; child → window egress is
    already deprioritized for everyone via the window penalty.
    """

    model_config = ConfigDict(extra="forbid")

    avoid_stairs: bool = False
    avoid_windows: bool = False
    max_sill_height_m: Optional[float] = Field(default=None, ge=0)


class Waypoint(BaseModel):
    """One point on a rendered route, in floor-local meters."""

    model_config = ConfigDict(extra="forbid")

    x: float
    y: float
    floor_id: str
    node_id: str
    kind: Literal["room", "opening", "stair", "exterior"]


class Route(BaseModel):
    model_config = ConfigDict(extra="forbid")

    waypoints: list[Waypoint]
    length_m: float = Field(ge=0)
    uses_stairs: bool
    uses_window: bool
    exit_id: str


class RouteFinding(BaseModel):
    """Structured negative result — a feature, not an error (S3.2 surfaces these)."""

    model_config = ConfigDict(extra="forbid")

    kind: Literal["no_secondary_egress", "no_viable_route"]
    room_id: str
    detail: str


class RoomRoutePlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    room_id: str
    room_name: str
    floor_id: str
    primary: Optional[Route] = None
    secondary: Optional[Route] = None
    findings: list[RouteFinding] = Field(default_factory=list)


class Bottleneck(BaseModel):
    """An opening whose removal disconnects rooms from every exit."""

    model_config = ConfigDict(extra="forbid")

    opening_id: str
    disconnected_room_ids: list[str]


class RoutePlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home_id: str
    home_name: str
    constraints: RoutingConstraints
    rooms: list[RoomRoutePlan]
    bottlenecks: list[Bottleneck] = Field(default_factory=list)
