from app.models import FloorObject, Room, Floor
from app.routing.nav_grid import objects_intersecting
from typing import Optional

def find_cover_object(floor: Floor, room: Room) -> Optional[FloorObject]:
    """Find the nearest sturdy object to get under in a room.
    
    Qualifying objects are limited to `table` (and desk-like storage, though none
    are currently supported by the schema). Sofas do not count as cover,
    and wardrobes are hazards. Grounded in S6.2 corpus [cite: shakeout-guidance].
    """
    local = objects_intersecting(list(room.polygon), list(floor.objects))
    qualifying = [obj for obj in local if obj.category == "table"]
    if not qualifying:
        return None
    import math
    cx = sum(p[0] for p in room.polygon) / len(room.polygon)
    cy = sum(p[1] for p in room.polygon) / len(room.polygon)
    
    def dist(obj: FloorObject) -> float:
        return math.hypot(obj.center[0] - cx, obj.center[1] - cy)
        
    return min(qualifying, key=dist)
