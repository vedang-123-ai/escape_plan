"""Revamp B3 tests: within-room grid pathfinding + obstacle-aware routing.

Covers, on the planted `bungalow-blocked` fixture and synthetic grids:
- rasterization + clearance erosion (nav_grid)
- deterministic A* + smoothing (pathfind): two runs are byte-identical, and
  unobstructed rooms collapse to a straight leg
- graph integration: routes visibly curve around objects, a fully blocked
  doorway drops the edge, the engine re-plans through another opening, and a
  structured `blocked_opening` finding is emitted
- rooms without objects keep the exact pre-B3 straight-line legs (no golden
  churn for the existing fixtures)
"""

from __future__ import annotations

import json
import math

import pytest

from app.models import FloorObject, HomeModel, ObjectCategory, Source
from app.routing.egress import EgressThresholds
from app.routing.engine import compute_route_plan
from app.routing.graph import build_graph
from app.routing.nav_grid import build_room_grid, nearest_walkable, object_contains
from app.routing.pathfind import grid_path, path_length
from tests.conftest import FIXTURES_DIR, REPO_ROOT, load_fixture

THRESHOLDS_PATH = REPO_ROOT / "backend" / "corpus" / "egress_thresholds.json"

SQUARE = [(0.0, 0.0), (5.0, 0.0), (5.0, 4.0), (0.0, 4.0)]


@pytest.fixture(scope="module")
def thresholds() -> EgressThresholds:
    return EgressThresholds.from_corpus(json.loads(THRESHOLDS_PATH.read_text()))


def _sofa(center, size=(2.0, 0.9), rotation=0.0) -> FloorObject:
    return FloorObject(
        id=f"o_{center[0]}_{center[1]}",
        category=ObjectCategory.sofa,
        center=center,
        size_m=size,
        height_m=0.8,
        rotation_deg=rotation,
        source=Source.manual,
    )


# ---------------------------------------------------------------------------
# nav_grid


def test_rotated_rect_containment_matches_editor_semantics() -> None:
    obj = _sofa((2.0, 2.0), size=(2.0, 1.0), rotation=90.0)
    # After 90° the long axis runs along y.
    assert object_contains(obj, (2.0, 2.9))
    assert not object_contains(obj, (2.9, 2.0))


def test_grid_marks_object_cells_blocked_and_erodes_clearance(thresholds) -> None:
    clearance = thresholds.door_min_width_m / 2
    grid = build_room_grid(SQUARE, [_sofa((2.5, 2.0))], clearance)
    # The sofa's center cell is blocked...
    c, r = grid.cell_for((2.5, 2.0))
    assert not grid.is_walkable(c, r)
    # ...and so is a cell just off its edge but inside the clearance band.
    c2, r2 = grid.cell_for((2.5, 2.6))
    assert not grid.is_walkable(c2, r2)
    # Open floor well away from the sofa and the walls stays walkable.
    c3, r3 = grid.cell_for((1.0, 1.0))
    assert grid.is_walkable(c3, r3)


def test_nearest_walkable_lands_boundary_points(thresholds) -> None:
    grid = build_room_grid(SQUARE, [_sofa((2.5, 2.0))], thresholds.door_min_width_m / 2)
    # An opening midpoint sits ON the room boundary; erosion clears its cell,
    # but a walkable landing cell must exist just inside.
    assert nearest_walkable(grid, (2.5, 0.0)) is not None


# ---------------------------------------------------------------------------
# pathfind


def test_unobstructed_room_collapses_to_a_straight_leg(thresholds) -> None:
    grid = build_room_grid(SQUARE, [_sofa((4.5, 3.6), size=(0.4, 0.4))],
                           thresholds.door_min_width_m / 2)
    leg = grid_path(grid, (2.5, 2.0), (2.5, 0.0))
    assert leg is not None
    # Line of sight is clear: the leg is (near-)straight — exact endpoints plus
    # at most one landing point where wall erosion pushed the goal cell inward.
    assert leg[0] == (2.5, 2.0)
    assert leg[-1] == (2.5, 0.0)
    assert len(leg) <= 3
    assert path_length(leg) == pytest.approx(2.0, rel=0.03)


def test_path_curves_around_an_object(thresholds) -> None:
    # Sofa mid-room: the gap beneath it (1.05 m minus clearances) is under the
    # egress width, so the leg must swing around the sofa's side.
    grid = build_room_grid(SQUARE, [_sofa((2.5, 1.5))], thresholds.door_min_width_m / 2)
    leg = grid_path(grid, (2.5, 3.0), (2.5, 0.0))
    assert leg is not None
    # The straight line would cross the sofa: the path must detour...
    assert len(leg) > 2
    assert path_length(leg) > 3.0
    # ...and no polyline point may sit inside the sofa.
    sofa = _sofa((2.5, 1.5))
    assert not any(object_contains(sofa, p) for p in leg)


def test_walled_off_goal_returns_none(thresholds) -> None:
    # A wall of boxes spanning the room's full width below the start.
    wall = [_sofa((x, 1.0), size=(1.0, 0.6)) for x in (0.5, 1.5, 2.5, 3.5, 4.5)]
    grid = build_room_grid(SQUARE, wall, thresholds.door_min_width_m / 2)
    assert grid_path(grid, (2.5, 2.5), (2.5, 0.0)) is None


def test_pathfinding_is_deterministic_across_runs(thresholds) -> None:
    def run() -> list:
        grid = build_room_grid(SQUARE, [_sofa((2.5, 1.0)), _sofa((1.0, 2.5))],
                               thresholds.door_min_width_m / 2)
        return grid_path(grid, (2.5, 3.5), (2.5, 0.0))

    a, b = run(), run()
    assert a == b  # exact float equality — same input must give identical output


# ---------------------------------------------------------------------------
# graph + engine integration (planted fixture)


def _blocked_home() -> HomeModel:
    return HomeModel.model_validate(load_fixture("bungalow-blocked.json"))


def test_blocked_doorway_drops_the_edge_and_is_recorded(thresholds) -> None:
    graph = build_graph(_blocked_home(), thresholds)
    # The wardrobe fully blocks d_living_bedroom from the bedroom side.
    assert graph.blocked_openings.get("r_bedroom") == ["d_living_bedroom"]
    bedroom_edges = {e.other("r_bedroom") for e in graph.neighbors("r_bedroom")}
    assert "d_living_bedroom" not in bedroom_edges
    assert "w_bedroom" in bedroom_edges  # the window leg survives


def test_bedroom_replans_through_its_window(thresholds) -> None:
    plan = compute_route_plan(_blocked_home(), thresholds)
    bedroom = next(r for r in plan.rooms if r.room_id == "r_bedroom")
    assert bedroom.primary is not None
    assert bedroom.primary.exit_id == "w_bedroom", (
        "with the doorway blocked, the engine must route out the egress window"
    )
    assert bedroom.primary.uses_window
    kinds = {f.kind for f in bedroom.findings}
    assert "blocked_opening" in kinds


def test_living_room_route_curves_around_the_sofa(thresholds) -> None:
    plan = compute_route_plan(_blocked_home(), thresholds)
    living = next(r for r in plan.rooms if r.room_id == "r_living")
    assert living.primary is not None
    # The sofa sits between the living room centroid and the front door, so the
    # leg must carry within-room "path" waypoints that clear it.
    path_points = [w for w in living.primary.waypoints if w.kind == "path"]
    assert path_points, "expected the leg to curve (path waypoints)"
    # The curve points themselves must clear the sofa. (The room-centroid
    # waypoint may legitimately sit inside it — the marker is the room's
    # center, and the first path point is where the person actually walks.)
    sofa = next(
        o for o in _blocked_home().floors[0].objects if o.category == ObjectCategory.sofa
    )
    for w in path_points:
        assert not object_contains(sofa, (w.x, w.y))


def test_route_plan_on_blocked_fixture_is_deterministic(thresholds) -> None:
    a = compute_route_plan(_blocked_home(), thresholds).model_dump_json()
    b = compute_route_plan(_blocked_home(), thresholds).model_dump_json()
    assert a == b


def test_object_free_fixtures_keep_straight_legs(thresholds) -> None:
    """No golden churn: homes without objects must produce byte-identical plans
    to the pre-B3 engine — straight legs, no path waypoints, no new findings.

    The fixture list is DERIVED rather than hardcoded. It used to name bungalow and
    twostory; S7.1 seeded twostory with object-hazard test objects, at which point a
    hardcoded list would have had to either lose a fixture silently or start asserting
    something untrue. Deriving it means the guard automatically covers every genuinely
    object-free fixture and can never quietly become a test of the wrong thing — with
    the emptiness assert below as the tripwire if the last one ever gains an object.
    """
    names = sorted(
        f.name
        for f in FIXTURES_DIR.glob("*.json")
        if not any(
            floor.get("objects") for floor in json.loads(f.read_text()).get("floors", [])
        )
    )
    assert names, "no object-free fixture is left — this guard has gone vacuous"
    for name in names:
        home = HomeModel.model_validate(load_fixture(name))
        plan = compute_route_plan(home, thresholds)
        for room in plan.rooms:
            for route in (room.primary, room.secondary):
                if route is None:
                    continue
                assert all(w.kind != "path" for w in route.waypoints)
            assert all(f.kind != "blocked_opening" for f in room.findings)


# ---------------------------------------------------------------------------
# narrows_route reaching the RoutePlan (2026-08-25). The obstruction layer had
# computed these since B3; the engine only ever looked up obstructions for
# openings already in `graph.blocked_openings`, and a narrowing is by definition
# NOT blocked — so nothing could ever surface one.


def _plan_for(fixture_name: str, thresholds):
    return compute_route_plan(
        HomeModel.model_validate(load_fixture(fixture_name)), thresholds
    )


def _findings(plan, kind: str):
    return [
        (room.room_id, f)
        for room in plan.rooms
        for f in room.findings
        if f.kind == kind
    ]


def test_a_narrowing_reaches_the_route_plan(thresholds) -> None:
    plan = _plan_for("bungalow-narrow.json", thresholds)
    narrowings = _findings(plan, "narrows_route")
    assert len(narrowings) == 1, "the planted squeeze must surface as a finding"
    room_id, finding = narrowings[0]
    assert room_id == "r_bedroom"
    assert finding.object_ids == ["o_wardrobe_narrowing"]


def test_a_narrowing_does_not_also_report_a_blockage(thresholds) -> None:
    """The two kinds are disjoint by construction. If a squeeze ever also emits
    `blocked_opening`, the user sees one problem described twice at two
    different severities."""
    plan = _plan_for("bungalow-narrow.json", thresholds)
    assert _findings(plan, "blocked_opening") == []


def test_a_narrowing_does_not_cost_the_room_its_routes(thresholds) -> None:
    """The whole point of the kind: the way out still works. A squeeze that
    removed the route would be a blockage, and mislabelled."""
    plan = _plan_for("bungalow-narrow.json", thresholds)
    bedroom = next(r for r in plan.rooms if r.room_id == "r_bedroom")
    assert bedroom.primary is not None


def test_a_blocked_home_still_reports_a_blockage_not_a_squeeze(thresholds) -> None:
    plan = _plan_for("bungalow-blocked.json", thresholds)
    assert len(_findings(plan, "blocked_opening")) == 1
    assert _findings(plan, "narrows_route") == []


def test_furniture_free_homes_gain_no_findings(thresholds) -> None:
    """Widening the analysis gate from "something is blocked" to "the home has
    objects" must not change any home that has no furniture."""
    for name in ("bungalow.json", "twostory.json"):
        plan = _plan_for(name, thresholds)
        assert _findings(plan, "narrows_route") == []
        assert _findings(plan, "blocked_opening") == []


def test_route_plan_is_deterministic_with_narrowings(thresholds) -> None:
    a = _plan_for("bungalow-narrow.json", thresholds)
    b = _plan_for("bungalow-narrow.json", thresholds)
    assert a.model_dump_json() == b.model_dump_json()


# ---------------------------------------------------------------------------
# Elevation: a wall-mounted object does not take floor away (BLOCKERS §3)
# ---------------------------------------------------------------------------
#
# The defect was latent but mechanically real: `build_room_grid` blocked any
# footprint it was handed, whatever its elevation, so a television bolted to the
# wall 1.35 m up eroded walkable floor. It never bit because `jagged.json`'s
# `o_u_tv_over_bed` sits over the bed, which is blocked anyway — the fixture hid
# it. These tests move it into open floor, which is what makes the guard real.


def _jagged_tv_room():
    """The `jagged` floor, room and mounted TV the board's measurement used."""
    home = HomeModel.model_validate(load_fixture("jagged.json"))
    for floor in home.floors:
        for obj in floor.objects:
            if obj.id == "o_u_tv_over_bed":
                room = next(r for r in floor.rooms if _room_contains(r, obj.center))
                return home, floor, room, obj
    raise AssertionError("jagged.json no longer carries o_u_tv_over_bed")


def _room_contains(room, point) -> bool:
    from app.routing.nav_grid import point_in_polygon

    return point_in_polygon(list(room.polygon), point)


def _free_cells(room, objects) -> int:
    from app.routing.nav_grid import build_room_grid

    grid = build_room_grid(room.polygon, objects, 0.0)
    return sum(1 for cell in grid.walkable if cell)


def _open_point(room):
    """A point in genuinely open floor, well away from the walls.

    NOT the polygon centroid: `jagged.json`'s rooms are non-convex (that is what
    it is for), so the centroid can fall outside the room entirely — an object
    placed there blocks nothing and the test passes for the wrong reason, which
    is exactly what happened on the first run of these tests.
    """
    from app.routing.nav_grid import CELL_M, build_room_grid

    grid = build_room_grid(room.polygon, [], 0.0)
    free = [
        (grid.min_x + (i % grid.cols + 0.5) * CELL_M,
         grid.min_y + (i // grid.cols + 0.5) * CELL_M)
        for i, walkable in enumerate(grid.walkable)
        if walkable
    ]
    assert free, "the room has no open floor at all"
    mean_x = sum(p[0] for p in free) / len(free)
    mean_y = sum(p[1] for p in free) / len(free)
    # The open cell nearest the average of the open cells — inside the room by
    # construction, whatever shape it is.
    return min(free, key=lambda p: (p[0] - mean_x) ** 2 + (p[1] - mean_y) ** 2)


def test_a_wall_mounted_object_in_open_floor_takes_no_floor_away():
    """The case the fixture hides. A mounted TV moved off the bed and into the
    middle of the room must not cost a single walkable cell."""
    _, _, room, tv = _jagged_tv_room()
    assert tv.mounted is True and tv.elevation_m > 0

    empty = _free_cells(room, [])
    mid_room_tv = tv.model_copy(update={"center": _open_point(room)})
    assert _free_cells(room, [mid_room_tv]) == empty


def test_the_same_object_unmounted_does_take_floor_away():
    """The other half, so the test above cannot pass for the wrong reason (an
    object too small to cover a cell, or a centroid outside the polygon). An
    identical object standing ON the floor must still block it — this is the
    measured 5476 → 5296 erosion, and it is correct behaviour for a floor-
    standing television."""
    _, _, room, tv = _jagged_tv_room()

    empty = _free_cells(room, [])
    standing_tv = tv.model_copy(
        update={"center": _open_point(room), "mounted": False, "elevation_m": 0.0}
    )
    blocked = _free_cells(room, [standing_tv])

    assert blocked < empty, "a floor-standing object must still erode walkable floor"


def test_mounting_an_object_is_what_decides_it_not_its_elevation():
    """`elevation_m` is deliberately not consulted: a box raised on a table is
    still something you cannot walk through. Only `mounted` frees the floor."""
    _, _, room, tv = _jagged_tv_room()
    centre = _open_point(room)

    raised_but_standing = tv.model_copy(
        update={"center": centre, "mounted": False, "elevation_m": 1.35}
    )
    assert _free_cells(room, [raised_but_standing]) < _free_cells(room, [])


def test_routing_still_treats_floor_standing_objects_as_obstacles():
    """The guard against over-applying the fix: every object in every bundled
    fixture stands on the floor except the one TV, so obstruction must be
    unchanged for all of them."""
    from app.routing.nav_grid import obstructs_floor

    for name in ("bungalow.json", "apartment.json", "twostory.json", "jagged.json"):
        home = HomeModel.model_validate(load_fixture(name))
        for floor in home.floors:
            for obj in floor.objects:
                assert obstructs_floor(obj) is (not obj.mounted), f"{name}:{obj.id}"
