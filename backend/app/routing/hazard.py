"""Fire-origin simulation: tap a room, watch every route re-solve around it.

Pure functions, no I/O, deterministic (same HomeModel + origin → byte-identical
output). This is the headline feature and it is emphatically NOT an AI call: the
hazard spreads over the same `NavGraph` the S1.1 builder produces, and every
occupant path is a Dijkstra search on that graph, exactly like `engine.py`. The
AI layer may later *narrate* a timeline; it never produces one.

What the model actually is
--------------------------
Two coupled halves:

1. **Spread.** A shortest-time traversal of the room-adjacency graph from the
   origin room, one fixed delay per opening crossed and a separate fixed delay
   per stair flight. A room's `untenable_at_s` is the earliest arrival time.
   Hazard only moves through openings the graph already knows about, and never
   through an `exit_crossing` edge — a house fire does not escape out the front
   door and come back in a window.

2. **Egress.** For each occupant, Dijkstra to EXTERIOR under their S3.4
   routing constraints, then a re-solve that removes any room the hazard makes
   untenable before that occupant would clear it. Iterate to a fixpoint. If no
   route survives, the occupant gets the EXISTING `no_viable_route`
   `RouteFinding` and **no track** — an honest empty result rather than a
   fabricated path through fire.

Everything numeric here is an animation parameter
------------------------------------------------
None of the constants below come from `backend/corpus/`. They are not corpus
thresholds, they have no fire-science basis, and they are not survivability
predictions. Real fire growth is exponential, geometry-dependent, and dominated
by fuel load, ventilation and door position — none of which this app models.
Constant-rate spread is a deliberate simplification chosen so the animation is
legible and reproducible. That is why every timeline carries
`is_illustrative=True` and the UI is required to say so on screen.

Known simplifications, stated rather than hidden:

- Spread is constant-rate and direction-agnostic on a floor.
- Doors are treated as always open to the hazard; a closed door (which really
  does buy minutes) is not modeled.
- An opening the furniture analysis marked blocked has no `room_opening` edge,
  so hazard does not spread through it either. That is wrong in reality — a
  wardrobe stops a person, not smoke — but it follows from reusing the one
  graph rather than building a parallel topology, which is the larger win.
- Occupants start moving at t=0 with perfect knowledge of the route. No
  detection delay, no pre-movement time, no reduced visibility.

Occupants when the home has no profiles
---------------------------------------
`schema/fixtures/bungalow.json` has an empty `profiles` list, and so do most
freshly scanned homes. Rather than return an empty animation, the engine
synthesizes one adult occupant per room, id `occupant.<room_id>` and name
`<room name>`, in floor-then-room document order. This is deterministic and is
purely a demo affordance; a home WITH profiles gets exactly one track per
profile, starting from that profile's `bedroom_room_id`, and nothing is
synthesized.
"""

from __future__ import annotations

import heapq
import math
from enum import Enum
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models import EXTERIOR_ID, HomeModel, Opening, Profile, ProfileTag
from app.routing.egress import EgressThresholds
from app.routing.engine import (
    _SearchResult,
    _edge_cost,
    _openings_by_id,
    _route_from_search,
)
from app.routing.graph import Edge, EdgeKind, NavGraph, build_graph
from app.routing.plan import Route, RouteFinding, RoutingConstraints
from app.routing.profiles import constraints_for_profile

# ---------------------------------------------------------------------------
# Hazard spread constants
#
# Read the module docstring first: these are animation parameters, not corpus
# thresholds. No number in this block has a fire-science basis, none of them was
# derived from backend/corpus/, and none of them should ever be quoted to a user
# as "how long you have". They exist so the spread reads clearly on a phone.
# ---------------------------------------------------------------------------

ROOM_SPREAD_DELAY_S = 45.0
"""Modeled seconds for the hazard to cross one opening into an adjacent room.

A single constant per hop is the whole spread model — deliberately the crudest
thing that still produces a believable-looking wavefront and a stable ordering
of which rooms go first. Chosen at 45 s because it puts the far side of a
typical single-floor home 2–3 minutes out, which is long enough that a viable
escape route is visibly a *race* and short enough that the animation does not
outstay a demo.

NOT a corpus threshold and NOT a fire-science figure. Real spread through a
doorway depends on fuel, ventilation and whether the door is shut; this models
none of that.
"""

STAIR_SPREAD_DELAY_S = 30.0
"""Modeled seconds for the hazard to travel one stair flight to another floor.

The hazard DOES climb stairs in this model. That choice is the one piece of
qualitative fire behavior worth honoring — heat and smoke rise, and a stairwell
is the chimney — so a fire downstairs must be shown threatening the bedrooms
upstairs rather than politely staying put. It is set shorter than
`ROOM_SPREAD_DELAY_S` to express "faster than sideways", nothing more precise.

Two simplifications are baked in and should be read as such: the delay is
symmetric (downward spread is modeled as fast as upward, which is not true),
and it is a single constant regardless of flight geometry. Coarse animation
heuristic; NOT a corpus threshold and NOT a fire-science figure.
"""

_MAX_RESOLVE_ITERATIONS_SLACK = 2
"""Slack added to the room count when bounding the re-solve fixpoint loop.

Each iteration bans at least one more room, so the loop terminates in at most
one pass per room; the slack just makes the bound obviously safe rather than
exactly tight.
"""


# ---------------------------------------------------------------------------
# Occupant movement constants
#
# A separate block on purpose: these describe how a *figure animates*, not how
# a fire behaves. Same disclaimer applies with equal force — they are
# illustrative engineering choices, NOT safety claims, NOT corpus thresholds,
# and NOT a prediction that any particular person can evacuate in any
# particular time. Nobody's real escape is a constant-velocity walk along a
# graph geodesic.
# ---------------------------------------------------------------------------

WALK_SPEED_MPS: dict["GaitKind", float] = {}
"""Level-floor travel speed in metres per second, by gait. Populated below the
`GaitKind` definition (the dict is keyed by the enum, which must exist first).

Values are ordinary unhurried-to-brisk walking speeds picked so the five gaits
are visually distinguishable on screen and rank in the order a viewer expects.
They are round numbers chosen by hand, not measured, not sourced, and not
adjusted for smoke, panic, carrying a child, or darkness.
"""

STAIR_RUN_M = 4.0
"""Assumed along-the-flight travel distance for one storey of stairs, in metres.

The graph models a staircase as a zero-length connector with a routing *cost*
(`graph.STAIR_TRAVERSAL_COST`), which is a preference weight, not a distance —
so timing a stair crossing needs its own length. 4 m is a plausible diagonal
for a single straight domestic flight. An engineering placeholder: the schema
stores a stair footprint, not a rise/run, so the true length is not available.
"""

STAIR_SPEED_FACTOR = 0.5
"""Fraction of an occupant's level-floor speed retained on stairs.

Applied to `WALK_SPEED_MPS[gait]`, so an adult covers `STAIR_RUN_M` in about
6.7 s. Stairs are slower than corridors for everyone and much slower for some;
one shared factor is the coarsest possible way to say that. An engineering
choice, not a measurement.
"""

DOOR_CROSSING_TIME_S = 2.0
"""Fixed seconds added when the occupant steps through the final exit door.

Small on purpose — it exists so the last animation segment has non-zero
duration (the exit opening and the EXTERIOR waypoint share coordinates) and so
a door exit and a window exit are visibly different events. Engineering choice.
"""

WINDOW_EGRESS_TIME_S = 15.0
"""Fixed seconds added when the occupant leaves through a window instead.

Climbing out of a window — clearing the sill, turning, lowering yourself — is
categorically slower than walking through a door, and the timeline should show
that so a window "second way out" never looks equivalent to a door. 15 s is a
deliberately conservative round number and applies uniformly regardless of gait
or sill height. Engineering choice; NOT a corpus figure, and emphatically not a
claim about how long any real person needs.
"""


class GaitKind(str, Enum):
    """How a figure animates. Mirrors `GaitKind` in EvacuationTimeline.swift.

    Deliberately separate from `ProfileTag`: tags drive *routing* constraints
    (which the S3.4 table already handles), gait drives *locomotion*. Two people
    can route identically and still move differently on screen.
    """

    adult = "adult"
    child = "child"
    elderly = "elderly"
    wheelchair = "wheelchair"
    pet = "pet"
    unknown = "unknown"


WALK_SPEED_MPS.update(
    {
        GaitKind.adult: 1.20,
        GaitKind.child: 0.90,
        GaitKind.elderly: 0.75,
        GaitKind.wheelchair: 0.85,
        GaitKind.pet: 1.10,
        GaitKind.unknown: 1.20,  # degrade to an adult walk, never to zero
    }
)

_GAIT_BY_TAG_PRECEDENCE: tuple[tuple[ProfileTag, GaitKind], ...] = (
    (ProfileTag.mobility_limited, GaitKind.wheelchair),
    (ProfileTag.pet, GaitKind.pet),
    (ProfileTag.child, GaitKind.child),
    (ProfileTag.elderly, GaitKind.elderly),
)
"""Tag → gait, first match wins. `mobility_limited` outranks `elderly` so an
older adult who also uses a wheelchair animates as a wheelchair user rather
than as a slow walker — the same "strictest wins" spirit as
`profiles.constraints_for_profile`. An untagged profile is an adult."""


# ---------------------------------------------------------------------------
# Wire models — mirror escape_plan/Models/EvacuationTimeline.swift field-for-field
# ---------------------------------------------------------------------------


class TimedStep(BaseModel):
    """A route waypoint plus the modeled time the occupant reaches it."""

    model_config = ConfigDict(extra="forbid")

    x: float
    y: float
    floor_id: str
    t_s: float
    kind: Literal["room", "opening", "stair", "exterior", "path"]
    """Mirrors `Waypoint.kind` so the renderer can decorate a stair crossing or
    a window climb-out differently from ordinary walking."""


class OccupantTrack(BaseModel):
    """One occupant's already-solved journey out."""

    model_config = ConfigDict(extra="forbid")

    profile_id: str
    profile_name: str
    gait: GaitKind
    start_room_id: str
    exit_id: str
    steps: list[TimedStep]
    distance_m: float
    egress_time_s: float
    """Always equals `steps[-1].t_s`."""
    uses_stairs: bool
    uses_window: bool
    overtaken_by_hazard: bool
    """True when the modeled hazard makes a room on this path untenable strictly
    before the occupant clears it. Reported honestly — the engine never retimes
    the hazard to keep a track clean."""


class HazardEvent(BaseModel):
    """When the modeled hazard makes a room impassable. Origin room is 0."""

    model_config = ConfigDict(extra="forbid")

    room_id: str
    floor_id: str
    untenable_at_s: float


class EvacuationTimeline(BaseModel):
    """One illustrative evacuation, ready to animate.

    `findings` is ADDITIVE beyond the Swift contract as written (the Swift
    struct ignores unknown keys), and carries the existing `RouteFinding` kinds
    — chiefly `no_viable_route` for an occupant the hazard cuts off entirely.
    Such an occupant gets a finding and NO track: an honest absence beats a
    fabricated path.
    """

    model_config = ConfigDict(extra="forbid")

    home_id: str
    profile_set_id: Optional[str] = None
    origin_room_id: str
    tracks: list[OccupantTrack]
    hazard: list[HazardEvent]
    duration_s: float
    is_illustrative: bool = True
    """Always True. The UI must show a disclaimer whenever a timeline is on
    screen — this is a visualization of geometry and assumed speeds, never a
    survivability prediction."""
    findings: list[RouteFinding] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Spread
# ---------------------------------------------------------------------------


def _hazard_neighbors(graph: NavGraph, room_id: str) -> list[tuple[str, float]]:
    """Rooms the hazard can reach directly from `room_id`, with the hop delay.

    Walks room → opening → room over the existing graph. `exit_crossing` edges
    are never followed, so the hazard cannot leave the building via EXTERIOR and
    re-enter somewhere else. Sorted + de-duplicated for determinism.
    """
    reached: set[tuple[str, float]] = set()
    for edge in graph.neighbors(room_id):
        if edge.kind == EdgeKind.stair:
            reached.add((edge.other(room_id), STAIR_SPREAD_DELAY_S))
        elif edge.kind == EdgeKind.room_opening:
            opening_id = edge.other(room_id)
            for onward in graph.neighbors(opening_id):
                if onward.kind != EdgeKind.room_opening:
                    continue  # exit_crossing: the hazard stops at the building line
                other_room = onward.other(opening_id)
                if other_room == room_id or other_room == EXTERIOR_ID:
                    continue
                reached.add((other_room, ROOM_SPREAD_DELAY_S))
    return sorted(reached)


def compute_hazard_spread(graph: NavGraph, origin_room_id: str) -> dict[str, float]:
    """Room id → modeled seconds from ignition until that room is untenable.

    Earliest-arrival traversal (uniform-cost, so a heap keyed by time and then
    node id). The origin room is untenable at 0. Rooms with no opening path
    from the origin are absent from the result and stay clear for the whole
    timeline.
    """
    untenable: dict[str, float] = {origin_room_id: 0.0}
    heap: list[tuple[float, str]] = [(0.0, origin_room_id)]
    while heap:
        t, room_id = heapq.heappop(heap)
        if t > untenable.get(room_id, math.inf):
            continue
        for other_room, delay in _hazard_neighbors(graph, room_id):
            arrival = t + delay
            if arrival < untenable.get(other_room, math.inf):
                untenable[other_room] = arrival
                heapq.heappush(heap, (arrival, other_room))
    return untenable


# ---------------------------------------------------------------------------
# Egress under hazard
# ---------------------------------------------------------------------------


def _dijkstra_avoiding_rooms(
    graph: NavGraph,
    source: str,
    openings: dict[str, Opening],
    constraints: RoutingConstraints,
    banned_rooms: frozenset[str] = frozenset(),
) -> _SearchResult | None:
    """`engine._dijkstra_to_exterior` with room nodes removable from the search.

    Same relaxation and the same `_edge_cost` (so profile constraints, window
    penalties and stair handling stay identical); the only addition is that a
    banned room node is never expanded into. Implemented here rather than as a
    new parameter on the engine so `engine.py` keeps its exact S1.2 signatures.
    """
    dist: dict[str, float] = {source: 0.0}
    prev: dict[str, tuple[str, Edge]] = {}
    heap: list[tuple[float, str]] = [(0.0, source)]
    done: set[str] = set()

    while heap:
        d, node = heapq.heappop(heap)
        if node in done:
            continue
        done.add(node)
        if node == EXTERIOR_ID:
            break
        for edge in graph.neighbors(node):
            neighbor = edge.other(node)
            if neighbor in banned_rooms:
                continue
            cost = _edge_cost(edge, node, graph, openings, constraints)
            if cost is None:
                continue
            nd = d + cost
            if nd < dist.get(neighbor, math.inf):
                dist[neighbor] = nd
                prev[neighbor] = (node, edge)
                heapq.heappush(heap, (nd, neighbor))

    if EXTERIOR_ID not in prev:
        return None

    path: list[str] = [EXTERIOR_ID]
    edges: list[Edge] = []
    node = EXTERIOR_ID
    while node != source:
        parent, edge = prev[node]
        path.append(parent)
        edges.append(edge)
        node = parent
    path.reverse()
    edges.reverse()
    return _SearchResult(path=path, edges=edges, cost=dist[EXTERIOR_ID])


def _time_route(route: Route, gait: GaitKind) -> tuple[list[TimedStep], float]:
    """Attach arrival times to a solved route. Returns (steps, walked metres).

    Times accumulate strictly forward, so `t_s` is monotonically non-decreasing
    by construction. Three segment kinds: a floor change is one stair flight, a
    step onto EXTERIOR is the exit crossing, everything else is level-floor
    walking at the gait's speed.
    """
    speed = WALK_SPEED_MPS[gait]
    stair_time = STAIR_RUN_M / (speed * STAIR_SPEED_FACTOR)
    exit_time = WINDOW_EGRESS_TIME_S if route.uses_window else DOOR_CROSSING_TIME_S

    steps: list[TimedStep] = []
    elapsed = 0.0
    distance = 0.0
    previous = None
    for waypoint in route.waypoints:
        if previous is not None:
            if waypoint.kind == "exterior":
                elapsed += exit_time
            elif waypoint.floor_id != previous.floor_id:
                elapsed += stair_time
                distance += STAIR_RUN_M
            else:
                leg = math.hypot(
                    waypoint.x - previous.x, waypoint.y - previous.y
                )
                distance += leg
                elapsed += leg / speed
        steps.append(
            TimedStep(
                x=round(waypoint.x, 4),
                y=round(waypoint.y, 4),
                floor_id=waypoint.floor_id,
                t_s=round(elapsed, 2),
                kind=waypoint.kind,
            )
        )
        previous = waypoint
    return steps, distance


def _room_clearance_times(
    route: Route, steps: list[TimedStep]
) -> list[tuple[str, float]]:
    """(room id, time the occupant finishes crossing that room) along the path.

    A room is "cleared" when the occupant reaches the next opening, stair or the
    exterior — i.e. when they are through the doorway rather than still inside.
    """
    cleared: list[tuple[str, float]] = []
    for i, waypoint in enumerate(route.waypoints):
        if waypoint.kind != "room":
            continue
        leave_at = steps[-1].t_s
        for j in range(i + 1, len(route.waypoints)):
            if route.waypoints[j].kind in ("opening", "stair", "exterior"):
                leave_at = steps[j].t_s
                break
        cleared.append((waypoint.node_id, leave_at))
    return cleared


def _solve_track(
    graph: NavGraph,
    home: HomeModel,
    openings: dict[str, Opening],
    untenable: dict[str, float],
    *,
    profile_id: str,
    profile_name: str,
    gait: GaitKind,
    start_room_id: str,
    constraints: RoutingConstraints,
) -> OccupantTrack | None:
    """One occupant's timed escape, or None when the hazard cuts them off.

    Fixpoint loop: solve, time the result, ban every room the hazard makes
    untenable before the occupant would clear it, re-solve. The occupant's own
    start room is never banned — you have to leave the room you are in, even
    when it is the room that is on fire — so an occupant caught at the origin
    still gets a track, flagged `overtaken_by_hazard`.
    """
    room_count = sum(len(floor.rooms) for floor in home.floors)
    banned: frozenset[str] = frozenset()

    for _ in range(room_count + _MAX_RESOLVE_ITERATIONS_SLACK):
        result = _dijkstra_avoiding_rooms(
            graph, start_room_id, openings, constraints, banned
        )
        if result is None:
            return None
        route = _route_from_search(result, graph, home)
        steps, distance = _time_route(route, gait)
        caught = {
            room_id
            for room_id, leave_at in _room_clearance_times(route, steps)
            if room_id != start_room_id
            and untenable.get(room_id, math.inf) < leave_at
        }
        if caught:
            banned = banned | frozenset(caught)
            continue

        overtaken = any(
            untenable.get(room_id, math.inf) < leave_at
            for room_id, leave_at in _room_clearance_times(route, steps)
        )
        return OccupantTrack(
            profile_id=profile_id,
            profile_name=profile_name,
            gait=gait,
            start_room_id=start_room_id,
            exit_id=route.exit_id,
            steps=steps,
            distance_m=round(distance, 3),
            egress_time_s=steps[-1].t_s,
            uses_stairs=route.uses_stairs,
            uses_window=route.uses_window,
            overtaken_by_hazard=overtaken,
        )
    return None  # pragma: no cover - the ban set grows every iteration


def gait_for_profile(profile: Profile) -> GaitKind:
    """Deterministic tag → gait mapping (first match in the precedence table)."""
    for tag, gait in _GAIT_BY_TAG_PRECEDENCE:
        if tag in profile.tags:
            return gait
    return GaitKind.adult


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def compute_evacuation_timeline(
    home: HomeModel,
    thresholds: EgressThresholds,
    origin_room_id: str,
    *,
    profile_set_id: str | None = None,
) -> EvacuationTimeline:
    """Ignite `origin_room_id` and re-solve every occupant's escape around it.

    Deterministic and pure. Occupants are the home's profiles when it has any,
    otherwise one synthesized adult per room (see the module docstring). An
    occupant with no route left produces a `no_viable_route` finding and no
    track.
    """
    room_ids = {room.id for floor in home.floors for room in floor.rooms}
    if origin_room_id not in room_ids:
        raise ValueError(f"no room '{origin_room_id}' in home '{home.home_id}'")

    graph = build_graph(home, thresholds)
    openings = _openings_by_id(home)
    untenable = compute_hazard_spread(graph, origin_room_id)

    room_names = {
        room.id: room.name for floor in home.floors for room in floor.rooms
    }

    occupants: list[tuple[str, str, GaitKind, str, RoutingConstraints]] = []
    if home.profiles:
        for profile in home.profiles:
            occupants.append(
                (
                    profile.id,
                    profile.name,
                    gait_for_profile(profile),
                    profile.bedroom_room_id,
                    constraints_for_profile(profile, thresholds),
                )
            )
    else:
        for floor in home.floors:
            for room in floor.rooms:
                occupants.append(
                    (
                        f"occupant.{room.id}",
                        room.name,
                        GaitKind.adult,
                        room.id,
                        RoutingConstraints(),
                    )
                )

    tracks: list[OccupantTrack] = []
    findings: list[RouteFinding] = []
    for profile_id, profile_name, gait, start_room_id, constraints in occupants:
        track = _solve_track(
            graph,
            home,
            openings,
            untenable,
            profile_id=profile_id,
            profile_name=profile_name,
            gait=gait,
            start_room_id=start_room_id,
            constraints=constraints,
        )
        if track is None:
            room_name = room_names[start_room_id]
            # A synthesized occupant IS the room, so naming both reads as a
            # stutter ("Bathroom has no route from 'Bathroom'").
            who = (
                f"'{room_name}'"
                if profile_name == room_name
                else f"{profile_name}, starting in '{room_name}',"
            )
            findings.append(
                RouteFinding(
                    kind="no_viable_route",
                    room_id=start_room_id,
                    detail=(
                        f"{who} has no escape route that avoids the rooms this "
                        f"fire reaches first."
                    ),
                )
            )
            continue
        tracks.append(track)

    hazard = [
        HazardEvent(
            room_id=room_id,
            floor_id=graph.nodes[room_id].floor_id or "",
            untenable_at_s=round(seconds, 2),
        )
        for room_id, seconds in sorted(untenable.items(), key=lambda kv: (kv[1], kv[0]))
    ]

    duration = max(
        [track.egress_time_s for track in tracks]
        + [event.untenable_at_s for event in hazard]
        + [0.0]
    )

    return EvacuationTimeline(
        home_id=home.home_id,
        profile_set_id=profile_set_id,
        origin_room_id=origin_room_id,
        tracks=tracks,
        hazard=hazard,
        duration_s=round(duration, 2),
        is_illustrative=True,
        findings=findings,
    )
