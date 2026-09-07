import json
import pytest
from app.models import HomeModel, Profile
from app.routing.plan import RoutingConstraints
from app.routing.engine import compute_route_plan
from app.routing.egress import EgressThresholds

from tests.conftest import load_fixture, REPO_ROOT

@pytest.fixture
def twostory():
    return HomeModel.model_validate(load_fixture("twostory.json"))

@pytest.fixture
def jagged():
    return HomeModel.model_validate(load_fixture("jagged.json"))

@pytest.fixture
def bungalow_narrow():
    return HomeModel.model_validate(load_fixture("bungalow-narrow.json"))

@pytest.fixture
def thresholds():
    with open(REPO_ROOT / "backend/corpus/egress_thresholds.json") as f:
        return EgressThresholds.from_corpus(json.load(f))

def test_fire_vs_tornado_different_destinations(twostory, thresholds):
    # For a given room on twostory, e.g., the Master Bedroom, fire route exit is an exterior door
    plan_fire = compute_route_plan(twostory, thresholds, peril="fire")
    plan_tornado = compute_route_plan(twostory, thresholds, peril="tornado")
    
    room_fire = next(r for r in plan_fire.rooms if r.room_id == "r_bed_master")
    room_tornado = next(r for r in plan_tornado.rooms if r.room_id == "r_bed_master")
    
    # Fire routes to an exterior door
    assert room_fire.primary.exit_id == "d_front"
    
    # Tornado routes to an interior room
    assert room_tornado.primary.exit_id != "d_front"

def test_mobility_limited_tornado_no_viable_safe_room(twostory, thresholds):
    constraints = RoutingConstraints(avoid_stairs=True)
    plan_tornado = compute_route_plan(twostory, thresholds, constraints=constraints, peril="tornado")
    
    room_tornado = next(r for r in plan_tornado.rooms if r.room_id == "r_bed_master")
    
    # Should be no_viable_safe_room
    assert room_tornado.primary is None
    assert any(f.kind == "no_viable_safe_room" for f in room_tornado.findings)

def test_mobile_home_tornado_no_viable_safe_room(bungalow_narrow, thresholds):
    # Every room touches an exterior wall
    plan = compute_route_plan(bungalow_narrow, thresholds, peril="tornado")
    
    assert plan.rooms[0].primary is None
    assert any(f.kind == "no_viable_safe_room" for f in plan.rooms[0].findings)

def test_earthquake_cover_points(jagged, thresholds):
    plan = compute_route_plan(jagged, thresholds, peril="earthquake")
    
    kitch = next(r for r in plan.rooms if r.room_id == "r_g_kitch")
    assert kitch.cover_object_id == "o_g_table"
    
    bath = next(r for r in plan.rooms if r.room_id == "r_g_live")
    assert bath.cover_object_id is None
    assert any(f.kind == "no_cover_in_room" for f in bath.findings)

def test_earthquake_cover_nearest_table(jagged, thresholds):
    # Add two tables to the same room, one closer to the centroid
    home = jagged.model_copy(deep=True)
    room = next(r for f in home.floors for r in f.rooms if r.id == "r_g_kitch")
    floor = next(f for f in home.floors if room in f.rooms)
    
    cx = sum(p[0] for p in room.polygon) / len(room.polygon)
    cy = sum(p[1] for p in room.polygon) / len(room.polygon)
    
    from app.models import FloorObject
    # Clear existing objects
    floor.objects = []
    
    table1 = FloorObject(
        id="t1", source="manual", category="table", center=(cx + 1, cy), size_m=(1, 1), height_m=1.0, rotation_deg=0
    )
    table2 = FloorObject(
        id="t2", source="manual", category="table", center=(cx + 5, cy), size_m=(1, 1), height_m=1.0, rotation_deg=0
    )
    floor.objects.extend([table2, table1]) # Added in reverse to ensure sorting by distance works
    
    plan = compute_route_plan(home, thresholds, peril="earthquake")
    r_plan = next(r for r in plan.rooms if r.room_id == room.id)
    assert r_plan.cover_object_id == "t1" # The closer one

def test_triangle_of_life_never_recommended(twostory, thresholds):
    plan = compute_route_plan(twostory, thresholds, peril="earthquake")
    for room in plan.rooms:
        for finding in room.findings:
            assert "beside" not in finding.detail.lower()
            assert "triangle" not in finding.detail.lower()

def test_earthquake_finding_has_valid_citation(twostory, thresholds):
    plan = compute_route_plan(twostory, thresholds, peril="earthquake")
    bath = next(r for r in plan.rooms if r.room_id == "r_bath2")
    finding = next(f for f in bath.findings if f.kind == "no_cover_in_room")
    assert "[cite: shakeout-guidance]" in finding.detail
    
    with open(REPO_ROOT / "backend/corpus/sources.json") as f:
        sources = json.load(f)
    assert any(s["id"] == "shakeout-guidance" for s in sources["sources"])

def test_determinism_perils(twostory, thresholds):
    plan_t1 = compute_route_plan(twostory, thresholds, peril="tornado")
    plan_t2 = compute_route_plan(twostory, thresholds, peril="tornado")
    assert plan_t1.model_dump_json() == plan_t2.model_dump_json()
    
    plan_e1 = compute_route_plan(twostory, thresholds, peril="earthquake")
    plan_e2 = compute_route_plan(twostory, thresholds, peril="earthquake")
    assert plan_e1.model_dump_json() == plan_e2.model_dump_json()
