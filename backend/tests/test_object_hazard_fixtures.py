"""S7.1: the object-hazard test bed is planted, and it is planted BOTH ways.

S7.4 will assert that its rules fire on the positive objects and stay SILENT on the
negative ones. A rule that fires on everything passes a positives-only suite, so the
controls are the half that actually proves anything — and a control is only a control
while it stays geometrically capable of firing. These tests pin that: each negative is
checked to differ from its positive in exactly the field the rule is supposed to read,
not in some incidental way (moved across the room, shrunk below the height cut) that
would make it pass for the wrong reason.

No hazard rules exist yet — that is deliberately S7.4's job, and it needs S7.2's corpus
first. These tests describe the fixtures only.
"""

from __future__ import annotations

import math

import pytest

from app.models import FloorObject, HomeModel
from tests.conftest import load_fixture

# The topple band of an object is its footprint grown by height_m on every face
# (a falling cabinet sweeps roughly its own height) — docs/object-hazard-spec.md §4 R1.


def _aabb(obj: FloorObject) -> tuple[float, float, float, float]:
    """Axis-aligned bounds. Every seeded object is unrotated, which is asserted."""
    assert obj.rotation_deg == 0, f"{obj.id}: this helper assumes an unrotated footprint"
    (cx, cy), (w, d) = obj.center, obj.size_m
    return cx - w / 2, cy - d / 2, cx + w / 2, cy + d / 2


def _topple_band(obj: FloorObject) -> tuple[float, float, float, float]:
    x0, y0, x1, y1 = _aabb(obj)
    h = obj.height_m
    return x0 - h, y0 - h, x1 + h, y1 + h


def _overlaps(a: tuple[float, float, float, float],
              b: tuple[float, float, float, float]) -> bool:
    return not (a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1])


def _gap_m(a: FloorObject, b: FloorObject) -> float:
    """Shortest distance between two axis-aligned footprints, 0 if they touch."""
    ax0, ay0, ax1, ay1 = _aabb(a)
    bx0, by0, bx1, by1 = _aabb(b)
    dx = max(bx0 - ax1, ax0 - bx1, 0.0)
    dy = max(by0 - ay1, ay0 - by1, 0.0)
    return math.hypot(dx, dy)


def _objects(fixture: str, floor_id: str) -> dict[str, FloorObject]:
    home = HomeModel.model_validate(load_fixture(fixture))
    floor = next(f for f in home.floors if f.id == floor_id)
    return {o.id: o for o in floor.objects}


# ---------------------------------------------------------------------------
# jagged — R1 topple, and the v2.1 fields carrying something 2.0 could not express


@pytest.fixture(scope="module")
def jagged_upstairs() -> dict[str, FloorObject]:
    return _objects("jagged.json", "fu")


def test_the_unsecured_bookcase_topple_band_reaches_the_bed(jagged_upstairs) -> None:
    bookcase = jagged_upstairs["o_u_bookcase_unsecured"]
    bed = jagged_upstairs["o_u_bed"]
    assert bookcase.secured is False
    assert bookcase.elevation_m == 0  # R1 only applies to floor-standing objects
    assert _overlaps(_topple_band(bookcase), _aabb(bed))


def test_the_secured_bookcase_would_also_reach_the_bed_and_is_silenced_only_by_secured(
    jagged_upstairs,
) -> None:
    """The control. If this object were merely far away, S7.4 could pass by checking
    distance and never reading `secured` at all — so it is placed to reach the bed on
    the opposite side, with identical dimensions, differing in exactly one field."""
    control = jagged_upstairs["o_u_bookcase_secured"]
    positive = jagged_upstairs["o_u_bookcase_unsecured"]
    bed = jagged_upstairs["o_u_bed"]

    assert control.secured is True
    assert _overlaps(_topple_band(control), _aabb(bed)), (
        "the control has stopped being capable of firing — it no longer proves "
        "that `secured` is what silences it"
    )
    # Same category, same footprint, same height: `secured` is the only difference.
    assert control.category == positive.category
    assert control.size_m == positive.size_m
    assert control.height_m == positive.height_m
    assert control.elevation_m == positive.elevation_m


def test_the_mounted_tv_is_the_case_schema_2_0_could_not_represent(
    jagged_upstairs,
) -> None:
    tv = jagged_upstairs["o_u_tv_over_bed"]
    bed = jagged_upstairs["o_u_bed"]
    assert tv.mounted is True
    assert tv.elevation_m > bed.height_m, "must hang above the bed, not sit on it"
    # Directly over the sleeping area, which is the whole point of the object.
    assert _overlaps(_aabb(tv), _aabb(bed))
    # `mounted` and `secured` stay orthogonal: hanging it did not make it strapped.
    assert tv.secured is False


# ---------------------------------------------------------------------------
# twostory — R2 heat-source clearance, and the always-topple set

NFPA_CLEARANCE_M = 0.9


@pytest.fixture(scope="module")
def twostory_ground() -> dict[str, FloorObject]:
    return _objects("twostory.json", "f1")


def test_the_near_heater_is_inside_the_clearance_distance(twostory_ground) -> None:
    gap = _gap_m(twostory_ground["o_1_heater_near_sofa"],
                 twostory_ground["o_1_sofa_living"])
    assert gap < NFPA_CLEARANCE_M
    assert gap > 0, "overlapping footprints would be a different (and fake) problem"


def test_the_far_heat_source_is_the_control_and_sits_well_outside_it(
    twostory_ground,
) -> None:
    """Same category, same room, same floor — only the distance differs. A rule that
    fires on `category == heat_source` rather than on a measurement fails here."""
    far = twostory_ground["o_1_fireplace_far"]
    near = twostory_ground["o_1_heater_near_sofa"]
    assert far.category == near.category
    gap = _gap_m(far, twostory_ground["o_1_sofa_living"])
    assert gap > NFPA_CLEARANCE_M * 2, (
        "the control has drifted close enough to be ambiguous"
    )


def test_the_water_heater_is_unsecured_and_its_control_is_secured(
    twostory_ground,
) -> None:
    assert twostory_ground["o_1_water_heater"].secured is False
    assert twostory_ground["o_1_bookcase_secured"].secured is True


def test_every_seeded_object_is_floor_standing_unless_it_says_otherwise() -> None:
    """elevation_m defaults to 0 and that default must keep meaning what pre-2.1
    objects meant. Exactly one seeded object is off the floor; if a second appears
    without a deliberate reason, this catches it."""
    off_the_floor = [
        o.id
        for fixture, floor in (("jagged.json", "fu"), ("twostory.json", "f1"))
        for o in _objects(fixture, floor).values()
        if o.elevation_m != 0 or o.mounted
    ]
    assert off_the_floor == ["o_u_tv_over_bed"]
