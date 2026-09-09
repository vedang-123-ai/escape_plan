import pytest
from app.schema_migrator import migrate, CURRENT_VERSION
from app.models import HomeModel
import copy
import json

def test_migrate_1_1_walks_all_the_way_to_current(bungalow: dict):
    data = bungalow
        
    # Artificially degrade it to 1.1
    data["schema_version"] = "1.1"
    if "household" in data:
        del data["household"]
    for floor in data["floors"]:
        if "safety_points" in floor:
            del floor["safety_points"]
        for obj in floor.get("objects", []):
            if "secured" in obj:
                del obj["secured"]
                
    # Migrate
    migrated = migrate(data)
    
    # Assert — a 1.1 document walks every step, not just the first one.
    assert migrated["schema_version"] == CURRENT_VERSION

    # And it should successfully parse as HomeModel now
    model = HomeModel.model_validate(migrated)
    assert model.schema_version == CURRENT_VERSION
    assert model.household is None
    for floor in model.floors:
        assert floor.safety_points == []
        for obj in floor.objects:
            assert obj.secured is False


def test_a_far_future_version_is_refused_as_too_new_not_as_a_missing_path() -> None:
    """Regression: the guard used a string compare, so "10.0" > "2.0" was False and a
    far-future document fell past "too new" into the migration path, failing later with
    a confusing "no upgrade path". Swift's SchemaMigrator already compared numerically."""
    import pytest as _pytest

    for version in ["3.0", "10.0", "2.10"]:
        with _pytest.raises(ValueError, match="newer version"):
            migrate({"schema_version": version})


def test_migrate_2_0_to_2_1_stamps_forward_and_defaults_the_new_object_fields(
    bungalow: dict,
) -> None:
    """A hand-written 2.0 document — no elevation_m, no mounted anywhere — must load
    and come out as 2.1 with the v2.1 fields at the values that preserve its meaning."""
    data = copy.deepcopy(bungalow)
    data["schema_version"] = "2.0"
    data["floors"][0]["objects"] = [
        {
            "id": "o_hand_written",
            "category": "wardrobe",
            "center": [1.0, 1.0],
            "size_m": [1.0, 0.6],
            "height_m": 2.0,
            "source": "manual",
        }
    ]

    migrated = migrate(data)
    assert migrated["schema_version"] == "2.1"

    model = HomeModel.model_validate(migrated)
    obj = model.floors[0].objects[0]
    # 0 / False are the values that mean "exactly what this object meant under 2.0".
    assert obj.elevation_m == 0.0
    assert obj.mounted is False
    assert obj.secured is False


def test_the_four_new_categories_are_accepted_and_the_old_seven_still_are(
    bungalow: dict,
) -> None:
    data = copy.deepcopy(bungalow)
    categories = ["bed", "sofa", "table", "wardrobe", "appliance", "storage", "other",
                  "bookcase", "tv", "water_heater", "heat_source"]
    data["floors"][0]["objects"] = [
        {
            "id": f"o_cat_{name}",
            "category": name,
            "center": [1.0 + i * 0.01, 1.0],
            "size_m": [0.4, 0.4],
            "height_m": 1.0,
            "source": "manual",
        }
        for i, name in enumerate(categories)
    ]
    model = HomeModel.model_validate(data)
    assert [o.category.value for o in model.floors[0].objects] == categories


@pytest.mark.parametrize(
    "override, message",
    [
        ({"elevation_m": -0.1}, "elevation_m"),
        ({"category": "trampoline"}, "category"),
    ],
)
def test_negative_validation_on_the_new_fields(
    bungalow: dict, override: dict, message: str
) -> None:
    data = copy.deepcopy(bungalow)
    obj = {
        "id": "o_bad",
        "category": "bookcase",
        "center": [1.0, 1.0],
        "size_m": [0.8, 0.3],
        "height_m": 1.9,
        "source": "manual",
    }
    obj.update(override)
    data["floors"][0]["objects"] = [obj]
    with pytest.raises(Exception, match=message):
        HomeModel.model_validate(data)


def test_a_scan_derived_object_in_a_new_category_still_needs_confidence(
    bungalow: dict,
) -> None:
    """The v1.1 provenance rule is not category-aware and must not become so: a
    scan-sourced bookcase without a confidence is as invalid as a scan-sourced wardrobe."""
    data = copy.deepcopy(bungalow)
    data["floors"][0]["objects"] = [
        {
            "id": "o_scan_bookcase",
            "category": "bookcase",
            "center": [1.0, 1.0],
            "size_m": [0.8, 0.3],
            "height_m": 1.9,
            "source": "scan",
        }
    ]
    with pytest.raises(Exception, match="confidence"):
        HomeModel.model_validate(data)
