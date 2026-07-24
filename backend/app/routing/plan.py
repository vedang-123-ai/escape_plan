"""RoutePlan models: the routing engine's output contract (consumed by the iOS
renderer, the /routes endpoint, and the S3.2 agent)."""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class RoutingConstraints(BaseModel):
    """Profile-derived constraints applied during path search (S3.4 hook).

    Hard fields remove edges from the search; penalty fields keep the edge but
    make it lose to comparable alternatives. Profiles never reach the engine
    directly — `app.routing.profiles.constraints_for_profile` maps tags to this
    model through a fixed table (docs/profile-constraint-mappings.md).
    """

    model_config = ConfigDict(extra="forbid")

    avoid_stairs: bool = False
    avoid_windows: bool = False
    max_sill_height_m: Optional[float] = Field(default=None, ge=0)
    stair_penalty_m: float = Field(default=0.0, ge=0)
    """Soft surcharge per stair traversal (0 = no preference)."""
    window_penalty_m: float = Field(default=0.0, ge=0)
    """Soft surcharge on window egress, on top of the engine's universal
    WINDOW_EXIT_PENALTY (0 = the universal penalty only)."""


class Waypoint(BaseModel):
    """One point on a rendered route, in floor-local meters."""

    model_config = ConfigDict(extra="forbid")

    x: float
    y: float
    floor_id: str
    node_id: str
    kind: Literal["room", "opening", "stair", "exterior", "path"]
    """"path" (revamp B3) = an intermediate within-room point where the leg
    curves around an object — node_id is the opening the leg approaches."""


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

    kind: Literal["no_secondary_egress", "no_viable_route", "blocked_opening"]
    room_id: str
    detail: str
    object_ids: list[str] = Field(default_factory=list)
    """Objects the obstruction analysis blamed for a `blocked_opening`, so the app
    can highlight them and the advice can say WHICH thing to move. Additive and
    defaulted — an older client simply ignores it."""


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
    profile_id: Optional[str] = None
    """The profile whose tags produced `constraints`, when routed per-profile."""
    rooms: list[RoomRoutePlan]
    bottlenecks: list[Bottleneck] = Field(default_factory=list)
