"""S1.2 tests: routing engine — hand-verified routes on all fixtures, secondary
egress, bottlenecks, determinism, and the profile-constraints hook."""

from __future__ import annotations

import json

import pytest

from app.models import HomeModel
from app.routing.egress import EgressThresholds
from app.routing.engine import compute_route_plan, find_bottlenecks, _openings_by_id
from app.routing.graph import build_graph
from app.routing.plan import RoutePlan, RoutingConstraints
from tests.conftest import REPO_ROOT, load_fixture

THRESHOLDS_PATH = REPO_ROOT / "backend" / "corpus" / "egress_thresholds.json"


@pytest.fixture(scope="module")
def thresholds() -> EgressThresholds:
    return EgressThresholds.from_corpus(json.loads(THRESHOLDS_PATH.read_text()))


def _plan(name: str, thresholds: EgressThresholds, **kwargs) -> RoutePlan:
    home = HomeModel.model_validate(load_fixture(name))
    return compute_route_plan(home, thresholds, **kwargs)


def _room(plan: RoutePlan, room_id: str):
    return next(r for r in plan.rooms if r.room_id == room_id)


# --- bungalow: hand-verified routes ------------------------------------------

def test_bungalow_living_primary_is_front_door(thresholds) -> None:
    room = _room(_plan("bungalow.json", thresholds), "r_living")
    assert room.primary is not None
    assert room.primary.exit_id == "d_front"
    assert not room.primary.uses_window
    assert not room.primary.uses_stairs


def test_bungalow_living_secondary_uses_different_exit(thresholds) -> None:
    room = _room(_plan("bungalow.json", thresholds), "r_living")
    assert room.secondary is not None
    assert room.secondary.exit_id != room.primary.exit_id
    assert room.secondary.exit_id == "w_living"  # own egress window beats a detour
    assert room.findings == []


def test_bungalow_bedroom_primary_door_over_own_window(thresholds) -> None:
    # door path bedroom->living->front door beats the window penalty
    room = _room(_plan("bungalow.json", thresholds), "r_bedroom")
    assert room.primary.exit_id == "d_front"
    node_ids = [w.node_id for w in room.primary.waypoints]
    assert node_ids[:4] == ["r_bedroom", "d_living_bedroom", "r_living", "d_front"]
    assert room.secondary.exit_id == "w_bedroom"
    assert room.secondary.uses_window


def test_bungalow_bath_has_secondary_despite_bad_window(thresholds) -> None:
    # w_bath is not viable egress; bath still has two ways out via doors/windows
    room = _room(_plan("bungalow.json", thresholds), "r_bath")
    assert room.primary is not None and room.secondary is not None
    exits = {room.primary.exit_id, room.secondary.exit_id}
    assert "w_bath" not in exits


def test_waypoints_start_at_room_and_end_exterior(thresholds) -> None:
    room = _room(_plan("bungalow.json", thresholds), "r_bedroom")
    wp = room.primary.waypoints
    assert wp[0].kind == "room" and wp[0].node_id == "r_bedroom"
    assert wp[-1].kind == "exterior"
    assert all(w.floor_id == "f1" for w in wp)


# --- apartment: single exit + bottleneck (planted issue) ----------------------

def test_apartment_all_primaries_use_single_door(thresholds) -> None:
    plan = _plan("apartment.json", thresholds)
    for room in plan.rooms:
        assert room.primary is not None, room.room_id
        assert room.primary.exit_id == "d_entry"


def test_apartment_no_secondary_egress_anywhere(thresholds) -> None:
    plan = _plan("apartment.json", thresholds)
    for room in plan.rooms:
        assert room.secondary is None
        kinds = [f.kind for f in room.findings]
        assert kinds == ["no_secondary_egress"], room.room_id


def test_apartment_entry_door_flagged_as_bottleneck(thresholds) -> None:
    plan = _plan("apartment.json", thresholds)
    assert len(plan.bottlenecks) == 1
    b = plan.bottlenecks[0]
    assert b.opening_id == "d_entry"
    assert b.disconnected_room_ids == [
        "r_bed1", "r_bed2", "r_hall", "r_kitchen", "r_living"
    ]


# --- twostory: stairs, cross-floor waypoints ----------------------------------

def test_twostory_upstairs_primary_goes_down_stairs(thresholds) -> None:
    room = _room(_plan("twostory.json", thresholds), "r_bed_kids")
    assert room.primary.uses_stairs
    assert room.primary.exit_id in {"d_front", "d_back"}
    floors = [w.floor_id for w in room.primary.waypoints]
    assert floors[0] == "f2" and floors[-1] == "f1"  # starts upstairs, exits below
    kinds = [w.kind for w in room.primary.waypoints]
    assert "stair" in kinds
    # stair waypoints ordered by travel: f2 then f1
    stair_floors = [
        w.floor_id for w in room.primary.waypoints if w.kind == "stair"
    ]
    assert stair_floors == ["f2", "f1"]


def test_twostory_master_secondary_is_own_window(thresholds) -> None:
    room = _room(_plan("twostory.json", thresholds), "r_bed_master")
    assert room.secondary is not None
    assert room.secondary.exit_id == "w_master"
    assert room.secondary.uses_window
    assert not room.secondary.uses_stairs


def test_twostory_kids_room_secondary_avoids_primary_exit(thresholds) -> None:
    # kids' window fails egress, so the secondary must be the other ground door
    room = _room(_plan("twostory.json", thresholds), "r_bed_kids")
    assert room.secondary is not None
    assert {room.primary.exit_id, room.secondary.exit_id} == {"d_front", "d_back"}


def test_twostory_ground_rooms_have_no_stairs_in_routes(thresholds) -> None:
    plan = _plan("twostory.json", thresholds)
    for rid in ["r_hall1", "r_living", "r_kitchen"]:
        room = _room(plan, rid)
        assert not room.primary.uses_stairs


def test_route_length_positive_and_metadata_consistent(thresholds) -> None:
    plan = _plan("twostory.json", thresholds)
    for room in plan.rooms:
        for route in filter(None, [room.primary, room.secondary]):
            assert route.length_m > 0
            assert route.exit_id == route.waypoints[-2].node_id


# --- constraints hook (S3.4): profiles change routes ---------------------------

def test_avoid_stairs_changes_upstairs_routes(thresholds) -> None:
    base = _room(_plan("twostory.json", thresholds), "r_bed_master")
    constrained = _room(
        _plan(
            "twostory.json", thresholds,
            constraints=RoutingConstraints(avoid_stairs=True),
        ),
        "r_bed_master",
    )
    assert base.primary.uses_stairs
    assert constrained.primary is not None
    assert not constrained.primary.uses_stairs
    assert constrained.primary.exit_id == "w_master"  # forced out the window


def test_mobility_limited_upstairs_yields_no_viable_route(thresholds) -> None:
    # Grandpa: avoid_stairs + avoid_windows and his bedroom is upstairs
    plan = _plan(
        "twostory.json", thresholds,
        constraints=RoutingConstraints(avoid_stairs=True, avoid_windows=True),
    )
    room = _room(plan, "r_bed_master")
    assert room.primary is None
    assert [f.kind for f in room.findings] == ["no_viable_route"]
    # ground floor is unaffected
    assert _room(plan, "r_living").primary is not None


def test_max_sill_constraint_filters_window_exits(thresholds) -> None:
    plan = _plan(
        "twostory.json", thresholds,
        constraints=RoutingConstraints(max_sill_height_m=0.5),
    )
    for room in plan.rooms:
        for route in filter(None, [room.primary, room.secondary]):
            assert not route.uses_window  # all fixture sills exceed 0.5m


def test_constraints_do_not_change_output_type(thresholds) -> None:
    plan = _plan(
        "twostory.json", thresholds,
        constraints=RoutingConstraints(avoid_windows=True),
    )
    assert isinstance(plan, RoutePlan)
    assert plan.constraints.avoid_windows


# --- determinism ---------------------------------------------------------------

def test_route_plan_deterministic(thresholds) -> None:
    p1 = _plan("twostory.json", thresholds)
    p2 = _plan("twostory.json", thresholds)
    assert p1.model_dump() == p2.model_dump()


def test_bottleneck_analysis_ignores_room_only_cutoffs_at_default(thresholds) -> None:
    home = HomeModel.model_validate(load_fixture("twostory.json"))
    graph = build_graph(home, thresholds)
    bottlenecks = find_bottlenecks(graph, _openings_by_id(home), min_rooms=2)
    # two independent ground exits + master window -> no >=2-room single point of failure
    assert bottlenecks == []
