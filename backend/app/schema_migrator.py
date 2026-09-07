from typing import Any
import copy

CURRENT_VERSION = "2.0"

def migrate(data: Any) -> Any:
    """Migrates a home document to the current schema version."""
    if not isinstance(data, dict):
        return data
        
    version = data.get("schema_version")
    if not version:
        raise ValueError("The document has no schema_version and cannot be read safely.")
        
    if version == CURRENT_VERSION:
        return data
        
    if version > CURRENT_VERSION:
        raise ValueError(
            f"This home was saved by a newer version of Escape Plan "
            f"(format {version}; this app reads {CURRENT_VERSION})."
        )
        
    migrated = copy.deepcopy(data)
    current = version
    
    # 1.0 -> 1.1
    if current == "1.0":
        migrated["schema_version"] = "1.1"
        current = "1.1"
        
    # 1.1 -> 2.0
    if current == "1.1":
        migrated["schema_version"] = "2.0"
        current = "2.0"
        
    if current != CURRENT_VERSION:
        raise ValueError(f"No upgrade path from home format {version} to {CURRENT_VERSION}.")
        
    return migrated
