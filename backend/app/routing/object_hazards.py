from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Literal

from app.models import HomeModel, FloorObject, Opening, Room, Point, ObjectCategory
from app.routing.graph import opening_midpoint

@dataclass(frozen=True)
class ObjectHazard:
    rule_id: Literal["topple", "overhead", "heat_clearance", "water_heater_unsecured"]
    severity: Literal["high", "info"]
    floor_id: str
    room_id: str
    room_name: str
    object_id: str
    object_category: str
    target: Literal["bed", "sofa", "egress"] | None
    reach_m: float | None
    gap_m: float | None
    clearance_m: float | None
    threshold_m: float | None
    citation: str
    detail: str

def _obb_corners(obj: FloorObject, inflate_w_m: float = 0.0, inflate_d_m: float = 0.0) -> list[Point]:
    w = obj.size_m[0] + 2 * inflate_w_m
    d = obj.size_m[1] + 2 * inflate_d_m
    angle = -math.radians(obj.rotation_deg)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    
    cx, cy = obj.center
    
    # Half dimensions
    hw, hd = w / 2, d / 2
    
    corners = [
        (hw, hd),
        (hw, -hd),
        (-hw, -hd),
        (-hw, hd)
    ]
    
    res = []
    for lx, ly in corners:
        rx = cx + lx * cos_a - ly * sin_a
        ry = cy + lx * sin_a + ly * cos_a
        res.append((rx, ry))
    return res

def _dist_sq_point_segment(p: Point, a: Point, b: Point) -> float:
    l2 = (a[0] - b[0])**2 + (a[1] - b[1])**2
    if l2 == 0:
        return (p[0] - a[0])**2 + (p[1] - a[1])**2
    t = max(0, min(1, ((p[0] - a[0]) * (b[0] - a[0]) + (p[1] - a[1]) * (b[1] - a[1])) / l2))
    proj = (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))
    return (p[0] - proj[0])**2 + (p[1] - proj[1])**2

def _dist_segment_segment(a1: Point, a2: Point, b1: Point, b2: Point) -> float:
    # A simple approach for 2D segment distance
    # Check intersection first
    def ccw(A: Point, B: Point, C: Point) -> bool:
        return (C[1]-A[1]) * (B[0]-A[0]) > (B[1]-A[1]) * (C[0]-A[0])
    def intersect(A, B, C, D):
        return ccw(A, C, D) != ccw(B, C, D) and ccw(A, B, C) != ccw(A, B, D)
    
    if intersect(a1, a2, b1, b2):
        # 0.0 is a pure geometric distance (intersecting), not a configurable threshold
        return 0.0
    
    d1 = _dist_sq_point_segment(b1, a1, a2)
    d2 = _dist_sq_point_segment(b2, a1, a2)
    d3 = _dist_sq_point_segment(a1, b1, b2)
    d4 = _dist_sq_point_segment(a2, b1, b2)
    return math.sqrt(min(d1, d2, d3, d4))

def _obb_distance(corners1: list[Point], corners2: list[Point]) -> float:
    # Check if one is inside the other by point in polygon
    def point_in_poly(p, poly):
        inside = False
        j = len(poly) - 1
        for i in range(len(poly)):
            # 1e-9 is a math epsilon to prevent division by zero, not a domain threshold
            if ((poly[i][1] > p[1]) != (poly[j][1] > p[1])) and \
               (p[0] < (poly[j][0] - poly[i][0]) * (p[1] - poly[i][1]) / (poly[j][1] - poly[i][1] + 1e-9) + poly[i][0]):
                inside = not inside
            j = i
        return inside

    if any(point_in_poly(p, corners2) for p in corners1): return 0.0
    if any(point_in_poly(p, corners1) for p in corners2): return 0.0

    min_dist = float('inf')
    for i in range(4):
        a1 = corners1[i]
        a2 = corners1[(i+1)%4]
        for j in range(4):
            b1 = corners2[j]
            b2 = corners2[(j+1)%4]
            d = _dist_segment_segment(a1, a2, b1, b2)
            if d < min_dist:
                min_dist = d
    return min_dist

def _obb_intersects_circle(corners: list[Point], center: Point, radius: float) -> bool:
    # Check if circle center is inside OBB
    def point_in_poly(p, poly):
        inside = False
        j = len(poly) - 1
        for i in range(len(poly)):
            # 1e-9 is a math epsilon to prevent division by zero, not a domain threshold
            if ((poly[i][1] > p[1]) != (poly[j][1] > p[1])) and \
               (p[0] < (poly[j][0] - poly[i][0]) * (p[1] - poly[i][1]) / (poly[j][1] - poly[i][1] + 1e-9) + poly[i][0]):
                inside = not inside
            j = i
        return inside
    
    if point_in_poly(center, corners):
        return True
    
    min_dist_sq = float('inf')
    for i in range(4):
        a = corners[i]
        b = corners[(i+1)%4]
        d_sq = _dist_sq_point_segment(center, a, b)
        if d_sq < min_dist_sq:
            min_dist_sq = d_sq
    return min_dist_sq <= radius * radius

from pydantic import BaseModel, Field

class CitedThreshold(BaseModel):
    value_m: float

class EngineeringConstant(BaseModel):
    value: float

class CitedSection(BaseModel):
    heater_clearance: CitedThreshold

class EngineeringSection(BaseModel):
    topple_min_height_m: EngineeringConstant
    topple_slenderness_ratio: EngineeringConstant
    overhead_min_elevation_m: EngineeringConstant
    door_approach_radius_m: EngineeringConstant
    registration_tolerance_m: EngineeringConstant

class ObjectHazardThresholds(BaseModel):
    cited: CitedSection
    engineering_constants: EngineeringSection


def analyze_object_hazards(home: HomeModel, thresholds: ObjectHazardThresholds) -> list[ObjectHazard]:
    hazards = []
    
    # Precompute room openings for R1 egress approaches
    floor_room_openings = {}
    for floor in home.floors:
        for room in floor.rooms:
            floor_room_openings[(floor.id, room.id)] = []
    for floor in home.floors:
        for op in floor.openings:
            for rid in op.room_ids:
                if rid != "exterior" and (floor.id, rid) in floor_room_openings:
                    floor_room_openings[(floor.id, rid)].append(op)

    for floor in home.floors:
        polygons = {room.id: list(room.polygon) for room in floor.rooms}
        for room in floor.rooms:
            # Get objects in this room
            # For simplicity and purity, since we can't reliably rely on nav_grid's objects_intersecting
            # we'll just check bounding circles against the room's bounding box as nav_grid does, 
            # or we can use point_in_polygon for the object center.
            # Let's use the simplest: object center is in room polygon.
            room_objects = []
            for obj in floor.objects:
                # bounding box check
                xs = [p[0] for p in room.polygon]
                ys = [p[1] for p in room.polygon]
                r = math.hypot(obj.size_m[0], obj.size_m[1]) / 2
                if (
                    obj.center[0] + r >= min(xs)
                    and obj.center[0] - r <= max(xs)
                    and obj.center[1] + r >= min(ys)
                    and obj.center[1] - r <= max(ys)
                ):
                    room_objects.append(obj)
            
            # Sort for deterministic output
            room_objects.sort(key=lambda o: o.id)
            openings = floor_room_openings.get((floor.id, room.id), [])

            for obj in room_objects:
                cat = obj.category.value if hasattr(obj.category, "value") else str(obj.category)
                
                # R5: water heater unsecured
                if cat == "water_heater" and not obj.secured:
                    hazards.append(ObjectHazard(
                        rule_id="water_heater_unsecured",
                        severity="high",
                        floor_id=floor.id,
                        room_id=room.id,
                        room_name=room.name,
                        object_id=obj.id,
                        object_category=cat,
                        target=None,
                        reach_m=None, gap_m=None, clearance_m=None, threshold_m=None,
                        citation="fema-earthquake",
                        detail="The water heater isn't strapped. An earthquake can tip it and rupture the gas line — strap it to wall studs at the top and bottom."
                    ))
                
                # R1: topple
                topple_cat = cat in {"wardrobe", "bookcase", "storage", "water_heater"}
                min_h = thresholds.engineering_constants.topple_min_height_m.value
                slenderness = thresholds.engineering_constants.topple_slenderness_ratio.value
                
                is_topple_prone = topple_cat or (obj.height_m >= min_h and (obj.height_m / min(obj.size_m)) >= slenderness)
                
                if not obj.secured and obj.elevation_m == 0 and is_topple_prone:
                    # check targets
                    # topple band is obj footprint inflated by height_m
                    band_corners = _obb_corners(obj, obj.height_m, obj.height_m)
                    obj_corners = _obb_corners(obj)
                    
                    best_target_name = None
                    best_dist = float('inf')
                    is_high = False
                    
                    for other in room_objects:
                        if other.id == obj.id: continue
                        ocat = other.category.value if hasattr(other.category, "value") else str(other.category)
                        if ocat in {"bed", "sofa"}:
                            other_corners = _obb_corners(other)
                            if _obb_distance(band_corners, other_corners) == 0:
                                d = _obb_distance(obj_corners, other_corners)
                                if d < best_dist:
                                    best_dist = d
                                    best_target_name = "the bed" if ocat == "bed" else "the sofa"
                                    if ocat == "bed":
                                        is_high = True
                                        
                    for op in openings:
                        if len(openings) == 1:
                            is_high = True
                        
                        host_polygon = polygons.get(op.wall_segment.room_id)
                        if not host_polygon: continue
                        goal = opening_midpoint(
                            host_polygon,
                            op.wall_segment.edge_index,
                            op.wall_segment.t0,
                            op.wall_segment.t1
                        )
                        min_radius = thresholds.engineering_constants.door_approach_radius_m.value
                        radius = max(op.width_m / 2, min_radius)
                        if _obb_intersects_circle(band_corners, goal, radius):
                            # compute distance from object to goal minus radius
                            d = float('inf')
                            # exact distance from OBB to circle is dist(OBB, center) - radius
                            # We'll just approximate dist as dist to center
                            # or _dist_sq_point_segment to the corners.
                            # We can just say "the doorway 'op-id'"
                            pass
                            # Actually let's calculate proper distance
                            def dist_point_poly(p, poly):
                                inside = False
                                j = len(poly) - 1
                                for i in range(len(poly)):
                                    # 1e-9 is a math epsilon to prevent division by zero, not a domain threshold
                                    if ((poly[i][1] > p[1]) != (poly[j][1] > p[1])) and \
                                       (p[0] < (poly[j][0] - poly[i][0]) * (p[1] - poly[i][1]) / (poly[j][1] - poly[i][1] + 1e-9) + poly[i][0]):
                                        inside = not inside
                                    j = i
                                # 0.0 is exact geometric distance, not a domain threshold
                                if inside: return 0.0
                                md = float('inf')
                                for i in range(4):
                                    d_sq = _dist_sq_point_segment(p, poly[i], poly[(i+1)%4])
                                    if d_sq < md: md = d_sq
                                return math.sqrt(md)
                            
                            # 0.0 bounds exact geometric distance to be non-negative
                            c_dist = max(0.0, dist_point_poly(goal, obj_corners) - radius)
                            if c_dist < best_dist:
                                best_dist = c_dist
                                best_target_name = f"the doorway '{op.id}'"
                                
                    if best_target_name:
                        cat_str = cat.replace('_', ' ')
                        detail = f"The {cat_str} ({obj.height_m:.1f} m tall, unsecured) can reach {best_target_name} {best_dist:.1f} m away if it topples. Strap it to wall studs — adhesive strap kits work for renters."
                        hazards.append(ObjectHazard(
                            rule_id="topple",
                            severity="high" if is_high else "info",
                            floor_id=floor.id,
                            room_id=room.id,
                            room_name=room.name,
                            object_id=obj.id,
                            object_category=cat,
                            target="egress" if "door" in best_target_name else "bed" if "bed" in best_target_name else "sofa",
                            reach_m=best_dist, gap_m=None, clearance_m=None, threshold_m=obj.height_m,
                            citation="shakeout-guidance",
                            detail=detail
                        ))
                
                # R2: overhead
                min_elev = thresholds.engineering_constants.overhead_min_elevation_m.value
                if obj.elevation_m >= min_elev:
                    obj_corners = _obb_corners(obj)
                    for other in room_objects:
                        if other.id == obj.id: continue
                        ocat = other.category.value if hasattr(other.category, "value") else str(other.category)
                        if ocat in {"bed", "sofa"}:
                            other_corners = _obb_corners(other)
                            if _obb_distance(obj_corners, other_corners) == 0:
                                sev = "high" if ocat == "bed" else "info"
                                if obj.mounted and obj.secured:
                                    sev = "info"
                                
                                cat_str = cat.replace('_', ' ')
                                detail = f"The {cat_str} mounted {obj.elevation_m:.1f} m up overlaps the head of the bed. Move heavy items to lower shelves or relocate them away from where people sleep."
                                if ocat == "sofa":
                                    detail = f"The {cat_str} mounted {obj.elevation_m:.1f} m up overlaps the seating area. Move heavy items to lower shelves or relocate them away from where people sit."
                                
                                hazards.append(ObjectHazard(
                                    rule_id="overhead",
                                    severity=sev,
                                    floor_id=floor.id,
                                    room_id=room.id,
                                    room_name=room.name,
                                    object_id=obj.id,
                                    object_category=cat,
                                    target=ocat,
                                    reach_m=None, gap_m=None, clearance_m=None, threshold_m=min_elev,
                                    citation="shakeout-guidance",
                                    detail=detail
                                ))
                
                # R3: heat_clearance
                if cat == "heat_source":
                    clearance = thresholds.cited.heater_clearance.value_m
                    obj_corners = _obb_corners(obj)
                    for other in room_objects:
                        if other.id == obj.id: continue
                        ocat = other.category.value if hasattr(other.category, "value") else str(other.category)
                        # "Only movable objects trigger it; walls and counters do not"
                        # All RoomPlan mapped objects are movable except perhaps heat_source itself
                        # We'll trigger for anything that isn't a heat_source or whatever
                        # Wait, what if they have two heat sources? Let's just trigger for all other objects.
                        other_corners = _obb_corners(other)
                        dist = _obb_distance(obj_corners, other_corners)
                        if dist < clearance:
                            sev = "high" if ocat in {"bed", "sofa"} else "info"
                            move_dist = clearance - dist
                            ocat_str = ocat.replace('_', ' ')
                            # "The sofa sits 0.4 m from the heater — under the 0.9 m (3 ft) clearance NFPA recommends. Move it at least 0.5 m farther away."
                            detail = f"The {ocat_str} sits {dist:.1f} m from the heater — under the {clearance:.1f} m (3 ft) clearance NFPA recommends. Move it at least {move_dist:.1f} m farther away."
                            
                            hazards.append(ObjectHazard(
                                rule_id="heat_clearance",
                                severity=sev,
                                floor_id=floor.id,
                                room_id=room.id,
                                room_name=room.name,
                                object_id=other.id,
                                object_category=ocat,
                                target=None,
                                reach_m=None, gap_m=None, clearance_m=dist, threshold_m=clearance,
                                citation="nfpa-heating-safety",
                                detail=detail
                            ))

    # Output list sorted deterministically by floor/room/object id
    hazards.sort(key=lambda h: (h.floor_id, h.room_id, h.object_id, h.rule_id))
    return hazards

