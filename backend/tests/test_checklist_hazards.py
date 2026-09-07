import json
import pytest
from app.models import HomeModel, Household, Profile, ProfileTag
from app.routing.plan import RoutingConstraints
from app.routing.engine import compute_route_plan
from app.routing.profiles import constraints_for_profile
from app.routing.egress import EgressThresholds
from app.scoring.checklist import build_checklist

from tests.conftest import load_fixture, REPO_ROOT

@pytest.fixture
def thresholds():
    with open(REPO_ROOT / "backend/corpus/egress_thresholds.json") as f:
        return EgressThresholds.from_corpus(json.load(f))

@pytest.fixture
def sources():
    with open(REPO_ROOT / "backend/corpus/sources.json") as f:
        return json.load(f)["sources"]

def test_mitigation_items_renter_vs_owner(twostory, thresholds):
    home_renter = HomeModel.model_validate(twostory)
    from app.models import FloorObject
    heavy_obj = FloorObject(id="wardrobe_1", source="manual", category="wardrobe", center=(1.0, 1.0), size_m=(1.0, 1.0), height_m=2.0, rotation_deg=0.0, secured=False)
    home_renter.floors[0].objects.append(heavy_obj)
    home_renter.household = Household(tenure="rent")
    plan = compute_route_plan(home_renter, thresholds, peril="earthquake")
    
    checklist_renter = build_checklist(home_renter, plan, [], {}, thresholds, earthquake_plan=plan)
    mitigation_renter = [i for i in checklist_renter if i.category == "mitigation" and i.id.startswith("mitigation.secure")]
    assert len(mitigation_renter) > 0
    assert all(i.id.endswith(".renter") for i in mitigation_renter)
    assert all("adhesive straps" in i.title for i in mitigation_renter)

    home_owner = HomeModel.model_validate(twostory)
    home_owner.floors[0].objects.append(heavy_obj)
    home_owner.household = Household(tenure="own")
    plan_owner = compute_route_plan(home_owner, thresholds, peril="earthquake")
    
    checklist_owner = build_checklist(home_owner, plan_owner, [], {}, thresholds, earthquake_plan=plan_owner)
    mitigation_owner = [i for i in checklist_owner if i.category == "mitigation" and i.id.startswith("mitigation.secure")]
    assert len(mitigation_owner) > 0
    assert not any(i.id.endswith(".renter") for i in mitigation_owner)
    assert all("wall studs" in i.title for i in mitigation_owner)

def test_equipment_presatisfaction(twostory, thresholds):
    home = HomeModel.model_validate(twostory)
    plan = compute_route_plan(home, thresholds)
    
    # Baseline: no equipment
    home.household = Household(existing_equipment=[])
    items_baseline = build_checklist(home, plan, [], {}, thresholds)
    alarms_baseline = [i for i in items_baseline if i.category == "smoke_alarm" and not i.id.endswith("test_monthly") and not i.id.endswith("replace_10y")]
    assert len(alarms_baseline) > 0
    assert all(not i.done for i in alarms_baseline)

    # With equipment declared
    home.household = Household(existing_equipment=["smoke_alarm"])
    items_equipped = build_checklist(home, plan, [], {}, thresholds)
    alarms_equipped = [i for i in items_equipped if i.category == "smoke_alarm" and not i.id.endswith("test_monthly") and not i.id.endswith("replace_10y")]
    assert len(alarms_equipped) > 0
    assert all(i.done for i in alarms_equipped)

def test_hearing_impaired_produces_alerts_no_routing_change(twostory, thresholds):
    home = HomeModel.model_validate(twostory)
    plan = compute_route_plan(home, thresholds)
    
    baseline_constraints = constraints_for_profile(home.profiles[0], thresholds)
    
    # Add hearing_impaired
    home.profiles[0].tags.append(ProfileTag.hearing_impaired)
    new_constraints = constraints_for_profile(home.profiles[0], thresholds)
    
    # 1. No routing constraint change
    assert baseline_constraints == new_constraints
    
    # 2. Alerts item exists
    checklist = build_checklist(home, plan, [], {}, thresholds)
    strobe_items = [i for i in checklist if i.category == "alerts" and "strobe" in i.id]
    assert len(strobe_items) == 1
    assert home.profiles[0].id in strobe_items[0].id

def test_pet_produces_item_no_routing_change(twostory, thresholds):
    home = HomeModel.model_validate(twostory)
    plan = compute_route_plan(home, thresholds)
    
    baseline_constraints = constraints_for_profile(home.profiles[0], thresholds)
    
    # Add pet
    home.profiles[0].tags.append(ProfileTag.pet)
    new_constraints = constraints_for_profile(home.profiles[0], thresholds)
    
    # 1. No routing constraint change
    assert baseline_constraints == new_constraints
    
    # 2. Pet item exists
    checklist = build_checklist(home, plan, [], {}, thresholds)
    pet_items = [i for i in checklist if "pet_evac" in i.id]
    assert len(pet_items) == 1
    assert home.profiles[0].id in pet_items[0].id

def test_general_items_appear_once(twostory, thresholds):
    home = HomeModel.model_validate(twostory)
    plan_fire = compute_route_plan(home, thresholds, peril="fire")
    plan_tornado = compute_route_plan(home, thresholds, peril="tornado")
    plan_earthquake = compute_route_plan(home, thresholds, peril="earthquake")
    
    checklist = build_checklist(
        home, plan_fire, [], {}, thresholds,
        tornado_plan=plan_tornado, earthquake_plan=plan_earthquake
    )
    
    # 72h kit should only appear once
    kits = [i for i in checklist if i.id == "supply_kit.72h"]
    assert len(kits) == 1

def test_id_stability(twostory, thresholds):
    home = HomeModel.model_validate(twostory)
    plan_fire = compute_route_plan(home, thresholds, peril="fire")
    
    list1 = build_checklist(home, plan_fire, [], {}, thresholds)
    list2 = build_checklist(home, plan_fire, [], {}, thresholds)
    
    ids1 = [i.id for i in list1]
    ids2 = [i.id for i in list2]
    assert ids1 == ids2
    
    # Mutate unrelated field
    home.floors[0].rooms[0].name = "Mutated Room Name"
    list3 = build_checklist(home, plan_fire, [], {}, thresholds)
    ids3 = set([i.id for i in list3])
    
    assert "practice.meeting_point" in ids3
    assert "supply_kit.72h" in ids3

@pytest.mark.parametrize("fixture_name", ["bungalow", "apartment", "twostory", "bungalow_narrow"])
def test_citation_resolution(fixture_name, thresholds, sources, request):
    fixture = request.getfixturevalue(fixture_name)
    home = HomeModel.model_validate(fixture)
    
    plan_fire = compute_route_plan(home, thresholds, peril="fire")
    plan_tornado = compute_route_plan(home, thresholds, peril="tornado")
    plan_earthquake = compute_route_plan(home, thresholds, peril="earthquake")
    
    checklist = build_checklist(
        home, plan_fire, [], {}, thresholds,
        tornado_plan=plan_tornado, earthquake_plan=plan_earthquake
    )
    
    valid_ids = {s["id"] for s in sources}
    
    for item in checklist:
        if item.source_citation is not None:
            assert item.source_citation in valid_ids, f"Item {item.id} has invalid citation {item.source_citation}"
