"""Revamp C1 tests: the pure construction-action layer the LLM builder drives.

Rejection paths matter most here — a rejected action is the model's feedback
loop, so every rejection must be loud, specific, and leave the draft usable.
"""

from __future__ import annotations

import pytest

from app.builder import actions
from app.builder.actions import ActionError
from app.models import EXTERIOR_ID, HomeModel
from app.schema_migrator import CURRENT_VERSION

NOW = "2026-07-23T12:00:00Z"


def _draft():
    d = actions.new_draft("Test Home", "11111111-2222-3333-4444-555555555555", NOW)
    actions.add_floor(d, floor_id="f1", level=0, name="Ground Floor")
    return d


def _square(x0, y0, w, h):
    return [[x0, y0], [x0 + w, y0], [x0 + w, y0 + h], [x0, y0 + h]]


def _two_room_draft():
    d = _draft()
    actions.add_room(d, room_id="r1", floor_id="f1", name="Living", type="living",
                     polygon=_square(0, 0, 5, 4))
    actions.add_room(d, room_id="r2", floor_id="f1", name="Kitchen", type="kitchen",
                     polygon=_square(5, 0, 4, 4))
    return d


# ---------------------------------------------------------------------------
# Provenance + validity


def test_everything_created_is_stamped_ai_plan_with_confidence():
    d = _two_room_draft()
    actions.add_opening(d, opening_id="o1", kind="door", room_id="r1", edge_index=0, t=0.5)
    actions.add_object(d, object_id="ob1", floor_id="f1", category="sofa",
                       center=[2.5, 2.0], size_m=[2.0, 0.9], height_m=0.8)
    assert actions.validate_draft(d) == []
    home = HomeModel.model_validate(d)
    for floor in home.floors:
        for entity in [*floor.rooms, *floor.openings, *floor.objects]:
            assert entity.source.value == "ai_plan"
            assert entity.confidence == actions.AI_CONFIDENCE


def test_clockwise_polygon_is_normalized_not_rejected():
    d = _draft()
    cw = list(reversed(_square(0, 0, 3, 3)))
    actions.add_room(d, room_id="r1", floor_id="f1", name="Room", type="other", polygon=cw)
    assert actions.validate_draft(d) == []


# ---------------------------------------------------------------------------
# Openings: adjacency + span (the one bit of editor logic re-expressed)


def test_door_on_shared_wall_derives_interior():
    d = _two_room_draft()
    # r1's edge 1 runs (5,0) → (5,4): shared with r2's edge 3.
    result = actions.add_opening(d, opening_id="o1", kind="door", room_id="r1",
                                 edge_index=1, t=0.5)
    assert sorted(result["connects"]) == ["r1", "r2"]
    assert result["is_exit"] is False


def test_door_on_outside_wall_derives_exterior_exit():
    d = _two_room_draft()
    result = actions.add_opening(d, opening_id="o1", kind="door", room_id="r1",
                                 edge_index=0, t=0.4)
    assert EXTERIOR_ID in result["connects"]
    assert result["is_exit"] is True


def test_opening_span_slides_inward_instead_of_overhanging():
    d = _two_room_draft()
    actions.add_opening(d, opening_id="o1", kind="door", room_id="r1", edge_index=0, t=0.0)
    opening = d["floors"][0]["openings"][0]
    assert opening["wall_segment"]["t0"] == pytest.approx(0.0)
    assert opening["wall_segment"]["t1"] == pytest.approx(0.9 / 5.0)
    assert actions.validate_draft(d) == []


def test_opening_on_too_short_wall_is_rejected_with_dimensions():
    d = _draft()
    actions.add_room(d, room_id="tiny", floor_id="f1", name="Closet", type="other",
                     polygon=_square(0, 0, 0.5, 0.5))
    with pytest.raises(ActionError, match="too short"):
        actions.add_opening(d, opening_id="o1", kind="door", room_id="tiny",
                            edge_index=0, t=0.5)


def test_window_defaults_differ_from_door_defaults():
    d = _two_room_draft()
    actions.add_opening(d, opening_id="w1", kind="window", room_id="r1", edge_index=3, t=0.5)
    window = d["floors"][0]["openings"][0]
    assert window["sill_height_m"] == pytest.approx(0.8)
    assert window["height_m"] == pytest.approx(1.2)


# ---------------------------------------------------------------------------
# Stairs, deletes, rejections


def test_stairs_require_different_floors_and_order_by_level():
    d = _two_room_draft()
    with pytest.raises(ActionError, match="DIFFERENT floors"):
        actions.add_stairs(d, stairs_id="s1", from_room_id="r1", to_room_id="r2")

    actions.add_floor(d, floor_id="f2", level=1, name="Upstairs")
    actions.add_room(d, room_id="r3", floor_id="f2", name="Landing", type="hall",
                     polygon=_square(0, 0, 3, 3))
    # Passed upper-first: the action reorders so `from` is the lower floor.
    actions.add_stairs(d, stairs_id="s1", from_room_id="r3", to_room_id="r1")
    stair = d["stairs"][0]
    assert stair["from"]["floor_id"] == "f1"
    assert stair["to"]["floor_id"] == "f2"
    assert actions.validate_draft(d) == []


def test_duplicate_and_reserved_ids_are_rejected():
    d = _two_room_draft()
    with pytest.raises(ActionError, match="already taken"):
        actions.add_room(d, room_id="r1", floor_id="f1", name="Dup", type="other",
                         polygon=_square(20, 20, 2, 2))
    with pytest.raises(ActionError, match="reserved"):
        actions.add_room(d, room_id=EXTERIOR_ID, floor_id="f1", name="X", type="other",
                         polygon=_square(20, 20, 2, 2))


def test_delete_room_cascades_openings_and_stairs():
    d = _two_room_draft()
    actions.add_opening(d, opening_id="o1", kind="door", room_id="r1", edge_index=1, t=0.5)
    actions.add_floor(d, floor_id="f2", level=1, name="Up")
    actions.add_room(d, room_id="r3", floor_id="f2", name="Land", type="hall",
                     polygon=_square(0, 0, 3, 3))
    actions.add_stairs(d, stairs_id="s1", from_room_id="r1", to_room_id="r3")

    actions.delete(d, entity_id="r1")
    assert d["floors"][0]["openings"] == []
    assert d["stairs"] == []
    assert actions.validate_draft(d) == []


def test_delete_unknown_id_is_rejected():
    with pytest.raises(ActionError, match="no entity"):
        actions.delete(_draft(), entity_id="ghost")


# ---------------------------------------------------------------------------
# Validation feedback


def test_validate_draft_reports_actionable_errors():
    d = _draft()  # a floor with zero rooms violates the schema
    errors = actions.validate_draft(d)
    assert errors, "an empty floor must not validate"
    assert any("rooms" in e for e in errors)


def test_validate_empty_draft_points_at_add_floor():
    d = actions.new_draft("Empty", "11111111-2222-3333-4444-555555555555", NOW)
    assert actions.validate_draft(d) == ["the home has no floors yet — add_floor first"]


def test_new_draft_stamps_the_version_pydantic_actually_accepts():
    """A draft stamped with any other version is rejected the moment it validates.

    This guards the seam that failed the 2026-09-19 deploy: actions.py and
    models.py each carried their own idea of the current schema version, and
    nothing asserted they agreed.
    """
    d = actions.new_draft("V", "11111111-2222-3333-4444-555555555555", NOW)
    accepted = HomeModel.model_fields["schema_version"].annotation.__args__
    assert d["schema_version"] == CURRENT_VERSION
    assert CURRENT_VERSION in accepted
