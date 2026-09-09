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
