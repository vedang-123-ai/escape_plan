import math
from pydantic import BaseModel
from typing import Sequence
from shapely.geometry import box, Polygon
from shapely.affinity import rotate
from app.models.home import FloorObject

class ScanDiff(BaseModel):
    new_objects: list[FloorObject]

def get_footprint(obj: FloorObject) -> Polygon:
    w, d = obj.size_m
    x, y = obj.center
    b = box(x - w/2, y - d/2, x + w/2, y + d/2)
    return rotate(b, obj.rotation_deg, origin=(x,y))

def compute_diff(stored_objects: Sequence[FloorObject], scanned_objects: Sequence[FloorObject], tolerance_m: float) -> list[FloorObject]:
    """Return scanned objects that do not overlap a stored object within tolerance."""
    stored_polys = [get_footprint(o) for o in stored_objects]
    
    diff_objects = []
    for sc_obj in scanned_objects:
        sc_poly = get_footprint(sc_obj)
        matched = False
        for st_poly in stored_polys:
            # Distance between centroids
            d = math.hypot(sc_poly.centroid.x - st_poly.centroid.x, sc_poly.centroid.y - st_poly.centroid.y)
            if d <= tolerance_m:
                matched = True
                break
        if not matched:
            diff_objects.append(sc_obj)
            
    return diff_objects
