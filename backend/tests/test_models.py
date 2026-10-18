"""S0.2 tests: HomeModel pydantic invariants + fixture validity (schema AND pydantic)."""

from __future__ import annotations

import json

import jsonschema
import pytest
from pydantic import ValidationError

from app.models import HomeModel
from app.validate import validate_file
from tests.conftest import FIXTURES_DIR, SCHEMA_PATH, load_fixture

VALID_FIXTURES = ["bungalow.json", "apartment.json", "twostory.json", "anishas-house.json"]
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


def test_happy_path_s6_1_fields(twostory: dict, apartment: dict) -> None:
    # twostory has safety_points and household
    model = HomeModel.model_validate(twostory)
    assert model.household is not None
    assert model.household.tenure == "rent"
    assert model.household.existing_equipment == []
    
    assert len(model.floors[0].safety_points) == 2
    sp = model.floors[0].safety_points[0]
    assert sp.id == "sp_gas"
    assert sp.kind == "gas_shutoff"
    
    # apartment has secured objects
    model_apt = HomeModel.model_validate(apartment)
    secure_objs = [obj for f in model_apt.floors for obj in f.objects if obj.secured]
    assert len(secure_objs) > 0
    assert secure_objs[0].id == "obj_wardrobe_1"



# ---------------------------------------------------------------------------
# Ported from `my-s6-1-and-policy` 2026-09-16
# ---------------------------------------------------------------------------
#
# These invariants were written alongside the schema-2.0 fields they guard and
# then stranded on an unmerged branch — the worst place for a contract test,
# because the behaviour shipped without them. Only the seeding-INDEPENDENT ones
# are ported: the branch also carried assertions about which fixture has which
# household, and that seeding was superseded on 2026-09-16 (see
# `test_fixture_coverage.py`, which pins the current decision instead).


def _bungalow() -> dict:
    return load_fixture("bungalow.json")


def test_the_apps_bundled_fixtures_match_the_contracts() -> None:
    """`escape_plan/Fixtures/*.json` are byte-identical copies of
    `schema/fixtures/`, bundled into the iOS app because it cannot reach outside
    its own bundle. The copies are the deliberate design; this test is what makes
    them safe.

    It earned its keep the moment it landed: porting it on 2026-09-16 immediately
    caught `apartment.json` and `jagged.json` drifting, because the fixture
    seeding done earlier the same day had updated `schema/fixtures/` and nothing
    on main knew the copies existed.
    """
    from tests.conftest import REPO_ROOT

    bundled = REPO_ROOT / "escape_plan" / "Fixtures"
    assert bundled.is_dir(), "the app's bundled fixture directory has moved"
    names = sorted(p.name for p in bundled.glob("*.json"))
    assert names, "no bundled fixtures found"
    for name in names:
        source = FIXTURES_DIR / name
        assert source.exists(), f"{name} is bundled but is gone from schema/fixtures/"
        assert bundled.joinpath(name).read_bytes() == source.read_bytes(), (
            f"escape_plan/Fixtures/{name} has drifted from schema/fixtures/{name}. "
            "Re-copy it; do not hand-edit the bundled copy."
        )


def test_an_unsupported_schema_version_is_refused_loudly() -> None:
    """The branch this came from matched on "unsupported schema_version"; since
    then the message became something a person can act on. Assert the property
    that actually matters — it names BOTH versions, so a user who opens a home
    saved by a newer build learns which one they need rather than seeing a
    validation dump."""
    with pytest.raises(ValidationError) as caught:
        HomeModel.model_validate(_bungalow() | {"schema_version": "3.0"})
    message = str(caught.value)
    assert "3.0" in message and "2.1" in message, message
    assert "newer version" in message


def test_safety_point_ids_are_unique_against_every_other_entity() -> None:
    """Not merely unique among safety points — they join the global id pass, so a
    collision with a ROOM id is caught too."""
    doc = _bungalow()
    room_id = doc["floors"][0]["rooms"][0]["id"]
    doc["floors"][0]["safety_points"] = [
        {"id": room_id, "kind": "gas_shutoff", "position": [1.0, 1.0], "source": "manual"}
    ]
    with pytest.raises(ValidationError, match="duplicate id"):
        HomeModel.model_validate(doc)


def test_unknown_safety_point_kind_is_rejected() -> None:
    doc = _bungalow()
    doc["floors"][0]["safety_points"] = [
        {"id": "sp_x", "kind": "nuclear_shutoff", "position": [1.0, 1.0], "source": "manual"}
    ]
    with pytest.raises(ValidationError):
        HomeModel.model_validate(doc)


def test_scan_derived_safety_point_must_carry_confidence() -> None:
    """SafetyPoint inherits the provenance rule: machine-derived items carry a
    confidence, so the editor can flag them for review rather than silently
    trusting them."""
    doc = _bungalow()
    doc["floors"][0]["safety_points"] = [
        {"id": "sp_scan", "kind": "gas_shutoff", "position": [1.0, 1.0], "source": "scan"}
    ]
    with pytest.raises(ValidationError, match="must carry a confidence"):
        HomeModel.model_validate(doc)


def test_unknown_equipment_is_rejected() -> None:
    with pytest.raises(ValidationError):
        HomeModel.model_validate(
            _bungalow() | {"household": {"existing_equipment": ["moat"]}}
        )


def test_household_is_optional_and_a_skipped_interview_is_valid() -> None:
    """Skipping every question must produce a valid home, not a half-written one."""
    assert HomeModel.model_validate(_bungalow()).household is None
    empty = HomeModel.model_validate(_bungalow() | {"household": {}})
    assert empty.household is not None
    assert empty.household.tenure is None, "unanswered tenure is None, never 'own'"
    assert empty.household.existing_equipment == []


def test_secured_defaults_to_false() -> None:
    home = HomeModel.model_validate(load_fixture("bungalow-blocked.json"))
    assert all(not o.secured for f in home.floors for o in f.objects)


def test_what_pydantic_serializes_validates_against_the_schema() -> None:
    """The contract has to accept what the backend actually EMITS, not merely
    what the fixtures happen to contain.

    pydantic writes an unanswered household as an explicit `"household": null`,
    and a bare `$ref` to an object type rejects null — so v2.0 shipped, briefly,
    a contract its own serializer violated. `household` is therefore declared
    nullable, matching `meta.address_optional` and `meta.last_scanned`.

    Scoped to `household` on purpose: `confidence: null` and `egress: null` have
    the same shape and predate this work (the endpoints paper over them with
    `response_model_exclude_none=True`). Widening it to the whole document is a
    separate decision, tracked rather than smuggled in here.
    """
    schema = json.loads(SCHEMA_PATH.read_text())
    validator = jsonschema.Draft202012Validator(schema)

    for name in ("bungalow.json", "apartment.json"):
        home = HomeModel.model_validate(load_fixture(name))
        emitted = json.loads(home.model_dump_json())
        household_errors = [
            e
            for e in validator.iter_errors(emitted)
            if "household" in "/".join(str(p) for p in e.path)
        ]
        assert not household_errors, (
            f"{name}: pydantic emits a household the schema rejects — "
            f"{[e.message for e in household_errors]}"
        )
