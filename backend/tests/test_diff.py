import pytest
import math
from app.models import HomeModel, FloorObject, Room, Floor, Opening, WallSegmentRef, EXTERIOR_ID
from app.routing.obstructions import Obstruction
from app.routing.egress import EgressThresholds
from app.routing.diff import compute_diff, align_room, DiffResult

def make_test_home(add_box=False, box_in_corridor=False):
    # simple room
    room = Room(id="r1", name="Hall", type="hall", source="scan", confidence=1.0, polygon=[(0,0), (5,0), (5,5), (0,5)])
    objects = []
    if add_box:
        if box_in_corridor:
            # Box blocking a hypothetical door at (2.5, 0)
            objects.append(FloorObject(id="o1", category="other", center=(2.5, 1.0), size_m=(2.0, 1.0), height_m=1.0, rotation_deg=0, source="scan", confidence=1.0))
        else:
            # Box away from doors
            objects.append(FloorObject(id="o1", category="other", center=(1.0, 4.0), size_m=(1.0, 1.0), height_m=1.0, rotation_deg=0, source="scan", confidence=1.0))

    # For obstructions to trigger, we need an opening
    op = Opening(
        id="op1", kind="door", width_m=1.0,
        wall_segment=WallSegmentRef(room_id="r1", edge_index=0, t0=0.4, t1=0.6), # door on bottom edge
        room_ids=["r1", "r2"], source="scan", confidence=1.0, height_m=2.0, sill_height_m=0.0
    )
    r2 = Room(id="r2", name="R2", type="other", source="scan", confidence=1.0, polygon=[(0, -5), (5, -5), (5, -1), (0, -1)])
    floor = Floor(id="f1", level=0, name="Ground", height_m=3, rooms=[room, r2], openings=[op], objects=objects)
    
    return HomeModel.model_validate({
        "schema_version": "2.1",
        "home_id": "h1",
        "name": "Test",
        "floors": [floor.model_dump()],
        "meta": {
            "created": "2023-01-01T00:00:00Z",
            "modified": "2023-01-01T00:00:00Z"
        }
    })

def test_diff_identical():
    h1 = make_test_home()
    res = compute_diff(h1, h1, "r1", EgressThresholds(window_min_area_m2=0, window_min_area_grade_m2=0, window_min_height_m=0, window_min_width_m=0, window_max_sill_m=0, door_min_width_m=0.8, door_min_height_m=2.0), 0.3)
    assert res.success
    assert len(res.diff_objects) == 0
    assert len(res.obstructions) == 0

def test_diff_planted_box_in_corridor():
    h1 = make_test_home()
    h2 = make_test_home(add_box=True, box_in_corridor=True)
    res = compute_diff(h1, h2, "r1", EgressThresholds(window_min_area_m2=0, window_min_area_grade_m2=0, window_min_height_m=0, window_min_width_m=0, window_max_sill_m=0, door_min_width_m=0.8, door_min_height_m=2.0), 0.3)
    assert res.success
    assert len(res.diff_objects) == 1
    assert res.diff_objects[0].id == "scan_o1"
    assert len(res.obstructions) > 0
    assert "scan_o1" in res.obstructions[0].object_ids

def test_diff_planted_box_outside_corridor():
    h1 = make_test_home()
    h2 = make_test_home(add_box=True, box_in_corridor=False)
    res = compute_diff(h1, h2, "r1", EgressThresholds(window_min_area_m2=0, window_min_area_grade_m2=0, window_min_height_m=0, window_min_width_m=0, window_max_sill_m=0, door_min_width_m=0.8, door_min_height_m=2.0), 0.3)
    assert res.success
    assert len(res.diff_objects) == 1
    assert len(res.obstructions) == 0

def test_diff_mismatched_room():
    h1 = make_test_home()
    h2 = make_test_home()
    h2.floors[0].rooms[0].polygon = [(0,0), (10,0), (10,10), (0,10)] # huge room
    res = compute_diff(h1, h2, "r1", EgressThresholds(window_min_area_m2=0, window_min_area_grade_m2=0, window_min_height_m=0, window_min_width_m=0, window_max_sill_m=0, door_min_width_m=0.8, door_min_height_m=2.0), 0.3)
    assert not res.success
    assert res.error == "couldn't line this scan up"
