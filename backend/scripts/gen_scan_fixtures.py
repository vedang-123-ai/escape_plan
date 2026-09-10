"""Generate the synthetic RoomPlan-format scan fixtures in schema/fixtures/scans/.

Dev-only, stdlib-only. Run from backend/:  python3 scripts/gen_scan_fixtures.py

These fixtures encode the ASSUMED RoomPlan export format documented in
app/convert/README.md (column-major simd transforms, {"high": {}} confidence
objects, per-room surface arrays). Ground truth for each is asserted in
tests/test_convert.py. Regenerate rather than hand-editing the JSON.
"""

from __future__ import annotations

import json
import math
import uuid
from pathlib import Path

SCANS_DIR = Path(__file__).resolve().parents[2] / "schema" / "fixtures" / "scans"
NS = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

Point = tuple[float, float]


def ident(name: str) -> str:
    return str(uuid.uuid5(NS, name))


def rotate(p: Point, deg: float) -> Point:
    a = math.radians(deg)
    return (
        round(p[0] * math.cos(a) - p[1] * math.sin(a), 6),
        round(p[0] * math.sin(a) + p[1] * math.cos(a), 6),
    )


def surface(
    name: str,
    a: Point,
    b: Point,
    height: float,
    category: dict,
    confidence: str = "high",
    *,
    floor_y: float = 0.0,
    sill: float | None = None,
    center_override: Point | None = None,
) -> dict:
    """Build a Surface whose plan segment runs a→b (plan y = world z).

    Walls sit on the floor; doors/windows pass `sill` for their bottom height.
    `center_override` displaces the plan center (for planted mismatch cases).
    """
    length = math.dist(a, b)
    dx, dz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    cx, cz = (a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0
    if center_override is not None:
        cx, cz = center_override
    bottom = floor_y if sill is None else floor_y + sill
    cy = bottom + height / 2.0
    # Column-major simd_float4x4: x-axis, y-axis, z-axis = x × y, translation.
    transform = [
        round(dx, 6), 0.0, round(dz, 6), 0.0,
        0.0, 1.0, 0.0, 0.0,
        round(-dz, 6), 0.0, round(dx, 6), 0.0,
        round(cx, 6), round(cy, 6), round(cz, 6), 1.0,
    ]
    return {
        "identifier": ident(name),
        "transform": transform,
        "dimensions": [round(length, 6), height, 0.0],
        "confidence": {confidence: {}},
        "category": category,
        "parentIdentifier": None,
        "story": 0,
    }


def wall(name: str, a: Point, b: Point, h: float = 2.5, conf: str = "high") -> dict:
    return surface(name, a, b, h, {"wall": {}}, conf)


def door(name: str, a: Point, b: Point, h: float = 2.0, conf: str = "high", **kw) -> dict:
    return surface(name, a, b, h, {"door": {"isOpen": False}}, conf, **kw)


def window(name: str, a: Point, b: Point, h: float, sill: float, conf: str = "high") -> dict:
    return surface(name, a, b, h, {"window": {}}, conf, sill=sill)


def rect_walls(prefix: str, x0: float, y0: float, x1: float, y1: float, conf: str = "high") -> list[dict]:
    c = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    names = ["south", "east", "north", "west"]
    return [wall(f"{prefix}/wall-{n}", c[i], c[(i + 1) % 4], conf=conf) for i, n in enumerate(names)]


def section(label: str, cx: float, cz: float) -> dict:
    return {"label": label, "center": [cx, 1.0, cz]}


def object_item(name: str, cx: float, cz: float, size_x: float, size_z: float, height: float, category: str, conf: str = "high", rot: float = 0.0, floor_y: float = 0.0, elev: float = 0.0) -> dict:
    cy = floor_y + elev + height / 2.0
    a = math.radians(rot)
    dx, dz = math.cos(a), math.sin(a)
    transform = [
        round(dx, 6), 0.0, round(dz, 6), 0.0,
        0.0, 1.0, 0.0, 0.0,
        round(-dz, 6), 0.0, round(dx, 6), 0.0,
        round(cx, 6), round(cy, 6), round(cz, 6), 1.0,
    ]
    return {
        "identifier": ident(name),
        "transform": transform,
        "dimensions": [round(size_x, 6), round(height, 6), round(size_z, 6)],
        "confidence": {conf: {}},
        "category": {category: {}},
    }


# ---------------------------------------------------------------------------
# 1. Clean rectangular bungalow — 2 rooms, shared door by IDENTIFIER match
# ---------------------------------------------------------------------------

def bungalow() -> dict:
    shared = door("bungalow/door-living-bedroom", (2.0, 4.0), (2.9, 4.0))
    living = {
        "identifier": ident("bungalow/room-living"),
        "walls": rect_walls("bungalow/living", 0, 0, 5, 4),
        "doors": [door("bungalow/door-front", (1.0, 0.0), (1.9, 0.0)), shared],
        "windows": [window("bungalow/window-living", (0.0, 1.0), (0.0, 2.0), 1.2, 0.8)],
        "openings": [],
        "sections": [section("livingRoom", 2.5, 2.0)],
        "objects": [
            object_item("bungalow/sofa", 2.0, 2.0, 2.0, 0.9, 0.8, "sofa"),
            object_item("bungalow/tv", 2.0, 0.5, 1.2, 0.2, 0.8, "television", elev=0.5),
        ],
    }
    bedroom = {
        "identifier": ident("bungalow/room-bedroom"),
        "walls": rect_walls("bungalow/bedroom", 0, 4, 5, 8),
        "doors": [shared],  # same identifier: merged-structure dedup path
        "windows": [window("bungalow/window-bedroom", (1.5, 8.0), (2.5, 8.0), 1.2, 0.8)],
        "openings": [],
        "sections": [section("bedroom", 2.5, 6.0)],
        "objects": [
            object_item("bungalow/bed", 2.5, 7.0, 1.6, 2.0, 0.6, "bed", conf="high"),
            object_item("bungalow/chair", 1.0, 5.0, 0.5, 0.5, 0.9, "chair", conf="high"), # dropped category
            object_item("bungalow/storage", 4.0, 5.0, 1.0, 0.5, 2.0, "storage", conf="medium"),
            object_item("bungalow/stove", 4.0, 7.0, 0.8, 0.8, 0.9, "stove", conf="low"),
            object_item("bungalow/unknown", 1.0, 7.0, 0.5, 0.5, 0.5, "some_unknown_category", conf="low"),
        ],
    }
    return {"version": 3, "rooms": [living, bedroom]}


# ---------------------------------------------------------------------------
# 2. Messy scan — bare CapturedRoom: split near-collinear wall, 0.3 m gap,
#    3° global rotation, low confidences, displaced (unresolvable) door
# ---------------------------------------------------------------------------

def messy() -> dict:
    rot = 3.0

    def r(p: Point) -> Point:
        return rotate(p, rot)

    walls = [
        # south wall split into two near-collinear pieces (~1° bend)
        wall("messy/wall-south-a", r((0.0, 0.0)), r((2.0, 0.03)), conf="medium"),
        wall("messy/wall-south-b", r((2.0, 0.03)), r((4.0, 0.0)), conf="medium"),
        # east wall stops 0.3 m short of the north wall (scan gap)
        wall("messy/wall-east", r((4.0, 0.0)), r((4.0, 2.7)), conf="low"),
        wall("messy/wall-north", r((4.0, 3.0)), r((0.0, 3.0)), conf="medium"),
        wall("messy/wall-west", r((0.0, 3.0)), r((0.0, 0.0)), conf="medium"),
    ]
    # Door geometry parallel to the south wall but its center floated 0.6 m into
    # the room — unresolvable placement, must be kept at confidence <= 0.25.
    drifting = door(
        "messy/door-drifting",
        r((1.0, 0.0)),
        r((1.9, 0.0)),
        conf="medium",
        center_override=r((1.45, 0.6)),
    )
    room_dict = {
        "identifier": ident("messy/room"),
        "walls": walls,
        "doors": [drifting],
        "windows": [window("messy/window-north", r((1.5, 3.0)), r((2.5, 3.0)), 1.2, 0.9, conf="low")],
        "openings": [],
        "sections": [],
    }
    return {"version": 2, "rooms": [room_dict]}


# ---------------------------------------------------------------------------
# 3. Two rooms, shared door by GEOMETRIC match (different identifiers,
#    centers 0.05 m apart) + exterior door + exterior window
# ---------------------------------------------------------------------------

def shared_door() -> dict:
    kitchen = {
        "identifier": ident("shared/room-kitchen"),
        "walls": rect_walls("shared/kitchen", 0, 0, 4, 3),
        "doors": [door("shared/door-kitchen-side", (3.98, 1.0), (3.98, 1.9))],
        "windows": [window("shared/window-kitchen", (0.0, 1.0), (0.0, 2.0), 1.0, 0.9)],
        "openings": [],
        "sections": [section("kitchen", 2.0, 1.5)],
        "objects": [
            object_item("shared/stove", 1.0, 0.5, 0.8, 0.8, 0.9, "stove"),
            object_item("shared/fridge", 3.0, 0.5, 0.9, 0.9, 1.8, "refrigerator"),
        ],
    }
    hall = {
        "identifier": ident("shared/room-hall"),
        "walls": rect_walls("shared/hall", 4, 0, 8, 3),
        "doors": [
            door("shared/door-hall-side", (4.03, 1.0), (4.03, 1.9)),
            door("shared/door-back", (8.0, 1.0), (8.0, 1.9)),
        ],
        "windows": [],
        "openings": [],
        "sections": [section("hallway", 6.0, 1.5)],
        "objects": [],
    }
    return {"version": 3, "rooms": [kitchen, hall]}


def empty_scan() -> dict:
    return {"version": 3, "rooms": [{
        "identifier": ident("empty/room"),
        "walls": [], "doors": [], "windows": [], "openings": [], "sections": [], "objects": []
    }]}

def main() -> None:
    SCANS_DIR.mkdir(parents=True, exist_ok=True)
    fixtures = {
        "synthetic-bungalow.roomplan.json": bungalow(),
        "synthetic-messy.roomplan.json": messy(),
        "synthetic-shared-door.roomplan.json": shared_door(),
        "synthetic-empty.roomplan.json": empty_scan(),
    }
    for name, data in fixtures.items():
        path = SCANS_DIR / name
        path.write_text(json.dumps(data, indent=2) + "\n")
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
