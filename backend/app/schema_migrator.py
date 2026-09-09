from typing import Any
import copy

CURRENT_VERSION = "2.1"

def _as_tuple(version: str) -> tuple[int, ...]:
    """Compare versions numerically, not lexically.

    A plain string compare gets this wrong in the one direction that matters:
    "10.0" > "2.0" is False, so a document from a far-future build would fall past
    the "too new to read" guard and into the migration path, failing later with a
    confusing "no upgrade path" instead of the honest message. Swift's
    SchemaMigrator already compares component-wise; this brings Python in line.
    Unparseable components sort as -1 so a malformed version is never "newer".
    """
    parts = []
    for chunk in version.split("."):
        try:
            parts.append(int(chunk))
        except ValueError:
            parts.append(-1)
    return tuple(parts)


def migrate(data: Any) -> Any:
    """Migrates a home document to the current schema version."""
    if not isinstance(data, dict):
        return data
        
    version = data.get("schema_version")
    if not version:
        raise ValueError("The document has no schema_version and cannot be read safely.")
        
    if version == CURRENT_VERSION:
        return data
        
    if _as_tuple(version) > _as_tuple(CURRENT_VERSION):
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

    # 2.0 -> 2.1: adds FloorObject.elevation_m (default 0) and .mounted (default
    # False), plus four ObjectCategory values. Every addition is defaulted and no
    # existing field changed meaning, so the stamp is the whole migration.
    if current == "2.0":
        migrated["schema_version"] = "2.1"
        current = "2.1"

    if current != CURRENT_VERSION:
        raise ValueError(f"No upgrade path from home format {version} to {CURRENT_VERSION}.")
        
    return migrated
