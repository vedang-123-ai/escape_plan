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

def test_a_site_built_home_always_gets_an_interior_shelter(bungalow_narrow, thresholds):
    """Replaces test_mobile_home_tornado_no_viable_safe_room (removed 2026-09-06).

    That test asserted a single-storey home whose every room touches an exterior wall has
    NO safe room — and ran it on `bungalow_narrow`, an ordinary site-built bungalow. It was
    pinning a defect: the engine told every bungalow and apartment occupant to leave the
    house during a tornado warning, while the corpus committed alongside it says to use the
    most interior room, "such as a bathroom, closet, or hallway"
    (severe-weather-tornado.md, [cite: noaa-tornado]).

    Construction type is not derivable from a footprint polygon, so geometry must never be
    used to infer a mobile home. Leave-the-house advice needs an explicit modelled fact.
    """
    plan = compute_route_plan(bungalow_narrow, thresholds, peril="tornado")

    assert plan.rooms[0].primary is not None, "a site-built home must be given a shelter"
    assert not any(
        f.kind == "no_viable_safe_room" for r in plan.rooms for f in (r.findings or [])
    )


@pytest.mark.parametrize(
    "fixture_name", ["bungalow", "apartment", "bungalow-blocked", "bungalow-narrow", "twostory", "jagged"]
)
def test_no_fixture_with_an_interior_room_is_told_to_leave(fixture_name, thresholds):
    """The regression guard for the above. Every committed fixture is a site-built home with
    at least one room carrying no exterior opening, so none of them may ever produce
    `no_viable_safe_room`. This is the assertion that would have caught the original defect:
    it fired on 4 of 5 fixtures and every suite still passed."""
    home = HomeModel.model_validate(load_fixture(f"{fixture_name}.json"))
    plan = compute_route_plan(home, thresholds, peril="tornado")

    unsheltered = [
        r.room_id
        for r in plan.rooms
        if any(f.kind == "no_viable_safe_room" for f in (r.findings or []))
    ]
    assert not unsheltered, f"{fixture_name}: no shelter found for {unsheltered}"

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
