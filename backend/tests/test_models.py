"""S0.2 tests: HomeModel pydantic invariants + fixture validity (schema AND pydantic)."""

from __future__ import annotations

import json

import jsonschema
import pytest
from pydantic import ValidationError

from app.models import HomeModel
from app.validate import validate_file
from tests.conftest import FIXTURES_DIR, SCHEMA_PATH, load_fixture

VALID_FIXTURES = ["bungalow.json", "apartment.json", "twostory.json"]
INVALID_FIXTURES = {
    "invalid/bad-room-ref.json": "does not exist on floor",
    "invalid/cw-polygon.json": "counter-clockwise",
    "invalid/duplicate-ids.json": "duplicate id",
}


# --- fixtures validate (acceptance) ---------------------------------------

@pytest.mark.parametrize("name", VALID_FIXTURES)
def test_fixture_passes_pydantic(name: str) -> None:
    HomeModel.model_validate(load_fixture(name))


@pytest.mark.parametrize("name", VALID_FIXTURES)
def test_fixture_passes_jsonschema(name: str) -> None:
    schema = json.loads(SCHEMA_PATH.read_text())
    jsonschema.Draft202012Validator(schema).validate(load_fixture(name))


@pytest.mark.parametrize("name", VALID_FIXTURES)
def test_fixture_passes_cli(name: str) -> None:
    assert validate_file(FIXTURES_DIR / name, SCHEMA_PATH) == []


# --- broken fixtures fail with a clear message (acceptance) ----------------

@pytest.mark.parametrize("name,expected", INVALID_FIXTURES.items())
def test_broken_fixture_fails_clearly(name: str, expected: str) -> None:
    errors = validate_file(FIXTURES_DIR / name, SCHEMA_PATH)
    assert errors, f"{name} unexpectedly validated"
    assert any(expected in e for e in errors), (
        f"{name}: expected message containing {expected!r}, got {errors}"
    )


# --- targeted invariant tests ----------------------------------------------

def _mutate(base: dict, fn) -> dict:
    doc = json.loads(json.dumps(base))
    fn(doc)
    return doc


def test_round_trip_semantic_equality(twostory: dict) -> None:
    """Decode → encode → decode must be a fixed point (Swift mirror does the same)."""
    model = HomeModel.model_validate(twostory)
    dumped = model.model_dump(mode="json", by_alias=True, exclude_none=True)
    again = HomeModel.model_validate(dumped)
    assert model == again


def test_stairs_from_alias_round_trip(twostory: dict) -> None:
    model = HomeModel.model_validate(twostory)
    dumped = model.model_dump(mode="json", by_alias=True)
    assert "from" in dumped["stairs"][0]
    assert "from_" not in dumped["stairs"][0]


def test_self_intersecting_polygon_rejected(bungalow: dict) -> None:
    doc = _mutate(
        bungalow,
        lambda d: d["floors"][0]["rooms"][0].__setitem__(
            "polygon", [[0, 0], [4, 4], [4, 0], [0, 4]]
        ),
    )
    with pytest.raises(ValidationError, match="self-intersecting"):
        HomeModel.model_validate(doc)


def test_exterior_reserved_as_room_id(bungalow: dict) -> None:
    doc = _mutate(
        bungalow, lambda d: d["floors"][0]["rooms"][0].__setitem__("id", "EXTERIOR")
    )
    with pytest.raises(ValidationError, match="reserved"):
        HomeModel.model_validate(doc)


def test_scan_source_requires_confidence(bungalow: dict) -> None:
    def fn(d: dict) -> None:
        d["floors"][0]["rooms"][0]["source"] = "scan"
    with pytest.raises(ValidationError, match="confidence"):
        HomeModel.model_validate(_mutate(bungalow, fn))


def test_bad_t_range_rejected(bungalow: dict) -> None:
    def fn(d: dict) -> None:
        ws = d["floors"][0]["openings"][0]["wall_segment"]
        ws["t0"], ws["t1"] = 0.6, 0.4
    with pytest.raises(ValidationError, match="t0 .* must be < t1"):
        HomeModel.model_validate(_mutate(bungalow, fn))


def test_edge_index_out_of_range_rejected(bungalow: dict) -> None:
    def fn(d: dict) -> None:
        d["floors"][0]["openings"][0]["wall_segment"]["edge_index"] = 7
    with pytest.raises(ValidationError, match="out of range"):
        HomeModel.model_validate(_mutate(bungalow, fn))


def test_wall_segment_host_must_be_in_room_ids(bungalow: dict) -> None:
    def fn(d: dict) -> None:
        d["floors"][0]["openings"][0]["wall_segment"]["room_id"] = "r_bath"
    with pytest.raises(ValidationError, match="must be one of room_ids"):
        HomeModel.model_validate(_mutate(bungalow, fn))


def test_double_exterior_opening_rejected(bungalow: dict) -> None:
    def fn(d: dict) -> None:
        d["floors"][0]["openings"][0]["room_ids"] = ["EXTERIOR", "EXTERIOR"]
    with pytest.raises(ValidationError):
        HomeModel.model_validate(_mutate(bungalow, fn))


def test_stairs_same_floor_rejected(twostory: dict) -> None:
    def fn(d: dict) -> None:
        d["stairs"][0]["to"]["floor_id"] = "f1"
        d["stairs"][0]["to"]["room_id"] = "r_kitchen"
    with pytest.raises(ValidationError, match="different floors"):
        HomeModel.model_validate(_mutate(twostory, fn))


def test_stairs_dangling_room_rejected(twostory: dict) -> None:
    def fn(d: dict) -> None:
        d["stairs"][0]["to"]["room_id"] = "r_nowhere"
    with pytest.raises(ValidationError, match="does not\n?.*exist on floor|does not exist on floor"):
        HomeModel.model_validate(_mutate(twostory, fn))


def test_profile_dangling_bedroom_rejected(twostory: dict) -> None:
    def fn(d: dict) -> None:
        d["profiles"][0]["bedroom_room_id"] = "r_nowhere"
    with pytest.raises(ValidationError, match="does not reference an existing room"):
        HomeModel.model_validate(_mutate(twostory, fn))


def test_duplicate_floor_levels_rejected(twostory: dict) -> None:
    def fn(d: dict) -> None:
        d["floors"][1]["level"] = 0
    with pytest.raises(ValidationError, match="levels must be unique"):
        HomeModel.model_validate(_mutate(twostory, fn))


def test_unknown_field_rejected(bungalow: dict) -> None:
    doc = _mutate(bungalow, lambda d: d.__setitem__("surprise", 1))
    with pytest.raises(ValidationError):
        HomeModel.model_validate(doc)


def test_is_exit_helper(bungalow: dict) -> None:
    model = HomeModel.model_validate(bungalow)
    by_id = {o.id: o for o in model.floors[0].openings}
    assert by_id["d_front"].is_exit
    assert not by_id["d_living_kitchen"].is_exit

def test_safety_point_id_must_be_unique(twostory: dict) -> None:
    def fn(d: dict) -> None:
        if "safety_points" not in d["floors"][0]:
            d["floors"][0]["safety_points"] = []
        d["floors"][0]["safety_points"].extend([
            {"id": "sp1", "kind": "gas_shutoff", "position": [1, 1], "source": "manual"},
            {"id": "sp1", "kind": "water_shutoff", "position": [2, 2], "source": "manual"}
        ])
    with pytest.raises(ValidationError, match="duplicate id"):
        HomeModel.model_validate(_mutate(twostory, fn))

def test_unknown_tenure_rejected(twostory: dict) -> None:
    def fn(d: dict) -> None:
        d["household"] = {"tenure": "squatting"}
    with pytest.raises(ValidationError):
        HomeModel.model_validate(_mutate(twostory, fn))

def test_duplicate_equipment_rejected(twostory: dict) -> None:
    def fn(d: dict) -> None:
        d["household"] = {"existing_equipment": ["smoke_alarm", "smoke_alarm"]}
    with pytest.raises(ValidationError):
        HomeModel.model_validate(_mutate(twostory, fn))

def test_safety_point_position_finite(twostory: dict) -> None:
    def fn(d: dict) -> None:
        if "safety_points" not in d["floors"][0]:
            d["floors"][0]["safety_points"] = []
        d["floors"][0]["safety_points"].append(
            {"id": "sp_inf", "kind": "gas_shutoff", "position": [float('inf'), 1], "source": "manual"}
        )
    with pytest.raises(ValidationError, match="must be finite"):
        HomeModel.model_validate(_mutate(twostory, fn))

