import pytest
from app.schema_migrator import migrate
from app.models import HomeModel
import copy
import json

def test_migrate_1_1_to_2_0(bungalow: dict):
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
    
    # Assert
    assert migrated["schema_version"] == "2.0"
    
    # And it should successfully parse as HomeModel now
    model = HomeModel.model_validate(migrated)
    assert model.schema_version == "2.0"
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
