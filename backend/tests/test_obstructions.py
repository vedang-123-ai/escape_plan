"""Obstruction attribution: which object is in the way, and how far to move it.

The engine already knew a doorway was unreachable (test_obstacles.py). These tests
pin the layer that turns that into advice — naming the culprit and measuring the
move — because "something blocks this door" is not something a user can act on.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.models import FloorObject, HomeModel, ObjectCategory, Source
from app.routing.egress import EgressThresholds
from app.routing.obstructions import (
    COMFORT_MARGIN_M,
    analyze_obstructions,
    code_clearance_m,
    culprit_object_ids,
    tolerated_clearance_m,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
THRESHOLDS_PATH = REPO_ROOT / "backend" / "corpus" / "egress_thresholds.json"
FIXTURES = REPO_ROOT / "schema" / "fixtures"

SQUARE = [(0.0, 0.0), (5.0, 0.0), (5.0, 4.0), (0.0, 4.0)]


@pytest.fixture(scope="module")
def thresholds() -> EgressThresholds:
    return EgressThresholds.from_corpus(json.loads(THRESHOLDS_PATH.read_text()))


def _box(obj_id: str, center, size=(2.0, 0.9), rotation=0.0) -> FloorObject:
    return FloorObject(
        id=obj_id,
        category=ObjectCategory.sofa,
        center=center,
        size_m=size,
        height_m=0.8,
        rotation_deg=rotation,
        source=Source.manual,
    )


def _blocked_home() -> HomeModel:
    return HomeModel.model_validate(
        json.loads((FIXTURES / "bungalow-blocked.json").read_text())
    )


# ---------------------------------------------------------------------------
# Attribution


def test_names_the_single_object_that_blocks_the_doorway(thresholds) -> None:
    obstructions = analyze_obstructions(_blocked_home(), thresholds)
    blocking = [o for o in obstructions if o.kind == "blocks_opening"]
    assert len(blocking) == 1
    found = blocking[0]
    # The planted wardrobe, and ONLY the wardrobe — not every object in the room.
    assert found.object_ids == ("o_wardrobe_blocking",)
    assert found.room_id == "r_bedroom"
    assert found.opening_id == "d_living_bedroom"


def test_blocked_approach_reports_zero_passable_width_and_a_real_move(
    thresholds,
) -> None:
    found = analyze_obstructions(_blocked_home(), thresholds)[0]
    assert found.passable_width_m == 0.0
    assert found.required_width_m == pytest.approx(thresholds.door_min_width_m)
    # The move has to at least recover the full required width, and be a clean
    # 5 cm increment rather than a float artifact.
    assert found.suggested_move_m >= thresholds.door_min_width_m
    assert round(found.suggested_move_m * 100) % 5 == 0


def test_detail_names_the_object_and_the_distance(thresholds) -> None:
    detail = analyze_obstructions(_blocked_home(), thresholds)[0].detail
    assert "wardrobe" in detail
    assert "0.85" in detail  # the measured move, not a vague "move it back"


def test_a_home_with_no_objects_yields_nothing(thresholds) -> None:
    home = HomeModel.model_validate(
        json.loads((FIXTURES / "twostory.json").read_text())
    )
    assert analyze_obstructions(home, thresholds) == []


# ---------------------------------------------------------------------------
# Counterfactual mechanics


def test_culprit_is_the_object_whose_removal_restores_the_path(thresholds) -> None:
    clearance = code_clearance_m(thresholds)
    blocker = _box("o_blocker", (2.5, 1.0), size=(5.0, 0.6))
    bystander = _box("o_bystander", (0.4, 3.6), size=(0.4, 0.4))
    culprits = culprit_object_ids(
        SQUARE, [blocker, bystander], (2.5, 3.5), (2.5, 0.0), clearance, 0.6
    )
    # Proximity would have implicated neither or both; the counterfactual picks
    # exactly the one that matters.
    assert [o.id for o in culprits] == ["o_blocker"]


def test_single_sufficient_object_is_preferred_over_a_group(thresholds) -> None:
    clearance = code_clearance_m(thresholds)
    # Two boxes each spanning half the room. Removing EITHER opens a full-width
    # way around, so the honest advice is "move one thing", not "move both".
    left = _box("o_a", (1.2, 1.0), size=(2.4, 0.6))
    right = _box("o_b", (3.8, 1.0), size=(2.4, 0.6))
    culprits = culprit_object_ids(
        SQUARE, [left, right], (2.5, 3.5), (2.5, 0.0), clearance, 0.6
    )
    assert len(culprits) == 1
    # Deterministic pick: id order, so the same home always names the same object.
    assert culprits[0].id == "o_a"


def test_group_is_reported_when_no_single_removal_frees_the_path(thresholds) -> None:
    clearance = code_clearance_m(thresholds)
    # An L of two boxes sealing the corner the doorway sits in. Removing either
    # one leaves a 0.6 m slot — under the 0.813 m door width — so neither is
    # sufficient alone and both have to be named.
    across = _box("o_a", (1.0, 0.9), size=(2.0, 0.6))
    down = _box("o_b", (0.9, 1.0), size=(0.6, 2.0))
    culprits = culprit_object_ids(
        SQUARE, [across, down], (3.5, 3.0), (0.4, 0.0), clearance, 0.6
    )
    assert {o.id for o in culprits} == {"o_a", "o_b"}


def test_geometry_not_furniture_yields_no_culprit(thresholds) -> None:
    clearance = code_clearance_m(thresholds)
    # A goal outside the room entirely: removing every object cannot help, so
    # blaming an object would be a lie.
    culprits = culprit_object_ids(
        SQUARE, [_box("o_a", (2.5, 2.0))], (2.5, 2.0), (50.0, 50.0), clearance, 0.6
    )
    assert culprits == ()


def test_tolerated_clearance_is_monotone_and_bounded(thresholds) -> None:
    upper = code_clearance_m(thresholds) + COMFORT_MARGIN_M
    # Wide-open room: the leg survives all the way to the ceiling value.
    assert tolerated_clearance_m(SQUARE, [], (2.5, 2.0), (2.5, 0.0), 0.6, upper) == upper
    # Pinched by a sofa: still passable, but not at full comfort clearance.
    pinched = tolerated_clearance_m(
        SQUARE, [_box("o_a", (2.5, 1.0), size=(4.2, 0.6))],
        (2.5, 3.5), (2.5, 0.0), 0.6, upper,
    )
    assert 0.0 < pinched < upper


def test_analysis_is_deterministic(thresholds) -> None:
    home = _blocked_home()
    first = analyze_obstructions(home, thresholds)
    second = analyze_obstructions(home, thresholds)
    assert first == second
