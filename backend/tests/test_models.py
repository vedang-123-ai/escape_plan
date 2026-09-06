"""S0.2 tests: HomeModel pydantic invariants + fixture validity (schema AND pydantic)."""

from __future__ import annotations

import json

import jsonschema
import pytest
from pydantic import ValidationError

from app.models import SCHEMA_VERSION, HomeModel
from app.validate import validate_file
from tests.conftest import FIXTURES_DIR, SCHEMA_PATH, load_fixture

# All six. jagged/bungalow-blocked/bungalow-narrow were never asserted against the JSON
# Schema before S6.1 — only against pydantic, incidentally, via the obstruction tests.
VALID_FIXTURES = [
    "bungalow.json",
    "apartment.json",
    "twostory.json",
    "jagged.json",
    "bungalow-blocked.json",
    "bungalow-narrow.json",
]
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


# --- v2.0 contract additions (S6.1) ---------------------------------------

def _bungalow() -> dict:
    return load_fixture("bungalow.json")


def test_a_1_1_document_still_loads_and_is_normalized() -> None:
    """The backward-compatibility ruling: every 2.0 addition is optional, so a 1.1
    document is a structurally valid 2.0 document. It loads and is stamped 2.0 in
    memory; nothing is rewritten on disk."""
    doc = _bungalow() | {"schema_version": "1.1"}
    assert HomeModel.model_validate(doc).schema_version == SCHEMA_VERSION


def test_an_unsupported_schema_version_is_refused_loudly() -> None:
    with pytest.raises(ValidationError, match="unsupported schema_version"):
        HomeModel.model_validate(_bungalow() | {"schema_version": "3.0"})


def test_safety_point_ids_are_unique_against_every_other_entity() -> None:
    """Not merely unique among safety points — they join the global claim() pass, so a
    collision with a ROOM id is caught too."""
    doc = _bungalow()
    room_id = doc["floors"][0]["rooms"][0]["id"]
    doc["floors"][0]["safety_points"] = [
        {"id": room_id, "kind": "gas_shutoff", "position": [1.0, 1.0], "source": "manual"}
    ]
    with pytest.raises(ValidationError, match="duplicate id"):
        HomeModel.model_validate(doc)


def test_duplicate_safety_point_ids_are_rejected() -> None:
    doc = _bungalow()
    doc["floors"][0]["safety_points"] = [
        {"id": "sp_dup", "kind": "gas_shutoff", "position": [1.0, 1.0], "source": "manual"},
        {"id": "sp_dup", "kind": "water_shutoff", "position": [2.0, 2.0], "source": "manual"},
    ]
    with pytest.raises(ValidationError, match="duplicate id"):
        HomeModel.model_validate(doc)


@pytest.mark.parametrize("bad", [float("nan"), float("inf"), float("-inf")])
def test_non_finite_safety_point_positions_are_rejected(bad: float) -> None:
    """JSON Schema's "number" admits NaN/Infinity once a parser has produced them; a
    non-finite landmark would reach the renderer as an invisible failure."""
    doc = _bungalow()
    doc["floors"][0]["safety_points"] = [
        {"id": "sp_bad", "kind": "gas_shutoff", "position": [bad, 1.0], "source": "manual"}
    ]
    with pytest.raises(ValidationError, match="must be finite"):
        HomeModel.model_validate(doc)


def test_unknown_safety_point_kind_is_rejected() -> None:
    doc = _bungalow()
    doc["floors"][0]["safety_points"] = [
        {"id": "sp_x", "kind": "nuclear_shutoff", "position": [1.0, 1.0], "source": "manual"}
    ]
    with pytest.raises(ValidationError):
        HomeModel.model_validate(doc)


def test_scan_derived_safety_point_must_carry_confidence() -> None:
    """SafetyPoint inherits the provenance rule: machine-derived items carry confidence."""
    doc = _bungalow()
    doc["floors"][0]["safety_points"] = [
        {"id": "sp_scan", "kind": "gas_shutoff", "position": [1.0, 1.0], "source": "scan"}
    ]
    with pytest.raises(ValidationError, match="must carry a confidence"):
        HomeModel.model_validate(doc)


def test_unknown_tenure_is_rejected() -> None:
    with pytest.raises(ValidationError):
        HomeModel.model_validate(_bungalow() | {"household": {"tenure": "leasehold"}})


def test_unknown_equipment_is_rejected() -> None:
    with pytest.raises(ValidationError):
        HomeModel.model_validate(
            _bungalow() | {"household": {"existing_equipment": ["moat"]}}
        )


def test_duplicate_equipment_is_rejected() -> None:
    with pytest.raises(ValidationError, match="duplicate existing_equipment"):
        HomeModel.model_validate(
            _bungalow()
            | {"household": {"existing_equipment": ["smoke_alarm", "smoke_alarm"]}}
        )


def test_household_is_optional_and_a_skipped_interview_is_valid() -> None:
    """Skipping every question must produce a valid home, not a half-written one."""
    assert HomeModel.model_validate(_bungalow()).household is None
    empty = HomeModel.model_validate(_bungalow() | {"household": {}})
    assert empty.household is not None
    assert empty.household.tenure is None, "unanswered tenure is None, never 'own'"
    assert empty.household.existing_equipment == []


def test_secured_defaults_to_false_and_last_scanned_to_none() -> None:
    home = HomeModel.model_validate(load_fixture("bungalow-blocked.json"))
    assert all(not o.secured for f in home.floors for o in f.objects)
    assert HomeModel.model_validate(_bungalow()).meta.last_scanned is not None, (
        "bungalow is seeded with a deliberately stale scan date"
    )
    assert HomeModel.model_validate(load_fixture("apartment.json")).meta.last_scanned is None, (
        "never-scanned is a distinct state from stale and must stay representable"
    )


def test_seeded_fixture_data_is_where_downstream_sessions_expect_it() -> None:
    """S6.4 and S6.6 are written against these exact cases; pin them."""
    apartment = HomeModel.model_validate(load_fixture("apartment.json"))
    assert apartment.household is not None
    assert apartment.household.tenure.value == "rent"
    assert "smoke_alarm" in [e.value for e in apartment.household.existing_equipment]

    twostory = HomeModel.model_validate(load_fixture("twostory.json"))
    assert twostory.household is not None and twostory.household.tenure.value == "own"
    kinds = {sp.kind.value for f in twostory.floors for sp in f.safety_points}
    assert kinds == {"gas_shutoff", "electrical_panel"}

    jagged = HomeModel.model_validate(load_fixture("jagged.json"))
    assert any(o.secured for f in jagged.floors for o in f.objects)
    assert any("hearing_impaired" in [t.value for t in p.tags] for p in jagged.profiles)


def test_the_apps_bundled_fixtures_match_the_contracts() -> None:
    """escape_plan/Fixtures/*.json are byte-identical copies of schema/fixtures/, bundled
    into the iOS app. Nothing guarded that before S6.1, and they went silently stale the
    moment the contract moved — the app would have shipped v1.1 homes against a v2.0
    build. Copies are the deliberate design (the app cannot reach outside its bundle);
    this test is what makes the copies safe."""
    from tests.conftest import REPO_ROOT

    bundled = REPO_ROOT / "escape_plan" / "Fixtures"
    assert bundled.is_dir(), "the app's bundled fixture directory has moved"
    names = sorted(p.name for p in bundled.glob("*.json"))
    assert names, "no bundled fixtures found"
    for name in names:
        source = FIXTURES_DIR / name
        assert source.exists(), f"{name} is bundled but no longer exists in schema/fixtures/"
        assert bundled.joinpath(name).read_bytes() == source.read_bytes(), (
            f"escape_plan/Fixtures/{name} has drifted from schema/fixtures/{name}. "
            "Re-copy it; do not hand-edit the bundled copy."
        )
