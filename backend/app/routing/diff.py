import math
from typing import Sequence, Optional
from pydantic import BaseModel
from app.models import HomeModel, FloorObject, Room, EXTERIOR_ID
from app.routing.obstructions import Obstruction
from app.routing.egress import EgressThresholds
from app.routing.obstructions import culprit_object_ids, tolerated_clearance_m, _suggested_move_m, COMFORT_MARGIN_M, _room_openings, code_clearance_m, opening_midpoint, _reachable, objects_intersecting, polygon_centroid
from app.routing.graph import Point

class DiffRequest(BaseModel):
    stored_model: HomeModel
    scan_model: HomeModel
    target_room_id: str

class DiffResult(BaseModel):
    success: bool
    error: Optional[str] = None
    diff_objects: list[FloorObject] = []
    obstructions: list[Obstruction] = []

def poly_centroid(poly: list[Point]) -> Point:
    x = sum(p[0] for p in poly) / len(poly)
    y = sum(p[1] for p in poly) / len(poly)
    return (x, y)

def rotate_point(p: Point, angle: float, origin: Point) -> Point:
    s = math.sin(angle)
    c = math.cos(angle)
    x = p[0] - origin[0]
    y = p[1] - origin[1]
    return (x * c - y * s + origin[0], x * s + y * c + origin[1])

def align_room(scan_room: Room, target_room: Room, tolerance_m: float) -> Optional[tuple[float, float, float]]:
    """Returns (dx, dy, angle) to transform scan_room to target_room, or None if they don't match."""
    # Simplified alignment: match centroids
    c_scan = poly_centroid(scan_room.polygon)
    c_tgt = poly_centroid(target_room.polygon)
    
    # Try 4 orthogonal rotations (RoomPlan is usually axis-aligned, but local origin can be arbitrary)
    best_match = None
    best_dist = float('inf')
    
    for i in range(4):
        angle = i * math.pi / 2
        # Transform scan polygon
        transformed = []
        for p in scan_room.polygon:
            # translate to c_tgt, rotate around c_tgt
            p_trans = (p[0] - c_scan[0] + c_tgt[0], p[1] - c_scan[1] + c_tgt[1])
            p_rot = rotate_point(p_trans, angle, c_tgt)
            transformed.append(p_rot)
            
        # Check if transformed polygon matches target polygon (vertex by vertex, or just area/bbox)
        # For simplicity, let's just check the distance between bounding boxes or vertices.
        # Since vertices might be out of order, we match each transformed vertex to the closest target vertex.
        max_dist = 0
        for pt in transformed:
            closest = min(math.hypot(pt[0]-tp[0], pt[1]-tp[1]) for tp in target_room.polygon)
            max_dist = max(max_dist, closest)
            
        if max_dist < best_dist:
            best_dist = max_dist
            best_match = (c_tgt[0] - c_scan[0], c_tgt[1] - c_scan[1], angle)
            
    if best_dist <= tolerance_m:
        return best_match
    return None

def apply_transform(obj: FloorObject, dx: float, dy: float, angle: float, origin: Point) -> FloorObject:
    # translate
    cx = obj.center[0] + dx
    cy = obj.center[1] + dy
    # rotate
    c_rot = rotate_point((cx, cy), angle, origin)
    
    new_obj = obj.model_copy()
    new_obj.center = c_rot
    new_obj.rotation_deg = (new_obj.rotation_deg + math.degrees(angle)) % 360
    return new_obj

def compute_diff(
    stored_model: HomeModel,
    scan_model: HomeModel,
    target_room_id: str,
    thresholds: EgressThresholds,
    registration_tolerance_m: float
) -> DiffResult:
    # Find target room in stored model
    target_room = None
    target_floor = None
    for f in stored_model.floors:
        for r in f.rooms:
            if r.id == target_room_id:
                target_room = r
                target_floor = f
                break
                
    if not target_room:
        return DiffResult(success=False, error="Target room not found in stored model")
        
    # Scan model should have 1 room
    if not scan_model.floors or not scan_model.floors[0].rooms:
        return DiffResult(success=False, error="Scan model has no rooms")
        
    scan_room = scan_model.floors[0].rooms[0]
    scan_objects = scan_model.floors[0].objects
    
    # Align
    transform = align_room(scan_room, target_room, registration_tolerance_m)
    if not transform:
        return DiffResult(success=False, error="couldn't line this scan up")
        
    dx, dy, angle = transform
    c_tgt = poly_centroid(target_room.polygon)
    
    # Transform scan objects
    transformed_objects = [apply_transform(o, dx, dy, angle, c_tgt) for o in scan_objects]
    
    # Find new objects
    stored_objects = target_floor.objects
    diff_objects = []
    
    for sc_obj in transformed_objects:
        matched = False
        for st_obj in stored_objects:
            d = math.hypot(sc_obj.center[0] - st_obj.center[0], sc_obj.center[1] - st_obj.center[1])
            if d <= registration_tolerance_m:
                matched = True
                break
        if not matched:
            sc_obj.id = f"scan_{sc_obj.id}"
            sc_obj.source = "scan"
            sc_obj.confidence = 0.3
            sc_obj.category = "other"  # per spec: NEVER a guessed category
            diff_objects.append(sc_obj)
            
    if not diff_objects:
        return DiffResult(success=True, diff_objects=[], obstructions=[])
        
    # Run obstructions logic with injected objects
    # We copy the target floor and add diff objects
    temp_objects = list(stored_objects) + diff_objects
    
    # We only care about obstructions caused by the NEW objects.
    # We can run analyze_obstructions on a temp home model, but it's simpler to just run the probe on target_room
    code_c = code_clearance_m(thresholds)
    comfort_c = code_c + COMFORT_MARGIN_M
    out = []
    
    local = objects_intersecting(list(target_room.polygon), temp_objects)
    start = polygon_centroid(list(target_room.polygon))
    
    polygons = {r.id: list(r.polygon) for r in target_floor.rooms}
    
    for op in _room_openings(target_floor, target_room):
        if EXTERIOR_ID in op.room_ids:
            continue
            
        required_width = thresholds.window_min_width_m if op.kind == "window" else thresholds.door_min_width_m
        host_polygon = polygons.get(op.wall_segment.room_id)
        if not host_polygon:
            continue
            
        goal = opening_midpoint(
            host_polygon,
            op.wall_segment.edge_index,
            op.wall_segment.t0,
            op.wall_segment.t1,
        )
        goal_radius = max(op.width_m / 2, 0.6)
        
        code_ok = _reachable(list(target_room.polygon), local, start, goal, code_c, goal_radius)
        if code_ok and _reachable(list(target_room.polygon), local, start, goal, comfort_c, goal_radius):
            continue
            
        probe_c = code_c if not code_ok else comfort_c
        culprits = culprit_object_ids(list(target_room.polygon), local, start, goal, probe_c, goal_radius)
        
        # Are any diff objects in culprits?
        diff_culprits = [c for c in culprits if c.id.startswith("scan_")]
        if not diff_culprits:
            continue
            
        tolerated = tolerated_clearance_m(list(target_room.polygon), local, start, goal, goal_radius, comfort_c)
        passable_width = round(2 * tolerated, 3)
        target_width = required_width if not code_ok else required_width + 2 * COMFORT_MARGIN_M
        
        out.append(
            Obstruction(
                kind="blocks_opening" if not code_ok else "narrows_route",
                room_id=target_room.id,
                room_name=target_room.name,
                floor_id=target_floor.id,
                opening_id=op.id,
                object_ids=tuple(c.id for c in culprits), # include all so removal is correct
                object_categories=tuple(c.category for c in culprits),
                passable_width_m=passable_width,
                required_width_m=required_width,
                target_width_m=round(target_width, 3),
                suggested_move_m=_suggested_move_m(passable_width, target_width),
            )
        )
        
    return DiffResult(success=True, diff_objects=diff_objects, obstructions=out)
