"""S3.4: profile tag → constraint mapping, and per-profile routing end-to-end.

The acceptance case is the demo moment: on twostory.json, Grandpa
(mobility_limited) and Maya (child) must not get the same answer.
"""

from __future__ import annotations

import pytest

from app.config import get_thresholds
from app.models import HomeModel, Profile, ProfileTag
from app.routing.engine import compute_route_plan
from app.routing.plan import RoutingConstraints
from app.routing.profiles import (
    CHILD_WINDOW_PENALTY_M,
    ELDERLY_STAIR_PENALTY_M,
    constraints_for_profile,
    find_profile,
)


@pytest.fixture
def thresholds():
    return get_thresholds()


@pytest.fixture
def twostory_home(twostory) -> HomeModel:
    return HomeModel.model_validate(twostory)


def _profile(*tags: ProfileTag) -> Profile:
    return Profile(id="p_test", name="Test", tags=list(tags), bedroom_room_id="r_x")


def _room(plan, room_id):
    return next(r for r in plan.rooms if r.room_id == room_id)


# --- the mapping table -----------------------------------------------------

def test_mobility_limited_maps_to_hard_stair_and_window_avoidance(thresholds):
    c = constraints_for_profile(_profile(ProfileTag.mobility_limited), thresholds)
    assert c.avoid_stairs is True
    assert c.avoid_windows is True


def test_child_maps_to_soft_window_deprioritization_only(thresholds):
    c = constraints_for_profile(_profile(ProfileTag.child), thresholds)
    assert c.window_penalty_m == CHILD_WINDOW_PENALTY_M
    assert c.avoid_stairs is False
    assert c.avoid_windows is False


def test_elderly_maps_to_soft_stair_preference_and_code_sill_limit(thresholds):
    c = constraints_for_profile(_profile(ProfileTag.elderly), thresholds)
    assert c.stair_penalty_m == ELDERLY_STAIR_PENALTY_M
    assert c.avoid_stairs is False  # a preference, not a prohibition
    assert c.max_sill_height_m == thresholds.window_max_sill_m


def test_pet_never_alters_routing(thresholds):
    """Corpus is explicit: pets are checklist/phrasing only."""
    assert constraints_for_profile(_profile(ProfileTag.pet), thresholds) == (
        RoutingConstraints()
    )


def test_tags_compose_strictest_wins(thresholds):
    c = constraints_for_profile(
        _profile(ProfileTag.elderly, ProfileTag.mobility_limited, ProfileTag.pet),
        thresholds,
    )
    assert c.avoid_stairs is True  # hard beats elderly's soft penalty
    assert c.avoid_windows is True


def test_mapping_is_deterministic_regardless_of_tag_order(thresholds):
    a = constraints_for_profile(_profile(ProfileTag.child, ProfileTag.elderly), thresholds)
    b = constraints_for_profile(_profile(ProfileTag.elderly, ProfileTag.child), thresholds)
    assert a == b


def test_untagged_profile_is_unconstrained(thresholds):
    assert constraints_for_profile(_profile(), thresholds) == RoutingConstraints()


# --- the S1.2 constraints hook, exercised through profiles ------------------

def test_grandpa_and_maya_get_different_answers(twostory_home, thresholds):
    """The acceptance criterion: a profile switch changes the routing outcome."""
    grandpa = find_profile(twostory_home.profiles, "p_grandpa")
    maya = find_profile(twostory_home.profiles, "p_maya")

    grandpa_plan = compute_route_plan(twostory_home, thresholds, profile=grandpa)
    maya_plan = compute_route_plan(twostory_home, thresholds, profile=maya)

    grandpa_room = _room(grandpa_plan, grandpa.bedroom_room_id)
    maya_room = _room(maya_plan, maya.bedroom_room_id)

    # Grandpa's upstairs bedroom has no stair-free, window-free way out: the
    # honest no-viable-route flag, not an unusable route.
    assert grandpa_room.primary is None
    assert [f.kind for f in grandpa_room.findings] == ["no_viable_route"]

    # Maya still gets a real route out.
    assert maya_room.primary is not None
    assert not any(f.kind == "no_viable_route" for f in maya_room.findings)


def test_mobility_limited_route_never_uses_stairs_or_windows(
    twostory_home, thresholds
):
    grandpa = find_profile(twostory_home.profiles, "p_grandpa")
    plan = compute_route_plan(twostory_home, thresholds, profile=grandpa)
    for room in plan.rooms:
        for route in (room.primary, room.secondary):
            if route is not None:
                assert route.uses_stairs is False
                assert route.uses_window is False


def test_plan_records_the_profile_and_its_derived_constraints(
    twostory_home, thresholds
):
    grandpa = find_profile(twostory_home.profiles, "p_grandpa")
    plan = compute_route_plan(twostory_home, thresholds, profile=grandpa)
    assert plan.profile_id == "p_grandpa"
    assert plan.constraints == constraints_for_profile(grandpa, thresholds)


def test_unprofiled_plan_is_unchanged(twostory_home, thresholds):
    """The S3.4 fields are additive: no profile → the S1.2 behaviour."""
    plan = compute_route_plan(twostory_home, thresholds)
    assert plan.profile_id is None
    assert plan.constraints == RoutingConstraints()


def test_profile_and_constraints_together_is_a_caller_error(
    twostory_home, thresholds
):
    grandpa = find_profile(twostory_home.profiles, "p_grandpa")
    with pytest.raises(ValueError, match="not both"):
        compute_route_plan(
            twostory_home,
            thresholds,
            constraints=RoutingConstraints(),
            profile=grandpa,
        )


def test_child_window_penalty_deprioritizes_but_never_strands(
    apartment, thresholds
):
    """A window that is the only way out is still returned for a child."""
    home = HomeModel.model_validate(apartment)
    child = Profile(
        id="p_kid", name="Kid", tags=[ProfileTag.child], bedroom_room_id="r_x"
    )
    plan = compute_route_plan(home, thresholds, profile=child)
    baseline = compute_route_plan(home, thresholds)
    for room, base_room in zip(plan.rooms, baseline.rooms):
        if base_room.primary is not None:
            assert room.primary is not None, (
                f"child was stranded in {room.room_id} by a soft penalty"
            )


def test_elderly_stair_penalty_changes_upstairs_secondaries(
    twostory_home, thresholds
):
    """The soft stair preference is observable: it re-routes, it doesn't strand."""
    elderly = Profile(
        id="p_e", name="Elder", tags=[ProfileTag.elderly], bedroom_room_id="r_x"
    )
    baseline = compute_route_plan(twostory_home, thresholds)
    plan = compute_route_plan(twostory_home, thresholds, profile=elderly)

    changed = [
        b.room_id
        for b, p in zip(baseline.rooms, plan.rooms)
        if (b.secondary is None) != (p.secondary is None)
        or (b.secondary and p.secondary and b.secondary.exit_id != p.secondary.exit_id)
    ]
    assert changed, "elderly stair preference had no effect on twostory"
    # Every room that had a way out still has one — a preference, not a ban.
    for base_room, room in zip(baseline.rooms, plan.rooms):
        if base_room.primary is not None:
            assert room.primary is not None


def test_child_penalty_is_a_no_op_on_the_current_fixtures(
    twostory_home, thresholds
):
    """Documents a real limitation rather than overclaiming the mapping.

    The engine's universal WINDOW_EXIT_PENALTY already dominates every
    door/window choice in the fixtures, so the child surcharge never changes a
    route there. The mapping still encodes the corpus's intent, and the child
    tag's observable effect today is the accompanied-adult explanation phrasing
    (S3.1), not the geometry. Delete this test if a fixture ever makes the
    choice close enough to flip.
    """
    baseline = compute_route_plan(twostory_home, thresholds)
    child = Profile(
        id="p_c", name="Kid", tags=[ProfileTag.child], bedroom_room_id="r_x"
    )
    plan = compute_route_plan(twostory_home, thresholds, profile=child)
    for base_room, room in zip(baseline.rooms, plan.rooms):
        assert (base_room.primary is None) == (room.primary is None)
        if base_room.primary is not None:
            assert room.primary.exit_id == base_room.primary.exit_id


def test_find_profile_misses_return_none(twostory_home):
    assert find_profile(twostory_home.profiles, "p_nobody") is None


# --- v2.0 sensory tags are routing-neutral (S6.1) --------------------------

@pytest.mark.parametrize("tag", [ProfileTag.hearing_impaired, ProfileTag.vision_impaired])
def test_sensory_tags_produce_no_routing_constraints(tag, thresholds) -> None:
    """The v2.0 tags exist so the S6.4 checklist can act on them (strobe alarms, NOAA
    radio). They are deliberately NOT routing signals: neither one changes how a person
    gets out of a building. This test is the contract — if a future session wires either
    to a constraint, that is a decision to argue for, not to slip in."""
    tagged = Profile(id="p_x", name="X", tags=[tag], bedroom_room_id="r_bed_master")
    untagged = Profile(id="p_x", name="X", tags=[], bedroom_room_id="r_bed_master")
    assert constraints_for_profile(tagged, thresholds) == constraints_for_profile(
        untagged, thresholds
    )


def test_sensory_tags_do_not_alter_a_computed_route(twostory_home, thresholds) -> None:
    """The end-to-end version of the above: same home, same person, one tag added, and
    the engine must return a byte-identical plan."""
    grandpa = find_profile(twostory_home.profiles, "p_grandpa")
    before = compute_route_plan(twostory_home, thresholds, profile=grandpa)
    grandpa.tags = grandpa.tags + [ProfileTag.hearing_impaired]
    after = compute_route_plan(twostory_home, thresholds, profile=grandpa)
    assert before.model_dump() == after.model_dump()


def test_safety_points_are_not_obstacles(twostory, thresholds) -> None:
    """twostory carries a gas shutoff and an electrical panel. They are landmarks; the
    routing engine must not see them at all."""
    home = HomeModel.model_validate(twostory)
    assert any(fl.safety_points for fl in home.floors), "fixture should have safety points"
    with_points = compute_route_plan(home, thresholds)
    for fl in home.floors:
        fl.safety_points = []
    assert with_points.model_dump() == compute_route_plan(home, thresholds).model_dump()
