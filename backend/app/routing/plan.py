"""RoutePlan models: the routing engine's output contract (consumed by the iOS
renderer, the /routes endpoint, and the S3.2 agent)."""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


from app.limits import (
    MAX_ROUTE_BOTTLENECK_DISCONNECTED_ROOMS,
    MAX_ROUTE_BOTTLENECKS,
    MAX_ROUTE_FINDING_OBJECTS,
    MAX_ROUTE_FINDINGS_PER_ROOM,
    MAX_ROUTE_ROOMS,
    MAX_ROUTE_WAYPOINTS,
)


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
    # allow_inf_nan=False (S11.52): Infinity passed `ge=0` and came back in
    # RoutePlan.constraints as null, a plan the client cannot decode.
    max_sill_height_m: Optional[float] = Field(default=None, ge=0, allow_inf_nan=False)
    stair_penalty_m: float = Field(default=0.0, ge=0, allow_inf_nan=False)
    """Soft surcharge per stair traversal (0 = no preference)."""
    window_penalty_m: float = Field(default=0.0, ge=0, allow_inf_nan=False)
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

    waypoints: list[Waypoint] = Field(max_length=MAX_ROUTE_WAYPOINTS)
    length_m: float = Field(ge=0)
    uses_stairs: bool
    uses_window: bool
    exit_id: str


class RouteFinding(BaseModel):
    """Structured negative result — a feature, not an error (S3.2 surfaces these)."""

    model_config = ConfigDict(extra="forbid")

    kind: Literal[
        "no_secondary_egress",
        "no_viable_route",
        "no_viable_safe_room",
        "no_cover_in_room",
        "blocked_opening",
        "narrows_route",
    ]
    """`blocked_opening` = no path to the doorway at all; `narrows_route` = there is
    a path but it squeezes below the clear width a door needs in the dark. The two
    are disjoint by construction — `narrows_route` only fires where the code-clearance
    path succeeded, which is exactly what keeps the opening out of `blocked_openings`."""
    room_id: str
    detail: str
    object_ids: list[str] = Field(
        default_factory=list, max_length=MAX_ROUTE_FINDING_OBJECTS
    )
    """Objects the obstruction analysis blamed for a `blocked_opening` or a
    `narrows_route`, so the app can highlight them and the advice can say WHICH
    thing to move. Additive and defaulted — an older client simply ignores it."""
    citation: Optional[str] = None


class RoomRoutePlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    room_id: str
    room_name: str
    floor_id: str
    primary: Optional[Route] = None
    secondary: Optional[Route] = None
    cover_object_id: Optional[str] = None
    findings: list[RouteFinding] = Field(
        default_factory=list, max_length=MAX_ROUTE_FINDINGS_PER_ROOM
    )


class Bottleneck(BaseModel):
    """An opening whose removal disconnects rooms from every exit."""

    model_config = ConfigDict(extra="forbid")

    opening_id: str
    disconnected_room_ids: list[str] = Field(
        max_length=MAX_ROUTE_BOTTLENECK_DISCONNECTED_ROOMS
    )


class RoutePlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    home_id: str
    home_name: str
    peril: Literal["fire", "tornado", "earthquake"] = "fire"
    constraints: RoutingConstraints
    profile_id: Optional[str] = None
    """The profile whose tags produced `constraints`, when routed per-profile."""
    rooms: list[RoomRoutePlan] = Field(max_length=MAX_ROUTE_ROOMS)
    bottlenecks: list[Bottleneck] = Field(
        default_factory=list, max_length=MAX_ROUTE_BOTTLENECKS
    )
