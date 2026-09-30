"""S11.25 (AUD-004): residential size bounds.

Every bound is tested twice — a home right AT the bound validates, a home one
step OVER it is rejected and the message names the bound that was exceeded.

The two bounds that matter are the grid-cell ones. `build_room_grid` rasterizes
a room's bounding box, not its area, so an area cap alone lets a long thin room
cost as much as the whole box it spans. `test_area_cap_alone_would_not_have_been_enough`
pins the measured case the audit's proposed bound would have missed.

Cost is asserted in CELLS, never seconds, so the suite cannot go flaky on a
loaded machine.
"""

from __future__ import annotations

import copy
import math

import pytest
from pydantic import ValidationError

from app.models import (
    MAX_COORD_M,
    MAX_FLOOR_HEIGHT_M,
    MAX_FLOORS,
    MAX_OBJECT_HEIGHT_M,
    MAX_OBJECT_SIZE_M,
    MAX_OBJECTS_PER_FLOOR,
    MAX_OBJECTS_PER_ROOM,
    MAX_OBJECTS_TOTAL,
    MAX_OPENING_DIM_M,
    MAX_OPENINGS_PER_FLOOR,
    MAX_POLYGON_VERTICES,
    MAX_PROFILES,
    MAX_ROOM_AREA_M2,
    MAX_ROOM_GRID_CELLS,
    MAX_ROOM_SPAN_M,
    MAX_ROOMS,
    MAX_SAFETY_POINTS_PER_FLOOR,
    MAX_STAIRS,
    MAX_TOTAL_GRID_CELLS,
    HomeModel,
    bbox_cell_count,
)


# --- the mirror of nav_grid stays honest ----------------------------------

def test_models_cell_size_matches_the_routing_engine() -> None:
    """models.py duplicates CELL_M to stay import-free of the routing package."""
    from app.models import _CELL_M
    from app.routing.nav_grid import CELL_M

    assert _CELL_M == CELL_M


@pytest.mark.parametrize("position", [0, 1, 2])
def test_bbox_cell_count_is_total_for_a_non_finite_polygon(position: int) -> None:
    """It saturates instead of raising, and for a NaN in ANY vertex.

    `max()`/`min()` silently skip a non-leading NaN (every comparison is False), so a
    polygon containing one can produce a finite-looking extent. `bbox_cell_count` is
    public and documented as pure, so the next caller must not be able to make it raise.
    Swift's `HomeSizeBounds.gridCellCount` returns `Int.max` for the same inputs.
    """
    import sys

    polygon = [(0.0, 0.0), (4.0, 0.0), (4.0, 3.0)]
    polygon[position] = (math.nan, polygon[position][1])
    assert bbox_cell_count(polygon) == sys.maxsize


def test_bbox_cell_count_matches_build_room_grid() -> None:
    """A known-answer check that the validator counts what the router allocates."""
    from app.routing.nav_grid import build_room_grid

    polygon = [(0.0, 0.0), (4.3, 0.0), (4.3, 2.7), (0.0, 2.7)]
    grid = build_room_grid(polygon, [], 0.0)
    assert bbox_cell_count(polygon) == grid.cols * grid.rows == 43 * 27


# --- helpers ---------------------------------------------------------------

def _rect(x0: float, y0: float, w: float, d: float) -> list[list[float]]:
    """A CCW axis-aligned rectangle."""
    return [[x0, y0], [x0 + w, y0], [x0 + w, y0 + d], [x0, y0 + d]]


def _single_room_home(polygon: list[list[float]]) -> dict:
    """The smallest valid home: one floor, one room, one exterior door."""
    return {
        "schema_version": "2.1",
        "home_id": "h_bounds",
        "name": "Bounds",
        "meta": {"created": "2026-09-30T00:00:00Z", "modified": "2026-09-30T00:00:00Z"},
        "floors": [
            {
                "id": "fl_1",
                "level": 0,
                "name": "Ground",
                "height_m": 2.7,
                "rooms": [
                    {
                        "id": "r_1",
                        "name": "Room",
                        "type": "living",
                        "polygon": polygon,
                        "source": "manual",
                    }
                ],
                "openings": [
                    {
                        "id": "op_1",
                        "kind": "door",
                        "room_ids": ["r_1", "EXTERIOR"],
                        "wall_segment": {
                            "room_id": "r_1",
                            "edge_index": 0,
                            "t0": 0.1,
                            "t1": 0.3,
                        },
                        "width_m": 0.9,
                        "height_m": 2.0,
                        "sill_height_m": 0.0,
                        "source": "manual",
                    }
                ],
            }
        ],
    }


def _mutate(base: dict, fn) -> dict:
    d = copy.deepcopy(base)
    fn(d)
    return d


@pytest.fixture
def home() -> dict:
    return _single_room_home(_rect(0, 0, 5, 4))


# --- the bound the audit's proposal would have missed ---------------------

def test_area_cap_alone_would_not_have_been_enough() -> None:
    """A 75 m² room — far under any sane area cap — spanning 150 m × 150 m.

    Measured 2026-09-30: 2,250,000 grid cells, ~300x more than its area
    justifies, ~58 s to rasterize once. This is why S11.25 bounds cells.
    """
    sliver = [[0.0, 0.0], [150.0, 149.0], [150.0, 150.0], [1.0, 1.0]]
    assert bbox_cell_count([tuple(p) for p in sliver]) == 2_250_000
    with pytest.raises(ValidationError) as err:
        HomeModel.model_validate(_single_room_home(sliver))
    # Rejected on span first (the cheapest, clearest reason for a user).
    assert "span" in str(err.value)


# --- per-room grid cells --------------------------------------------------

def test_room_grid_cells_at_and_over_the_bound() -> None:
    """The per-room cell cap only bites on a SLIVER, and that is the point.

    For a rectangle the 500 m2 area cap always binds first (500 m2 is 50,000
    cells), so this bound exists solely for a room whose area is modest and whose
    bounding box is not. Both polygons below are 30 m2 diagonal slivers with a
    legal span; only the box they span differs.
    """
    # 60 m x 15 m box = 600 x 150 = 90,000 cells exactly, area 30 m2.
    at = [[0.0, 0.0], [60.0, 14.5], [60.0, 15.0], [0.0, 0.5]]
    assert bbox_cell_count([tuple(p) for p in at]) == MAX_ROOM_GRID_CELLS
    HomeModel.model_validate(_single_room_home(at))

    # 60 m x 16 m box = 600 x 160 = 96,000 cells. Same 30 m2 area, same legal span.
    over = [[0.0, 0.0], [60.0, 15.5], [60.0, 16.0], [0.0, 0.5]]
    assert bbox_cell_count([tuple(p) for p in over]) > MAX_ROOM_GRID_CELLS
    from app.models import signed_area

    assert abs(signed_area([tuple(p) for p in over])) < MAX_ROOM_AREA_M2
    assert max(60.0, 16.0) <= MAX_ROOM_SPAN_M
    with pytest.raises(ValidationError, match="navigation-grid cells"):
        HomeModel.model_validate(_single_room_home(over))


def test_room_span_at_and_over_the_bound() -> None:
    HomeModel.model_validate(_single_room_home(_rect(0, 0, MAX_ROOM_SPAN_M, 1.0)))
    with pytest.raises(ValidationError, match="maximum span"):
        HomeModel.model_validate(
            _single_room_home(_rect(0, 0, MAX_ROOM_SPAN_M + 0.1, 1.0))
        )


def test_room_area_at_and_over_the_bound() -> None:
    # 50 m x 10 m = 500 m2 exactly, and 50,000 cells (inside both cell bounds).
    HomeModel.model_validate(_single_room_home(_rect(0, 0, 50.0, 10.0)))
    # 50 m x 10.5 m = 525 m2. Span and cell count both still legal.
    over = _rect(0, 0, 50.0, 10.5)
    assert bbox_cell_count([tuple(p) for p in over]) <= MAX_ROOM_GRID_CELLS
    with pytest.raises(ValidationError, match="exceeds the maximum of 500"):
        HomeModel.model_validate(_single_room_home(over))


# --- whole-home grid cells: the binding bound ----------------------------

def _home_with_n_rooms(n: int, w: float, d: float) -> dict:
    """n rooms of w x d laid out in a row, each with its own exterior door."""
    home = _single_room_home(_rect(0, 0, w, d))
    floor = home["floors"][0]
    floor["rooms"] = []
    floor["openings"] = []
    for i in range(n):
        # Stagger in both axes so nothing exceeds MAX_COORD_M on a long row.
        col, row = i % 12, i // 12
        floor["rooms"].append(
            {
                "id": f"r_{i}",
                "name": f"Room {i}",
                "type": "bedroom",
                "polygon": _rect(col * (w + 1), row * (d + 1), w, d),
                "source": "manual",
            }
        )
        floor["openings"].append(
            {
                "id": f"op_{i}",
                "kind": "door",
                "room_ids": [f"r_{i}", "EXTERIOR"],
                "wall_segment": {
                    "room_id": f"r_{i}",
                    "edge_index": 0,
                    "t0": 0.1,
                    "t1": 0.3,
                },
                "width_m": 0.9,
                "height_m": 2.0,
                "sill_height_m": 0.0,
                "source": "manual",
            }
        )
    return home


def test_total_grid_cells_at_and_over_the_bound() -> None:
    """Each room is legal on its own; the home is not."""
    # 100 rooms of 5 m x 5 m = 2,500 cells each = 250,000 exactly.
    at = _home_with_n_rooms(100, 5.0, 5.0)
    total = sum(
        bbox_cell_count([tuple(p) for p in r["polygon"]])
        for r in at["floors"][0]["rooms"]
    )
    assert total == MAX_TOTAL_GRID_CELLS
    HomeModel.model_validate(at)

    over = _home_with_n_rooms(101, 5.0, 5.0)
    for room in over["floors"][0]["rooms"]:
        assert (
            bbox_cell_count([tuple(p) for p in room["polygon"]]) <= MAX_ROOM_GRID_CELLS
        )
    with pytest.raises(ValidationError, match="over the maximum of 250,000"):
        HomeModel.model_validate(over)


# --- objects: the OTHER cost driver, and the worse one ---------------------

def _object(oid: str, cx: float, cy: float) -> dict:
    return {
        "id": oid, "category": "bookcase", "center": [cx, cy],
        "size_m": [0.8, 0.35], "height_m": 1.9, "rotation_deg": 12.5,
        "source": "manual",
    }


def test_objects_per_room_at_and_over_the_bound(home: dict) -> None:
    """The bound the first version of these bounds missed.

    When a route is blocked, culprit attribution re-rasterizes the room per object,
    so cost grows ~O(n^1.7) in the objects ONE room holds — almost independently of
    its cell count. Measured 2026-09-30 in a 1,225-cell room, one peril: 25 objects
    0.90 s, 100 objects 9.03 s, 400 objects 134.17 s. The old per-floor cap of 500
    therefore allowed a ~10-minute /score inside every other bound.
    """
    def at(d: dict) -> None:
        d["floors"][0]["objects"] = [
            _object(f"ob{i}", 2.0, 2.0) for i in range(MAX_OBJECTS_PER_ROOM)
        ]

    def over(d: dict) -> None:
        d["floors"][0]["objects"] = [
            _object(f"ob{i}", 2.0, 2.0) for i in range(MAX_OBJECTS_PER_ROOM + 1)
        ]

    HomeModel.model_validate(_mutate(home, at))
    with pytest.raises(ValidationError, match="objects overlap it"):
        HomeModel.model_validate(_mutate(home, over))


def test_objects_are_counted_per_room_not_per_floor() -> None:
    """Spread out they pass; piled into one room they do not, at the same total.

    This is the distinction that matters: `objects_intersecting` filters by the
    room's bounding box, so it is the per-room set the router rasterizes against.
    """
    n = MAX_OBJECTS_PER_ROOM + 4
    spread = _home_with_n_rooms(n, 2.0, 2.0)
    # One object per room: n objects on the floor, never more than 1 per room.
    spread["floors"][0]["objects"] = [
        _object(f"ob{i}", r["polygon"][0][0] + 1.0, r["polygon"][0][1] + 1.0)
        for i, r in enumerate(spread["floors"][0]["rooms"])
    ]
    HomeModel.model_validate(spread)

    piled = _home_with_n_rooms(n, 2.0, 2.0)
    piled["floors"][0]["objects"] = [_object(f"ob{i}", 1.0, 1.0) for i in range(n)]
    assert len(piled["floors"][0]["objects"]) == len(spread["floors"][0]["objects"])
    with pytest.raises(ValidationError, match="objects overlap it"):
        HomeModel.model_validate(piled)


def test_objects_total_across_the_home(home: dict) -> None:
    """Under the per-floor cap on every floor, over the cap for the home."""
    def fn(d: dict) -> None:
        base = d["floors"][0]
        floors = []
        # 3 floors x 100 objects = 300 > MAX_OBJECTS_TOTAL, each floor under its cap.
        for level in range(3):
            fl = copy.deepcopy(base)
            fl["id"] = f"fl_{level}"
            fl["level"] = level
            fl["rooms"] = [
                {
                    "id": f"r_{level}_{i}", "name": "R", "type": "living",
                    "polygon": _rect(i * 6.0, 0, 5.0, 5.0), "source": "manual",
                }
                for i in range(MAX_OBJECTS_PER_FLOOR // MAX_OBJECTS_PER_ROOM)
            ]
            fl["openings"] = [{
                "id": f"op_{level}", "kind": "door",
                "room_ids": [f"r_{level}_0", "EXTERIOR"],
                "wall_segment": {"room_id": f"r_{level}_0", "edge_index": 0,
                                 "t0": 0.1, "t1": 0.3},
                "width_m": 0.9, "height_m": 2.0, "sill_height_m": 0.0,
                "source": "manual",
            }]
            fl["objects"] = [
                _object(f"ob_{level}_{i}_{j}", i * 6.0 + 2.0, 2.0)
                for i in range(MAX_OBJECTS_PER_FLOOR // MAX_OBJECTS_PER_ROOM)
                for j in range(MAX_OBJECTS_PER_ROOM)
            ]
            assert len(fl["objects"]) <= MAX_OBJECTS_PER_FLOOR
            floors.append(fl)
        d["floors"] = floors

    with pytest.raises(ValidationError, match="over the maximum of 200"):
        HomeModel.model_validate(_mutate(home, fn))


def test_the_maximum_home_stays_inside_the_stated_cost_budget() -> None:
    """The guard MISSION 4 asks for: bounded quantities, not seconds, so it cannot
    go flaky.

    Two independent terms, both measured on a 2026 Mac on 2026-09-30 for the three
    route plans `/score` runs:

      cells   ~26 us each                     -> 250,000 cells        = 6.11 s
      objects ~O(n^1.7) per room when blocked -> 200 obj at 25/room   = 20.29 s

    They are close to additive. The COMBINED worst case a valid home can reach
    (245,000 cells, 200 rooms, 200 objects, every route blocked) measures **21.82 s**.
    The first version of this test asserted only the cell term and claimed 7 s, which
    was wrong by 3x because it held the object count at the fixtures' handful.

    If any of these bounds is raised, re-measure the combined case here — do not
    extrapolate from one term.
    """
    # The bound values the 21.82 s figure was measured at. Asserting these rather than
    # a formula is deliberate: the two cost terms are NOT cleanly additive (a room
    # holding 25 objects is small, so its cell cost is already inside the object term),
    # and a formula that pretended otherwise is what produced the wrong 7 s claim.
    # Changing any bound below fails this test, which is the point — re-measure with
    # the combined worst case rather than extrapolating.
    MEASURED_AT = {
        "MAX_TOTAL_GRID_CELLS": 250_000,
        "MAX_OBJECTS_PER_ROOM": 25,
        "MAX_OBJECTS_PER_FLOOR": 120,
        "MAX_OBJECTS_TOTAL": 200,
    }
    MEASURED_WORST_CASE_S = 21.82
    BUDGET_S = 25.0

    import app.models as models

    actual = {name: getattr(models, name) for name in MEASURED_AT}
    assert actual == MEASURED_AT, (
        f"a size bound changed ({actual} != {MEASURED_AT}), so the {MEASURED_WORST_CASE_S}s "
        "worst-case measurement no longer applies. Re-measure a home at the COMBINED "
        "maximum (max cells AND max objects, every route blocked) and update both numbers."
    )
    assert MEASURED_WORST_CASE_S < BUDGET_S


# --- coordinates ----------------------------------------------------------

def test_coordinate_at_and_over_the_bound() -> None:
    HomeModel.model_validate(
        _single_room_home(_rect(MAX_COORD_M - 5.0, 0, 5.0, 4.0))
    )
    with pytest.raises(ValidationError, match=r"outside the supported range"):
        HomeModel.model_validate(
            _single_room_home(_rect(MAX_COORD_M - 4.9, 0, 5.0, 4.0))
        )


@pytest.mark.parametrize("bad", [math.inf, -math.inf, math.nan])
def test_non_finite_coordinates_get_their_own_message(bad: float) -> None:
    """A converter dividing by zero is a different bug from a too-large home."""
    with pytest.raises(ValidationError, match="must be finite"):
        HomeModel.model_validate(
            _single_room_home([[0.0, 0.0], [5.0, 0.0], [bad, 4.0], [0.0, 4.0]])
        )


def test_polygon_vertices_at_and_over_the_bound() -> None:
    def ngon(n: int, radius: float = 6.0) -> list[list[float]]:
        return [
            [
                round(radius * math.cos(2 * math.pi * i / n), 4),
                round(radius * math.sin(2 * math.pi * i / n), 4),
            ]
            for i in range(n)
        ]

    HomeModel.model_validate(_single_room_home(ngon(MAX_POLYGON_VERTICES)))
    with pytest.raises(ValidationError, match="vertices exceeds the maximum"):
        HomeModel.model_validate(_single_room_home(ngon(MAX_POLYGON_VERTICES + 1)))


# --- counts ---------------------------------------------------------------

def test_rooms_at_and_over_the_bound() -> None:
    """MAX_ROOMS counts the whole home, not one floor.

    At the bound the rooms are 1 m x 1 m (100 cells each, 20,000 total) so the
    cell budget is not what rejects the over-bound case.
    """
    at = _home_with_n_rooms(MAX_ROOMS, 1.0, 1.0)
    HomeModel.model_validate(at)
    over = _home_with_n_rooms(MAX_ROOMS + 1, 1.0, 1.0)
    with pytest.raises(ValidationError) as err:
        HomeModel.model_validate(over)
    assert "at most 200 items" in str(err.value) or "over the maximum of 200" in str(
        err.value
    )


def test_rooms_split_across_floors_still_counts_the_whole_home(home: dict) -> None:
    """Two floors of 120 rooms each pass the per-floor cap and fail the home cap."""

    def fn(d: dict) -> None:
        base = _home_with_n_rooms(120, 1.0, 1.0)["floors"][0]
        upper = copy.deepcopy(base)
        upper["id"] = "fl_2"
        upper["level"] = 1
        for r in upper["rooms"]:
            r["id"] = r["id"] + "_u"
        for i, op in enumerate(upper["openings"]):
            op["id"] = op["id"] + "_u"
            op["room_ids"] = [f"r_{i}_u", "EXTERIOR"]
            op["wall_segment"]["room_id"] = f"r_{i}_u"
        d["floors"] = [base, upper]

    with pytest.raises(ValidationError, match="rooms across 2 floors"):
        HomeModel.model_validate(_mutate(home, fn))


def test_floors_over_the_bound(home: dict) -> None:
    def fn(d: dict) -> None:
        base = d["floors"][0]
        d["floors"] = []
        for level in range(MAX_FLOORS + 1):
            fl = copy.deepcopy(base)
            fl["id"] = f"fl_{level}"
            fl["level"] = level
            fl["rooms"][0]["id"] = f"r_{level}"
            fl["openings"][0]["id"] = f"op_{level}"
            fl["openings"][0]["room_ids"] = [f"r_{level}", "EXTERIOR"]
            fl["openings"][0]["wall_segment"]["room_id"] = f"r_{level}"
            d["floors"].append(fl)

    with pytest.raises(ValidationError, match="at most 8 items"):
        HomeModel.model_validate(_mutate(home, fn))


def test_objects_over_the_bound(home: dict) -> None:
    def fn(d: dict) -> None:
        d["floors"][0]["objects"] = [
            {
                "id": f"ob_{i}",
                "category": "bookcase",
                "center": [1.0, 1.0],
                "size_m": [0.5, 0.3],
                "height_m": 1.8,
                "source": "manual",
            }
            for i in range(MAX_OBJECTS_PER_FLOOR + 1)
        ]

    with pytest.raises(ValidationError, match="at most 120 items"):
        HomeModel.model_validate(_mutate(home, fn))


def test_safety_points_over_the_bound(home: dict) -> None:
    def fn(d: dict) -> None:
        d["floors"][0]["safety_points"] = [
            {
                "id": f"sp_{i}",
                "kind": "gas_shutoff",
                "position": [1.0, 1.0],
                "source": "manual",
            }
            for i in range(MAX_SAFETY_POINTS_PER_FLOOR + 1)
        ]

    with pytest.raises(ValidationError, match="at most 100 items"):
        HomeModel.model_validate(_mutate(home, fn))


def test_openings_over_the_bound(home: dict) -> None:
    def fn(d: dict) -> None:
        base = d["floors"][0]["openings"][0]
        d["floors"][0]["openings"] = []
        for i in range(MAX_OPENINGS_PER_FLOOR + 1):
            op = copy.deepcopy(base)
            op["id"] = f"op_{i}"
            d["floors"][0]["openings"].append(op)

    with pytest.raises(ValidationError, match="at most 400 items"):
        HomeModel.model_validate(_mutate(home, fn))


def test_profiles_over_the_bound(home: dict) -> None:
    def fn(d: dict) -> None:
        d["profiles"] = [
            {"id": f"p_{i}", "name": f"P{i}", "bedroom_room_id": "r_1"}
            for i in range(MAX_PROFILES + 1)
        ]

    with pytest.raises(ValidationError, match="at most 50 items"):
        HomeModel.model_validate(_mutate(home, fn))


def test_stairs_over_the_bound(home: dict) -> None:
    def fn(d: dict) -> None:
        upper = copy.deepcopy(d["floors"][0])
        upper["id"] = "fl_2"
        upper["level"] = 1
        upper["rooms"][0]["id"] = "r_2"
        upper["openings"][0]["id"] = "op_2"
        upper["openings"][0]["room_ids"] = ["r_2", "EXTERIOR"]
        upper["openings"][0]["wall_segment"]["room_id"] = "r_2"
        d["floors"].append(upper)
        d["stairs"] = [
            {
                "id": f"st_{i}",
                "from": {"floor_id": "fl_1", "room_id": "r_1"},
                "to": {"floor_id": "fl_2", "room_id": "r_2"},
                "footprint": _rect(0, 0, 1, 3),
                "kind": "straight",
                "source": "manual",
            }
            for i in range(MAX_STAIRS + 1)
        ]

    with pytest.raises(ValidationError, match="at most 50 items"):
        HomeModel.model_validate(_mutate(home, fn))


# --- scalar dimensions ----------------------------------------------------

def test_floor_height_at_and_over_the_bound(home: dict) -> None:
    def at(d: dict) -> None:
        d["floors"][0]["height_m"] = MAX_FLOOR_HEIGHT_M

    def over(d: dict) -> None:
        d["floors"][0]["height_m"] = MAX_FLOOR_HEIGHT_M + 0.1

    HomeModel.model_validate(_mutate(home, at))
    with pytest.raises(ValidationError, match="less than or equal to 20"):
        HomeModel.model_validate(_mutate(home, over))


def test_opening_dimension_over_the_bound(home: dict) -> None:
    def fn(d: dict) -> None:
        d["floors"][0]["openings"][0]["width_m"] = MAX_OPENING_DIM_M + 1

    with pytest.raises(ValidationError, match="less than or equal to 20"):
        HomeModel.model_validate(_mutate(home, fn))


def _with_object(home: dict, **over: object) -> dict:
    obj = {
        "id": "ob_1",
        "category": "bookcase",
        "center": [1.0, 1.0],
        "size_m": [0.5, 0.3],
        "height_m": 1.8,
        "source": "manual",
    }
    obj.update(over)
    return _mutate(home, lambda d: d["floors"][0].__setitem__("objects", [obj]))


def test_object_size_over_the_bound(home: dict) -> None:
    HomeModel.model_validate(_with_object(home, size_m=[MAX_OBJECT_SIZE_M, 0.3]))
    with pytest.raises(ValidationError, match="exceeds the maximum of 50 m on a side"):
        HomeModel.model_validate(_with_object(home, size_m=[MAX_OBJECT_SIZE_M + 1, 0.3]))


def test_object_height_over_the_bound(home: dict) -> None:
    HomeModel.model_validate(_with_object(home, height_m=MAX_OBJECT_HEIGHT_M))
    with pytest.raises(ValidationError, match="height_m .* exceeds the maximum"):
        HomeModel.model_validate(_with_object(home, height_m=MAX_OBJECT_HEIGHT_M + 1))


def test_object_centre_outside_the_coordinate_range(home: dict) -> None:
    with pytest.raises(ValidationError, match="outside the supported range"):
        HomeModel.model_validate(_with_object(home, center=[MAX_COORD_M + 1, 1.0]))


def test_object_rotation_must_be_finite(home: dict) -> None:
    with pytest.raises(ValidationError, match="rotation_deg must be finite"):
        HomeModel.model_validate(_with_object(home, rotation_deg=math.nan))


# --- stairs footprints go through the same polygon bounds ----------------

def test_stairs_footprint_respects_the_polygon_bounds(home: dict) -> None:
    def fn(d: dict) -> None:
        upper = copy.deepcopy(d["floors"][0])
        upper["id"] = "fl_2"
        upper["level"] = 1
        upper["rooms"][0]["id"] = "r_2"
        upper["openings"][0]["id"] = "op_2"
        upper["openings"][0]["room_ids"] = ["r_2", "EXTERIOR"]
        upper["openings"][0]["wall_segment"]["room_id"] = "r_2"
        d["floors"].append(upper)
        d["stairs"] = [
            {
                "id": "st_1",
                "from": {"floor_id": "fl_1", "room_id": "r_1"},
                "to": {"floor_id": "fl_2", "room_id": "r_2"},
                "footprint": _rect(0, 0, MAX_ROOM_SPAN_M + 1, 3),
                "kind": "straight",
                "source": "manual",
            }
        ]

    with pytest.raises(ValidationError, match="footprint: bounding box"):
        HomeModel.model_validate(_mutate(home, fn))


# --- real data is unaffected (MISSION 3) ---------------------------------

def test_every_fixture_is_far_inside_every_bound() -> None:
    """Records the headroom, so a future tightening has to face the numbers."""
    from tests.conftest import FIXTURES_DIR

    worst_cells = 0
    for path in sorted(FIXTURES_DIR.glob("*.json")):
        import json

        raw = json.loads(path.read_text())
        if raw.get("schema_version") is None:
            continue
        model = HomeModel.model_validate(raw)
        cells = sum(
            bbox_cell_count(list(r.polygon)) for fl in model.floors for r in fl.rooms
        )
        worst_cells = max(worst_cells, cells)
    # jagged.json is the largest committed fixture at 51,600 cells.
    assert 0 < worst_cells <= MAX_TOTAL_GRID_CELLS / 4, (
        f"the largest fixture now needs {worst_cells:,} cells, less than 4x headroom "
        f"under MAX_TOTAL_GRID_CELLS={MAX_TOTAL_GRID_CELLS:,}"
    )
