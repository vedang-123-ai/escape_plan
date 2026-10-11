"""Which object is in the way, and how far to move it (pure, deterministic, no I/O).

`nav_grid` already knows that *a* doorway is unreachable; it does not know *which*
piece of furniture did it, and "something blocks this door" is not advice anyone can
act on. This module closes that gap by attribution rather than guesswork:

- **Attribution is counterfactual, not heuristic.** An object is a culprit when
  re-rasterizing the room WITHOUT it restores the leg. Nothing is inferred from
  proximity, so a sofa that merely sits near a door is never blamed for a doorway
  a wardrobe actually blocks. When no single object is sufficient, objects are
  withdrawn in id order until the leg comes back — the reported set is the group
  that jointly blocks, which is the honest answer for a pinch point.
- **Two severities from one mechanism.** The same reachability probe run at two
  clearances separates "you cannot get through" (fails at the code clearance the
  graph uses) from "you can, but it is a squeeze" (passes at code clearance,
  fails at code + COMFORT_MARGIN_M). No second code path, no second definition
  of blocked.
- **The move distance is measured, not invented.** `passable_width_m` comes from
  a bisection on the clearance the leg actually tolerates with the object still
  in place; the deficit against the corpus door width is how far it has to go.
  A number the engine measured is defensible to a judge; a number a model
  guessed is not.

Clearance ↔ width: `build_room_grid` erodes by a half-width, so a passage whose
narrowest point admits clearance c is about 2·c wide. Every width reported here
is 2·clearance, and the required width arrives from the corpus thresholds
(metric authoritative) — never hardcoded.

The AI layer consumes this through the agent's `check_obstructions` tool and
phrases the recommendation with a corpus citation ("keep exits clear" —
usfa-escape-plans / redcross-escape-plan). It never decides *what* is blocked:
this module does, deterministically, exactly as the routing engine owns routes.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Literal

from app.models import EXTERIOR_ID, Floor, FloorObject, HomeModel, Point, Polygon, Room, OpeningKind, Source
from app.routing.egress import EgressThresholds, check_egress
from app.routing.graph import opening_midpoint, polygon_centroid
from app.routing.nav_grid import build_room_grid, objects_intersecting
from app.routing.pathfind import grid_path

COMFORT_MARGIN_M = 0.15
"""Extra half-width beyond the code clearance that separates a comfortable
passage from a squeeze. 0.15 m (≈6 in) per side is deliberately modest — it
flags genuine pinch points without moralizing about every armchair."""

SCAN_TOLERANCE_M = 0.05
"""Per-side position error we forgive in scanned furniture. RoomPlan places a box
within a few centimetres and a hurried scan does worse, so a shortfall this small
is noise, not a finding: a "move it 0.05 m" card about a bed that is not in the way
is how the user learns to distrust every other card."""

SILL_STEP_OVER_M = 0.10
"""How far above a window's sill furniture may reach and still be climbed over. A bed
or a sofa under a window is the way out through it, not an obstruction."""

_BISECTION_STEPS = 7
"""Bisection iterations for the tolerated clearance (≈0.005 m resolution over
the searched band — finer than the 0.1 m grid can distinguish anyway)."""

ObstructionKind = Literal["blocks_opening", "narrows_route"]


@dataclass(frozen=True)
class Obstruction:
    """One actionable "move this" finding about one object and one doorway."""

    kind: ObstructionKind
    room_id: str
    room_name: str
    floor_id: str
    opening_id: str
    opening_kind: str
    """"door" or "window" — the detail names the opening by kind, never by its id."""
    object_ids: tuple[str, ...]
    """The culprit group — objects that jointly block. Usually one."""
    object_categories: tuple[str, ...]
    passable_width_m: float
    """Measured width of the narrowest point on the way to the doorway, with the
    objects still in place. 0.0 when the approach is closed outright."""
    required_width_m: float
    """The corpus door clear-width threshold (IRC R311.2). Always the code number,
    never our comfort margin, so a citation attached to it stays truthful."""
    target_width_m: float
    """The width THIS finding is measured against, which is not always the code
    number: a `blocks_opening` is judged at `required_width_m`, a `narrows_route`
    at the comfort width (code + `COMFORT_MARGIN_M` per side). Kept separate from
    `required_width_m` so the comfort margin — our judgement, not a code threshold —
    can never be reported as though a standard mandated it."""
    suggested_move_m: float
    """How much width has to be recovered — the least the object must move to
    clear the approach, measured against `target_width_m`. Rounded up to 0.05 m;
    never below 0.05 m."""

    @property
    def detail(self) -> str:
        """Deterministic human phrasing. The AI may re-word this with a citation;
        the numbers must survive that re-wording, so they live here."""
        objects = " and ".join(
            f"the {c}" for c in self.object_categories
        ) or "an object"
        target = f"the {self.opening_kind}"
        if self.kind == "blocks_opening":
            return (
                f"{objects.capitalize()} blocks the way to {target} from "
                f"inside {self.room_name} — there is no path to it at all. "
                f"Moving it about {self.suggested_move_m:.2f} m clear of the approach "
                f"restores a {self.required_width_m:.2f} m escape path."
            )
        return (
            f"The path to {target} from inside {self.room_name} squeezes to "
            f"{self.passable_width_m:.2f} m past {objects} — still passable, but under "
            f"the {self.target_width_m:.2f} m that keeps it comfortable in the "
            f"dark ({self.required_width_m:.2f} m of code clearance plus "
            f"{COMFORT_MARGIN_M:.2f} m of margin each side). Moving it about "
            f"{self.suggested_move_m:.2f} m restores that."
        )


def code_clearance_m(thresholds: EgressThresholds) -> float:
    """The half-width `build_room_grid` erodes by — mirrors graph.build_graph so
    the two can never disagree about what "blocked" means."""
    return thresholds.door_min_width_m / 2


def _reachable(
    polygon: Polygon,
    objects: list[FloorObject],
    start: Point,
    goal: Point,
    clearance_m: float,
    goal_radius_m: float,
) -> bool:
    grid = build_room_grid(polygon, objects, clearance_m)
    return grid_path(grid, start, goal, goal_radius_m=goal_radius_m) is not None


def culprit_object_ids(
    polygon: Polygon,
    objects: list[FloorObject],
    start: Point,
    goal: Point,
    clearance_m: float,
    goal_radius_m: float,
) -> tuple[FloorObject, ...]:
    """The objects whose removal restores the leg, by counterfactual re-rasterization.

    Single objects are tried first, in id order, so the common case (one wardrobe
    in front of one door) reports exactly that one. Only when no single removal
    helps are objects withdrawn cumulatively — the returned group is then the
    smallest id-ordered prefix that frees the path.

    Empty when removing every object still leaves the doorway unreachable: the
    obstruction is the room's geometry, not its furniture, and blaming a sofa for
    a wall would be a lie.
    """
    ordered = sorted(objects, key=lambda o: o.id)

    for obj in ordered:
        remaining = [o for o in ordered if o.id != obj.id]
        if _reachable(polygon, remaining, start, goal, clearance_m, goal_radius_m):
            return (obj,)

    withdrawn: list[FloorObject] = []
    for obj in ordered:
        withdrawn.append(obj)
        remaining = [o for o in ordered if o.id not in {w.id for w in withdrawn}]
        if _reachable(polygon, remaining, start, goal, clearance_m, goal_radius_m):
            return tuple(withdrawn)
    return ()


def tolerated_clearance_m(
    polygon: Polygon,
    objects: list[FloorObject],
    start: Point,
    goal: Point,
    goal_radius_m: float,
    upper_m: float,
) -> float:
    """The largest clearance (≤ `upper_m`) at which the leg still exists, by
    bisection. 0.0 when the approach is closed even at zero clearance.

    Monotone by construction — eroding more can only remove walkable cells — so
    bisection is exact to its resolution rather than an approximation.
    """
    if not _reachable(polygon, objects, start, goal, 0.0, goal_radius_m):
        return 0.0
    if _reachable(polygon, objects, start, goal, upper_m, goal_radius_m):
        return upper_m

    low, high = 0.0, upper_m
    for _ in range(_BISECTION_STEPS):
        mid = (low + high) / 2
        if _reachable(polygon, objects, start, goal, mid, goal_radius_m):
            low = mid
        else:
            high = mid
    return low


def _suggested_move_m(passable_width_m: float, required_width_m: float) -> float:
    deficit = required_width_m - passable_width_m
    return round(max(0.05, math.ceil(deficit / 0.05) * 0.05), 2)


def _nearest_boundary_point(polygon: Polygon, p: Point) -> Point:
    """The point on `polygon`'s boundary closest to `p`.

    A shared door's midpoint is computed on its HOST room's wall. In a scan the
    neighbouring room's wall sits a wall-thickness away, so probing from that side
    aimed at a point outside the room, and furniture merely near the door tipped it
    into "blocked". Aim at this room's own wall instead.
    """
    best, best_d = p, math.inf
    n = len(polygon)
    for i in range(n):
        a, b = polygon[i], polygon[(i + 1) % n]
        ab = (b[0] - a[0], b[1] - a[1])
        denom = ab[0] ** 2 + ab[1] ** 2
        t = 0.0 if denom < 1e-12 else max(
            0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / denom)
        )
        q = (a[0] + t * ab[0], a[1] + t * ab[1])
        d = math.dist(p, q)
        if d < best_d:
            best, best_d = q, d
    return best


def goal_radius_m(opening_width_m: float) -> float:
    """How close counts as having reached a doorway. Shared with diff.py so the two
    probes can never disagree. (Widening it was tried and rejected: the path then
    "arrives" before the pinch point and real squeezes vanish.)"""
    return max(opening_width_m / 2, 0.6)


def _shrunk(obj: FloorObject, margin_m: float) -> FloorObject:
    """A scanned object with the scan tolerance taken off each side; manual objects
    were placed on purpose and are kept exactly."""
    if obj.source != Source.scan:
        return obj
    w = max(0.01, obj.size_m[0] - 2 * margin_m)
    d = max(0.01, obj.size_m[1] - 2 * margin_m)
    return obj.model_copy(update={"size_m": (w, d)})


def _room_openings(floor: Floor, room: Room) -> list:
    """Openings on this floor that this room owns, in document order."""
    return [op for op in floor.openings if room.id in op.room_ids]


def analyze_obstructions(
    home: HomeModel, thresholds: EgressThresholds
) -> list[Obstruction]:
    """Every actionable "move this object" finding in the home, deterministically
    ordered by (floor, room, opening).

    Only rooms that actually contain objects are probed, so a home with no
    furniture costs nothing. Rooms whose doorway is unreachable for geometric
    reasons produce no finding — see `culprit_object_ids`.
    """
    code_c = code_clearance_m(thresholds)
    comfort_c = code_c + COMFORT_MARGIN_M
    out: list[Obstruction] = []

    for floor in home.floors:
        # An opening's wall_segment indexes ITS HOST room's polygon, so the midpoint
        # has to be derived from that room even when we are probing the doorway from
        # the other side. Deriving it from the probing room silently yields a point
        # somewhere off that room's boundary, which lands as "reachable" and hides
        # every real blockage — the bug this map exists to prevent.
        polygons = {room.id: list(room.polygon) for room in floor.rooms}

        for room in floor.rooms:
            local = objects_intersecting(list(room.polygon), list(floor.objects))
            if not local:
                continue
            start = polygon_centroid(list(room.polygon))

            for op in _room_openings(floor, room):
                # An exit's other side is EXTERIOR — the approach still matters.
                if op.room_ids == [EXTERIOR_ID]:
                    continue

                candidates = local
                if op.kind == OpeningKind.window:
                    is_grade = floor.level <= 0
                    assessment = op.egress if op.egress is not None else check_egress(op, thresholds, grade_floor=is_grade)
                    if not assessment.viable:
                        continue
                    required_width = thresholds.window_min_width_m
                    # You climb over a bed to reach the window above it.
                    reach = op.sill_height_m + SILL_STEP_OVER_M
                    candidates = [o for o in local if o.elevation_m + o.height_m > reach]
                    if not candidates:
                        continue
                elif op.kind == OpeningKind.door:
                    required_width = thresholds.door_min_width_m
                else:
                    continue

                host_polygon = polygons.get(op.wall_segment.room_id)
                if host_polygon is None:
                    continue
                goal = opening_midpoint(
                    host_polygon,
                    op.wall_segment.edge_index,
                    op.wall_segment.t0,
                    op.wall_segment.t1,
                )
                if op.wall_segment.room_id != room.id:
                    goal = _nearest_boundary_point(list(room.polygon), goal)
                goal_radius = goal_radius_m(op.width_m)

                code_ok = _reachable(
                    list(room.polygon), candidates, start, goal, code_c, goal_radius
                )
                if code_ok and _reachable(
                    list(room.polygon), candidates, start, goal, comfort_c, goal_radius
                ):
                    continue  # comfortable — nothing to say

                probe_c = code_c if not code_ok else comfort_c
                # Scan tolerance: if the shortfall disappears once scanned furniture
                # is given its few centimetres of benefit of the doubt, it is noise.
                forgiving = [_shrunk(o, SCAN_TOLERANCE_M) for o in candidates]
                if _reachable(list(room.polygon), forgiving, start, goal, probe_c, goal_radius):
                    continue

                culprits = culprit_object_ids(
                    list(room.polygon), candidates, start, goal, probe_c, goal_radius
                )
                if not culprits:
                    continue  # geometry, not furniture

                tolerated = tolerated_clearance_m(
                    list(room.polygon), candidates, start, goal, goal_radius, comfort_c
                )
                passable_width = round(2 * tolerated, 3)
                # A blockage is judged at the code clearance; a squeeze is judged at
                # the comfort width, which is the only reason it was flagged at all.
                target_width = (
                    required_width if not code_ok else required_width + 2 * COMFORT_MARGIN_M
                )
                out.append(
                    Obstruction(
                        kind="blocks_opening" if not code_ok else "narrows_route",
                        room_id=room.id,
                        room_name=room.name,
                        floor_id=floor.id,
                        opening_id=op.id,
                        opening_kind=op.kind.value,
                        object_ids=tuple(o.id for o in culprits),
                        object_categories=tuple(
                            o.category.value if hasattr(o.category, "value")
                            else str(o.category)
                            for o in culprits
                        ),
                        passable_width_m=passable_width,
                        required_width_m=required_width,
                        target_width_m=round(target_width, 3),
                        suggested_move_m=_suggested_move_m(
                            passable_width, target_width
                        ),
                    )
                )
    return out
