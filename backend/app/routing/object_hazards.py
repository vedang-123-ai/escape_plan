from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any, Literal

from app.models import HomeModel, FloorObject, Opening, OpeningKind, Room, Point, ObjectCategory
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
    # Local → world is a +rotation_deg (CCW) turn. This was negated, which mirrored
    # every box not at a multiple of 90° — and a scan's furniture almost never is.
    # nav_grid.object_contains (world → local) uses the negated angle, correctly.
    angle = math.radians(obj.rotation_deg)
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

def _point_in_poly(p: Point, poly: list[Point]) -> bool:
    """Ray-cast point-in-polygon. The engine's single answer to "is it in here?".

    Lived inline in three places before S11.3, which is how the room-assignment
    filter (BUG-02) came to use a bounding box instead: the correct helper was
    already in the file, just not reachable from the loop that needed it.
    """
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        # 1e-9 is a math epsilon to prevent division by zero, not a domain threshold
        if ((poly[i][1] > p[1]) != (poly[j][1] > p[1])) and \
           (p[0] < (poly[j][0] - poly[i][0]) * (p[1] - poly[i][1]) / (poly[j][1] - poly[i][1] + 1e-9) + poly[i][0]):
            inside = not inside
        j = i
    return inside

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

def _dist_point_to_obb(p: Point, corners: list[Point]) -> float:
    """Distance from a point to an oriented box; 0 when the point is inside it."""
    # 0.0 is exact geometric distance, not a domain threshold
    if _point_in_poly(p, corners):
        return 0.0
    md = float('inf')
    for i in range(4):
        d_sq = _dist_sq_point_segment(p, corners[i], corners[(i + 1) % 4])
        if d_sq < md:
            md = d_sq
    return math.sqrt(md)

def _obb_distance(corners1: list[Point], corners2: list[Point]) -> float:
    # Check if one is inside the other by point in polygon
    if any(_point_in_poly(p, corners2) for p in corners1): return 0.0
    if any(_point_in_poly(p, corners1) for p in corners2): return 0.0

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
    if _point_in_poly(center, corners):
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


@dataclass(frozen=True)
class _ToppleTarget:
    """What an unsecured object's topple band reaches, and how far away it is."""
    kind: Literal["bed", "sofa", "egress"]
    name: str
    dist_m: float
    is_high: bool


def _topple_target(
    obj: FloorObject,
    room_objects: list[FloorObject],
    openings: list[Opening],
    polygons: dict[str, list[Point]],
    door_approach_radius_m: float,
) -> _ToppleTarget | None:
    """The nearest thing the object's topple band reaches, or None.

    The band is the footprint pushed out by `height_m` on each face — a falling
    cabinet sweeps roughly its own height. Extracted from R1 in S11.3 so R5 can
    reuse it: an unsecured water heater emits one finding (BUG-03), and that
    finding should still carry the measurement R1 was the only one computing.

    Severity, per spec sec 4 R1: high when the band reaches a bed, or reaches the
    approach of the room's ONLY egress.
    """
    band_corners = _obb_corners(obj, obj.height_m, obj.height_m)
    obj_corners = _obb_corners(obj)

    best: _ToppleTarget | None = None
    best_dist = float('inf')
    reaches_bed = False

    for other in room_objects:
        if other.id == obj.id:
            continue
        ocat = other.category.value if hasattr(other.category, "value") else str(other.category)
        if ocat not in {"bed", "sofa"}:
            continue
        other_corners = _obb_corners(other)
        if _obb_distance(band_corners, other_corners) != 0:
            continue
        if ocat == "bed":
            reaches_bed = True
        d = _obb_distance(obj_corners, other_corners)
        if d < best_dist:
            best_dist = d
            best = _ToppleTarget(
                kind="bed" if ocat == "bed" else "sofa",
                name="the bed" if ocat == "bed" else "the sofa",
                dist_m=d,
                is_high=False,
            )

    reaches_sole_egress = False
    for op in openings:
        host_polygon = polygons.get(op.wall_segment.room_id)
        if not host_polygon:
            continue
        goal = opening_midpoint(
            host_polygon,
            op.wall_segment.edge_index,
            op.wall_segment.t0,
            op.wall_segment.t1,
        )
        radius = max(op.width_m / 2, door_approach_radius_m)
        if not _obb_intersects_circle(band_corners, goal, radius):
            continue
        # BUG-05 (found S11.3): `is_high = True` used to be set at the TOP of this
        # loop, for any room with one opening, before the intersection test had said
        # anything. So every unsecured tall object in a one-door room came out high
        # and capped the composite score on geometry the engine never checked. The
        # flag belongs here, after the band is known to reach the approach.
        if len(openings) == 1:
            reaches_sole_egress = True
        # BUG-04 (S10.1 QA): this said "the doorway" for every Opening, so an egress
        # WINDOW — the only topple target in a garage or a hallway — was narrated as
        # a doorway. The label now comes from op.kind.
        label = "window" if op.kind == OpeningKind.window else "doorway"
        # 0.0 bounds exact geometric distance to be non-negative
        c_dist = max(0.0, _dist_point_to_obb(goal, obj_corners) - radius)
        if c_dist < best_dist:
            best_dist = c_dist
            best = _ToppleTarget(
                kind="egress",
                name=f"the {label} '{op.id}'",
                dist_m=c_dist,
                is_high=False,
            )

    if best is None:
        return None
    # `kind` is the nearest target; severity asks whether ANY reached target is
    # serious, so it is computed over the whole sweep, not over the winner.
    # Deriving it from the detail string (the pre-S11.3 code sniffed for "door")
    # is what made BUG-04's rename silently retarget the finding to "sofa".
    return _ToppleTarget(
        kind=best.kind,
        name=best.name,
        dist_m=best.dist_m,
        is_high=reaches_bed or reaches_sole_egress,
    )


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
            # Which objects are in this room?
            #
            # BUG-02 (S10.1 QA, fixed S11.3): this used to inflate the object to a
            # bounding circle and test it against the room's AXIS-ALIGNED BOUNDING BOX.
            # That admitted objects whose centre is in a different room — a bed just
            # over the wall in the living room landed in the bedroom's list, and R1
            # reported a wardrobe able to reach it "0.5 m away", through the wall. It
            # also put one object in several rooms at once, duplicating its findings,
            # and on a non-convex room the AABB covers floor the room does not.
            #
            # An object belongs to the room its CENTRE is in, and to exactly one room.
            # Every rule below reads this list, so the bleed was never only R1's.
            room_objects = [
                obj for obj in floor.objects if _point_in_poly(obj.center, list(room.polygon))
            ]
            
            # Sort for deterministic output
            room_objects.sort(key=lambda o: o.id)
            openings = floor_room_openings.get((floor.id, room.id), [])

            for obj in room_objects:
                cat = obj.category.value if hasattr(obj.category, "value") else str(obj.category)
                
                # R1's geometry, computed once. R5 borrows it (BUG-03).
                topple_cat = cat in {"wardrobe", "bookcase", "storage", "water_heater"}
                min_h = thresholds.engineering_constants.topple_min_height_m.value
                slenderness = thresholds.engineering_constants.topple_slenderness_ratio.value
                is_topple_prone = topple_cat or (obj.height_m >= min_h and (obj.height_m / min(obj.size_m)) >= slenderness)

                topple_applies = not obj.secured and obj.elevation_m == 0 and is_topple_prone
                fires_r5 = cat == "water_heater" and not obj.secured

                # R5 does NOT inherit R1's `elevation_m == 0` gate.
                #
                # N1 (grounding-auditor, S11.3): it did at first, and a water heater on
                # a stand — common in a garage, and required outright where the ignition
                # source must be raised — came out with no target, no reach and no
                # threshold even with a bed inside its topple band. R1's elevation gate
                # exists to separate floor-standing furniture from a wall shelf (R2's
                # job); a raised water heater is neither, and it still topples.
                if topple_applies or fires_r5:
                    target = _topple_target(
                        obj,
                        room_objects,
                        openings,
                        polygons,
                        thresholds.engineering_constants.door_approach_radius_m.value,
                    )
                else:
                    target = None

                # R5: water heater unsecured.
                #
                # BUG-03 (S10.1 QA, fixed S11.3): R5 and R1 both fired for the same
                # heater, so the checklist showed two strap-it cards for one object
                # (`hazard.water_heater_unsecured.wh1` AND `hazard.topple.wh1`).
                # R5 is the more specific rule and wins — but simply deleting the R1
                # finding would have cost the user the only measured number either
                # rule produced, which spec sec 2 forbids. So R5 absorbs the reach:
                # one finding, one action, and the measurement survives.
                if fires_r5:
                    detail = "The water heater isn't strapped."
                    if target is not None:
                        detail += f" It can reach {target.name} {target.dist_m:.1f} m away if it topples."
                    detail += " Secure it to wall studs with two metal straps."
                    hazards.append(ObjectHazard(
                        rule_id="water_heater_unsecured",
                        severity="high",
                        floor_id=floor.id,
                        room_id=room.id,
                        room_name=room.name,
                        object_id=obj.id,
                        object_category=cat,
                        target=target.kind if target else None,
                        reach_m=target.dist_m if target else None,
                        gap_m=None,
                        clearance_m=None,
                        threshold_m=obj.height_m if target else None,
                        # Was fema-earthquake with "an earthquake can tip it and
                        # rupture the gas line ... at the top and bottom". Ready.gov
                        # lists water heaters among the heavy items to secure, so the
                        # ACTION was covered; the rupture mechanism is on no page
                        # fetched (S11.1 deleted the identical claim from
                        # prevention_tips.json), and the sources say TWO METAL STRAPS,
                        # not top and bottom — the CPC's strap positions were
                        # unreachable behind a paywall (decisions.md 2026-09-21).
                        citation="shakeout-guidance",
                        detail=detail
                    ))

                # R1: topple. Suppressed for anything R5 already reported.
                if target is not None and not fires_r5:
                    cat_str = cat.replace('_', ' ')
                    # "adhesive strap kits work for renters" was deleted from
                    # the corpus on 2026-09-21 as unsourced (see
                    # earthquake-securing-home.md, "What this corpus does not
                    # claim"), but survived here under a shakeout-guidance
                    # cite that resolves. Removed in S11.2: this is the text a
                    # renter actually sees, because mitigation_items suppresses
                    # its own item for any object that produced a topple hazard.
                    detail = f"The {cat_str} ({obj.height_m:.1f} m tall, unsecured) can reach {target.name} {target.dist_m:.1f} m away if it topples. Secure it to wall studs; if you rent and cannot drill, move it away from where people sit and sleep."
                    hazards.append(ObjectHazard(
                        rule_id="topple",
                        severity="high" if target.is_high else "info",
                        floor_id=floor.id,
                        room_id=room.id,
                        room_name=room.name,
                        object_id=obj.id,
                        object_category=cat,
                        target=target.kind,
                        reach_m=target.dist_m, gap_m=None, clearance_m=None, threshold_m=obj.height_m,
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
                        # BUG-01 (S10.1 QA, fixed S11.3): another heat source is not a
                        # thing that can burn. R3 asks whether combustible contents sit
                        # inside a heater's clearance zone; a stove beside a stove fired
                        # twice and told the user to move each away from the other, which
                        # is advice addressed at neither. Spec sec 4 R3 now says so.
                        if ocat == "heat_source":
                            continue
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

