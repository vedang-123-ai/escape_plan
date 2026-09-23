"""S10.1 QA regressions — BUG-01..05.

Each test in this file reproduces a defect found by the S10.1 QA pass
(`docs/tracker/notes/2026-09-14-S10.1-object-detection-qa.md`; full reproductions in
`git show 01f6ca0:docs/tracker/TODO.md`) and was watched failing on the pre-fix engine
before the fix landed in S11.3. BUG-05 was found in S11.3 while reading R1 for BUG-04.

The four stock fixtures are exercised too: the engine's behaviour on them is what the
demo and the score actually show, and BUG-03 was live on `twostory.json`.
"""

from datetime import datetime
from pathlib import Path

import pytest

from app import config
from app.models import (
    Floor,
    FloorObject,
    HomeModel,
    Meta,
    ObjectCategory,
    Opening,
    OpeningKind,
    Room,
    WallSegmentRef,
)
from app.routing.object_hazards import (
    CitedSection,
    CitedThreshold,
    EngineeringConstant,
    EngineeringSection,
    ObjectHazardThresholds,
    analyze_object_hazards,
)

FIXTURES = Path(__file__).resolve().parents[2] / "schema" / "fixtures"


@pytest.fixture
def thresholds() -> ObjectHazardThresholds:
    return ObjectHazardThresholds(
        cited=CitedSection(heater_clearance=CitedThreshold(value_m=0.9)),
        engineering_constants=EngineeringSection(
            topple_min_height_m=EngineeringConstant(value=1.2),
            topple_slenderness_ratio=EngineeringConstant(value=2.0),
            overhead_min_elevation_m=EngineeringConstant(value=0.9),
            door_approach_radius_m=EngineeringConstant(value=0.6),
            registration_tolerance_m=EngineeringConstant(value=0.3),
        ),
    )


def _home(rooms: list[Room], objects: list[FloorObject], openings: list[Opening] | None = None) -> HomeModel:
    return HomeModel(
        schema_version="2.1",
        home_id="h1",
        name="test",
        meta=Meta(created=datetime.now(), modified=datetime.now()),
        floors=[
            Floor(
                id="f1",
                level=1,
                name="f1",
                height_m=3.0,
                rooms=rooms,
                openings=openings or [],
                objects=objects,
            )
        ],
    )


def _one_room(objects: list[FloorObject], openings: list[Opening] | None = None) -> HomeModel:
    return _home(
        [
            Room(
                id="r1",
                name="Bedroom",
                source="manual",
                type="bedroom",
                polygon=[(0, 0), (10, 0), (10, 10), (0, 10)],
            )
        ],
        objects,
        openings,
    )


# ---------------------------------------------------------------- BUG-01 (R3)

def test_r3_no_false_positive_heat_source_vs_heat_source(thresholds):
    """BUG-01: a stove beside a stove is not an NFPA clearance violation.

    R3 asks whether something that can burn sits inside a heater's clearance zone.
    Another appliance that is itself a heat source is not that thing, and the advice
    ("move it farther away") is addressed at neither object.
    """
    home = _one_room(
        [
            FloorObject(
                source="manual", id="stove1", category=ObjectCategory.heat_source,
                center=(1, 1), size_m=(0.8, 0.8), height_m=0.9,
            ),
            FloorObject(
                source="manual", id="stove2", category=ObjectCategory.heat_source,
                center=(2.0, 1), size_m=(0.8, 0.8), height_m=0.9,
            ),
        ]
    )
    assert analyze_object_hazards(home, thresholds) == []


def test_r3_still_fires_for_a_non_heat_source_inside_the_clearance(thresholds):
    """The BUG-01 exclusion must not silence R3 for what it is actually for."""
    home = _one_room(
        [
            FloorObject(
                source="manual", id="heater1", category=ObjectCategory.heat_source,
                center=(1, 1), size_m=(0.5, 0.5), height_m=0.5,
            ),
            FloorObject(
                source="manual", id="sofa1", category=ObjectCategory.sofa,
                center=(1.8, 1.0), size_m=(1, 1), height_m=0.5,
            ),
        ]
    )
    hazards = analyze_object_hazards(home, thresholds)
    assert [h.rule_id for h in hazards] == ["heat_clearance"]
    assert hazards[0].object_id == "sofa1"
    assert hazards[0].severity == "high"


# ---------------------------------------------------------------- BUG-02 (room assignment)

def _two_rooms() -> list[Room]:
    return [
        Room(id="r1", name="Bedroom", source="manual", type="bedroom",
             polygon=[(0, 0), (10, 0), (10, 10), (0, 10)]),
        Room(id="r2", name="Living", source="manual", type="living",
             polygon=[(10, 0), (20, 0), (20, 10), (10, 10)]),
    ]


def test_r1_no_topple_across_room_boundary(thresholds):
    """BUG-02: a wardrobe in the bedroom cannot topple onto a bed in the living room.

    Room assignment used a bounding-circle-vs-AABB filter, so the bed at x=11 (circle
    radius ~1.41 reaching x=9.59) was assigned to r1 as well as r2 and the engine
    reported it 0.5 m from the wardrobe — through a wall.
    """
    home = _home(
        _two_rooms(),
        [
            FloorObject(source="manual", id="wardrobe1", category=ObjectCategory.wardrobe,
                        center=(9, 5), size_m=(1, 1), height_m=1.9, secured=False),
            FloorObject(source="manual", id="bed1", category=ObjectCategory.bed,
                        center=(11, 5), size_m=(2, 2), height_m=0.5),
        ],
    )
    assert analyze_object_hazards(home, thresholds) == []


def test_r3_no_heat_clearance_across_room_boundary(thresholds):
    """BUG-02 is room assignment, not R1: every rule read the same bled list."""
    home = _home(
        _two_rooms(),
        [
            FloorObject(source="manual", id="heater1", category=ObjectCategory.heat_source,
                        center=(9.6, 5), size_m=(0.5, 0.5), height_m=0.5),
            FloorObject(source="manual", id="sofa1", category=ObjectCategory.sofa,
                        center=(10.6, 5), size_m=(1, 1), height_m=0.5),
        ],
    )
    assert analyze_object_hazards(home, thresholds) == []


def test_an_object_is_assigned_to_exactly_one_room(thresholds):
    """The old filter could assign one object to several rooms, duplicating its findings."""
    home = _home(
        _two_rooms(),
        [
            FloorObject(source="manual", id="wardrobe1", category=ObjectCategory.wardrobe,
                        center=(9.5, 5), size_m=(1, 1), height_m=1.9, secured=False),
            FloorObject(source="manual", id="bed1", category=ObjectCategory.bed,
                        center=(8.0, 5), size_m=(2, 2), height_m=0.5),
        ],
    )
    hazards = analyze_object_hazards(home, thresholds)
    assert [(h.rule_id, h.object_id, h.room_id) for h in hazards] == [("topple", "wardrobe1", "r1")]


def test_objects_inside_a_room_are_still_found(thresholds):
    """Point-in-polygon must not drop objects the AABB filter did catch legitimately."""
    home = _home(
        _two_rooms(),
        [
            FloorObject(source="manual", id="wardrobe2", category=ObjectCategory.wardrobe,
                        center=(15, 5), size_m=(1, 1), height_m=1.9, secured=False),
            FloorObject(source="manual", id="bed2", category=ObjectCategory.bed,
                        center=(17.2, 5), size_m=(2, 2), height_m=0.5),
        ],
    )
    hazards = analyze_object_hazards(home, thresholds)
    assert [(h.rule_id, h.object_id, h.room_id) for h in hazards] == [("topple", "wardrobe2", "r2")]


# ---------------------------------------------------------------- BUG-03 (R5 vs R1)

def test_r5_suppresses_r1_for_an_unsecured_water_heater(thresholds):
    """BUG-03: one heater, one strap-it card.

    R5 and R1 both fired for the same object, so the checklist showed
    `hazard.water_heater_unsecured.wh1` AND `hazard.topple.wh1` — two cards telling the
    user to strap the same heater.
    """
    home = _one_room(
        [
            FloorObject(source="manual", id="wh1", category=ObjectCategory.water_heater,
                        center=(1, 1), size_m=(0.5, 0.5), height_m=1.9, secured=False),
            FloorObject(source="manual", id="bed1", category=ObjectCategory.bed,
                        center=(3.2, 1), size_m=(2, 2), height_m=0.5),
        ]
    )
    hazards = analyze_object_hazards(home, thresholds)
    assert [h.rule_id for h in hazards] == ["water_heater_unsecured"]


def test_the_surviving_water_heater_finding_keeps_the_measurement(thresholds):
    """Suppressing R1 must not cost the user the number R1 was carrying.

    Spec §2: every finding states a measured value, the threshold it violates, a
    citation and an action. R5 alone has no geometry, so it absorbs R1's reach.
    """
    home = _one_room(
        [
            FloorObject(source="manual", id="wh1", category=ObjectCategory.water_heater,
                        center=(1, 1), size_m=(0.5, 0.5), height_m=1.9, secured=False),
            FloorObject(source="manual", id="bed1", category=ObjectCategory.bed,
                        center=(3.2, 1), size_m=(2, 2), height_m=0.5),
        ]
    )
    (h,) = analyze_object_hazards(home, thresholds)
    assert h.target == "bed"
    assert h.reach_m is not None
    assert "the bed" in h.detail
    assert f"{h.reach_m:.1f} m" in h.detail


def test_a_water_heater_with_nothing_in_reach_still_fires_r5_alone(thresholds):
    home = _one_room(
        [
            FloorObject(source="manual", id="wh1", category=ObjectCategory.water_heater,
                        center=(1, 1), size_m=(0.5, 0.5), height_m=1.0, secured=False),
        ]
    )
    (h,) = analyze_object_hazards(home, thresholds)
    assert h.rule_id == "water_heater_unsecured"
    assert h.target is None and h.reach_m is None
    assert "isn't strapped" in h.detail


def test_a_secured_water_heater_fires_nothing(thresholds):
    home = _one_room(
        [
            FloorObject(source="manual", id="wh1", category=ObjectCategory.water_heater,
                        center=(1, 1), size_m=(0.5, 0.5), height_m=1.9, secured=True),
            FloorObject(source="manual", id="bed1", category=ObjectCategory.bed,
                        center=(3.2, 1), size_m=(2, 2), height_m=0.5),
        ]
    )
    assert analyze_object_hazards(home, thresholds) == []


# ---------------------------------------------------------------- BUG-04 (narration)

def _window_room_home(object_height_m: float = 1.9) -> HomeModel:
    """One room, one opening, and that opening is a window."""
    return _one_room(
        [
            FloorObject(source="manual", id="store1", category=ObjectCategory.storage,
                        center=(1.0, 1.0), size_m=(1, 1), height_m=object_height_m,
                        secured=False),
        ],
        openings=[
            Opening(
                id="win1",
                kind=OpeningKind.window,
                room_ids=["r1", "EXTERIOR"],
                wall_segment=WallSegmentRef(room_id="r1", edge_index=0, t0=0.1, t1=0.2),
                width_m=0.9,
                height_m=1.2,
                sill_height_m=0.9,
                source="manual",
            )
        ],
    )


def test_r1_detail_says_window_not_doorway_for_a_window_opening(thresholds):
    """BUG-04: `best_target_name` hardcoded "the doorway" for every Opening."""
    (h,) = analyze_object_hazards(_window_room_home(), thresholds)
    assert h.rule_id == "topple"
    assert "the window 'win1'" in h.detail
    assert "doorway" not in h.detail


def test_r1_target_is_egress_for_a_window_not_sofa(thresholds):
    """`target` was derived by sniffing the word "door" out of the detail sentence.

    Renaming the label to "window" therefore silently retargeted the finding to "sofa" —
    there is no sofa within a kilometre of this fixture.
    """
    (h,) = analyze_object_hazards(_window_room_home(), thresholds)
    assert h.target == "egress"


def test_r1_still_says_doorway_for_a_door_opening(thresholds):
    home = _one_room(
        [
            FloorObject(source="manual", id="store1", category=ObjectCategory.storage,
                        center=(1.0, 1.0), size_m=(1, 1), height_m=1.9, secured=False),
        ],
        openings=[
            Opening(
                id="d1",
                kind=OpeningKind.door,
                room_ids=["r1", "EXTERIOR"],
                wall_segment=WallSegmentRef(room_id="r1", edge_index=0, t0=0.1, t1=0.2),
                width_m=0.9,
                height_m=2.0,
                sill_height_m=0.0,
                source="manual",
            )
        ],
    )
    (h,) = analyze_object_hazards(home, thresholds)
    assert "the doorway 'd1'" in h.detail
    assert h.target == "egress"


# ---------------------------------------------------------------- BUG-05 (R1 severity)

def test_r1_severity_is_not_high_just_because_the_room_has_one_exit(thresholds):
    """BUG-05 (found in S11.3): `is_high` was set before the reach test.

    Spec §4 R1: high when the band reaches a bed or the room's *only* egress approach.
    The loop set `is_high = True` for a single-exit room on its first iteration, before
    `_obb_intersects_circle` had said anything, so every unsecured tall object in a
    one-door room capped the composite score whether or not it could reach the door.
    """
    home = _one_room(
        [
            FloorObject(source="manual", id="store1", category=ObjectCategory.storage,
                        center=(1.0, 1.0), size_m=(1, 1), height_m=1.9, secured=False),
            FloorObject(source="manual", id="sofa1", category=ObjectCategory.sofa,
                        center=(3.2, 1.0), size_m=(1, 1), height_m=0.5),
        ],
        openings=[
            Opening(
                id="d_far",
                kind=OpeningKind.door,
                room_ids=["r1", "EXTERIOR"],
                wall_segment=WallSegmentRef(room_id="r1", edge_index=1, t0=0.8, t1=0.9),
                width_m=0.9,
                height_m=2.0,
                sill_height_m=0.0,
                source="manual",
            )
        ],
    )
    (h,) = analyze_object_hazards(home, thresholds)
    assert h.rule_id == "topple"
    assert h.target == "sofa"
    assert h.severity == "info"


def test_r1_severity_is_high_when_the_band_reaches_the_only_exit(thresholds):
    (h,) = analyze_object_hazards(_window_room_home(), thresholds)
    assert h.severity == "high"


# ---------------------------------------------------------------- stock fixtures

STOCK = ["bungalow", "apartment", "twostory", "jagged"]


@pytest.fixture(scope="module")
def real_thresholds() -> ObjectHazardThresholds:
    return config.get_object_hazard_thresholds()


def _fixture_hazards(name: str, thresholds: ObjectHazardThresholds):
    home = HomeModel.model_validate_json((FIXTURES / f"{name}.json").read_text())
    return analyze_object_hazards(home, thresholds)


@pytest.mark.parametrize(
    "name,expected",
    [
        ("bungalow", []),
        ("apartment", []),
        (
            "jagged",
            [
                ("topple", "o_u_bookcase_unsecured", "r_u_bed", "high"),
                ("overhead", "o_u_tv_over_bed", "r_u_bed", "high"),
                ("topple", "o_u_ward", "r_u_bed", "info"),
            ],
        ),
        (
            # BUG-03 was live here: `o_1_water_heater` produced BOTH `topple` and
            # `water_heater_unsecured` before S11.3. One finding now, carrying the reach.
            "twostory",
            [
                ("heat_clearance", "o_1_sofa_living", "r_living", "high"),
                ("water_heater_unsecured", "o_1_water_heater", "r_kitchen", "high"),
            ],
        ),
    ],
)
def test_stock_fixture_findings_are_pinned(name, expected, real_thresholds):
    """The demo and the score run on these four. Changing them must be deliberate."""
    hazards = _fixture_hazards(name, real_thresholds)
    got = sorted((h.rule_id, h.object_id, h.room_id, h.severity) for h in hazards)
    assert got == sorted(expected)


@pytest.mark.parametrize("name", STOCK)
def test_no_fixture_reports_an_object_outside_the_room_it_is_in(name, real_thresholds):
    """BUG-02 on real data: every finding's room must actually contain the object."""
    from app.routing.object_hazards import _point_in_poly

    home = HomeModel.model_validate_json((FIXTURES / f"{name}.json").read_text())
    centers = {
        (floor.id, obj.id): (obj.center, floor)
        for floor in home.floors
        for obj in floor.objects
    }
    for h in _fixture_hazards(name, real_thresholds):
        center, floor = centers[(h.floor_id, h.object_id)]
        room = next(r for r in floor.rooms if r.id == h.room_id)
        assert _point_in_poly(center, list(room.polygon)), (
            f"{name}: {h.rule_id} on {h.object_id} was reported in {h.room_id}, "
            f"which does not contain the object's centre {center}"
        )


@pytest.mark.parametrize("name", STOCK)
def test_no_fixture_produces_two_findings_for_one_water_heater(name, real_thresholds):
    for h in _fixture_hazards(name, real_thresholds):
        if h.object_category == "water_heater":
            assert h.rule_id == "water_heater_unsecured", (
                f"{name}: water heater {h.object_id} still fires {h.rule_id} alongside R5"
            )


@pytest.mark.parametrize("name", STOCK)
def test_every_fixture_finding_carries_a_citation_and_an_action(name, real_thresholds):
    """Spec §2, checked on real data rather than asserted in prose."""
    import json

    sources = json.loads(
        (Path(__file__).resolve().parents[1] / "corpus" / "sources.json").read_text()
    )
    valid = {s["id"] for s in sources["sources"]}
    for h in _fixture_hazards(name, real_thresholds):
        assert h.citation in valid, f"{name}: {h.citation} does not resolve"
        assert h.detail.rstrip().endswith("."), f"{name}: {h.object_id} detail is not a sentence"
        assert any(
            n is not None for n in (h.reach_m, h.gap_m, h.clearance_m, h.threshold_m)
        ), f"{name}: {h.rule_id} on {h.object_id} states no measured value"


def test_jagged_narrates_its_egress_window_as_a_window(real_thresholds):
    """BUG-04 was not hypothetical — it shipped on a stock fixture.

    `r_u_bed`'s only opening, `w_u_bed`, is a window, and the wardrobe's topple band
    reaches it. Every demo run of jagged.json told the user about a doorway that does
    not exist.
    """
    (h,) = [
        h for h in _fixture_hazards("jagged", real_thresholds) if h.object_id == "o_u_ward"
    ]
    assert "the window 'w_u_bed'" in h.detail
    assert "doorway" not in h.detail
    assert h.target == "egress"


def test_twostory_water_heater_keeps_its_reach_after_r1_is_suppressed(real_thresholds):
    """BUG-03 was live here too: two cards for `o_1_water_heater` before S11.3."""
    (h,) = [
        h
        for h in _fixture_hazards("twostory", real_thresholds)
        if h.object_id == "o_1_water_heater"
    ]
    assert h.rule_id == "water_heater_unsecured"
    assert h.severity == "high"
    assert h.target == "egress"
    assert h.reach_m == pytest.approx(0.69, abs=0.01)
    assert "isn't strapped" in h.detail and "can reach the doorway 'd_back'" in h.detail


def test_an_object_whose_centre_is_in_no_room_is_analysed_by_no_rule(thresholds):
    """Pinning a consequence of the BUG-02 fix so it is deliberate, not accidental.

    Room membership is now point-in-polygon on the centre, so an object whose centre
    lands outside every polygon — possible on a real scan where a wall line and an
    object centre nearly coincide — gets no hazard analysis at all. The old bounding
    box would have caught it (along with three rooms it was not in). No fixture has
    such an object today; a real scan might, which is why S11.10 is asked to look.
    """
    home = _home(
        [
            Room(id="r1", name="Bedroom", source="manual", type="bedroom",
                 polygon=[(0, 0), (4, 0), (4, 4), (0, 4)]),
        ],
        [
            FloorObject(source="manual", id="ward_outside", category=ObjectCategory.wardrobe,
                        center=(6, 6), size_m=(1, 1), height_m=1.9, secured=False),
            FloorObject(source="manual", id="bed_outside", category=ObjectCategory.bed,
                        center=(7.5, 6), size_m=(2, 2), height_m=0.5),
        ],
    )
    assert analyze_object_hazards(home, thresholds) == []
