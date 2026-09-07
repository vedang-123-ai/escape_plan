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
