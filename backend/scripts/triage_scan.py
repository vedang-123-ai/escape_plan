"""Triage a RoomPlan scan export against the converter's ASSUMED input format.

Dev tool for the LiDAR field test (see docs/tracker/field-test-lidar.md). Run from
backend/ on a raw export copied off a device:

    python3 scripts/triage_scan.py ../artifacts/scans/kitchen-hall/raw.roomplan.json

`app/convert/README.md` says plainly that the converter was written against an
*assumed* encoding of `CapturedStructure` and has only ever been validated on
synthetic fixtures. So the first question a real export has to answer is not "did
conversion succeed?" but "do the format assumptions hold?" — a row-major transform
encoding, for instance, converts without raising and produces a house made entirely
of bounding boxes. This script checks the assumptions first, converts second, and
names the symptom when a known failure mode fires.

Exit codes: 0 clean, 1 warnings worth reading, 2 the export could not be converted.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.convert import convert_scan  # noqa: E402
from app.models import HomeModel  # noqa: E402

# Conversion timestamp is pinned so two runs of this script are byte-comparable —
# that is what makes the idempotency check below meaningful.
FIXED_TIME = datetime(2026, 1, 1, tzinfo=timezone.utc)

SURFACE_ARRAYS = ("walls", "doors", "windows", "openings", "objects")

# Emitted by the converter when a room's wall chain could not be closed into a
# simple polygon (app/convert/README.md, pipeline step 5).
BBOX_FALLBACK_CONFIDENCE = 0.5

findings: list[tuple[str, str]] = []


def note(level: str, message: str) -> None:
    findings.append((level, message))
    print(f"  {level:<4} {message}")


def section(title: str) -> None:
    print(f"\n=== {title} ===")


# --------------------------------------------------------------------------
# 1. Input shape
# --------------------------------------------------------------------------


def describe_shape(export: dict[str, Any]) -> list[dict[str, Any]]:
    section("Input shape")
    if "rooms" in export:
        rooms = export["rooms"]
        note("OK", f"CapturedStructure with {len(rooms)} room(s) (iOS 17 merged scan)")
        # Only meaningful for the structure form — in the single-room form the top level
        # IS a room, so its keys are room keys and get audited by check_surface_encodings.
        unknown_top = sorted(set(export) - {"rooms", "version"})
        if unknown_top:
            note("INFO", f"top-level keys the converter ignores: {unknown_top}")
    elif any(k in export for k in SURFACE_ARRAYS):
        rooms = [export]
        note("WARN", "CapturedRoom (single room) — the merged multi-room API is preferred; "
                     "shared-door adjacency cannot be exercised by a one-room export")
    else:
        note("FAIL", f"neither `rooms` nor surface arrays at top level; keys = {sorted(export)}")
        return []
    return rooms


# --------------------------------------------------------------------------
# 2. Format assumptions — the part that actually matters
# --------------------------------------------------------------------------


def flatten_transform(raw: Any) -> list[float] | None:
    if isinstance(raw, list) and len(raw) == 16 and all(isinstance(v, (int, float)) for v in raw):
        return [float(v) for v in raw]
    if isinstance(raw, list) and len(raw) == 4 and all(isinstance(r, list) and len(r) == 4 for r in raw):
        return [float(v) for row in raw for v in row]
    return None


def check_transform_majorness(surfaces: list[dict[str, Any]]) -> None:
    """A rigid 4x4 has one row/column of (0,0,0,1). Column-major flattening (what
    Swift's JSONEncoder does to simd_float4x4, and what the converter assumes) puts
    that at indices 3/7/11/15 with translation at 12/13/14. Row-major puts it at
    12/13/14/15 with translation at 3/7/11. Getting this backwards is the single
    highest-impact failure mode: it does not raise, it silently rotates every wall.
    """
    col_major = row_major = ambiguous = 0
    for s in surfaces:
        m = flatten_transform(s.get("transform"))
        if m is None:
            continue
        col_tail = all(abs(m[i]) < 1e-4 for i in (3, 7, 11)) and abs(m[15] - 1) < 1e-4
        row_tail = all(abs(m[i]) < 1e-4 for i in (12, 13, 14)) and abs(m[15] - 1) < 1e-4
        if col_tail and not row_tail:
            col_major += 1
        elif row_tail and not col_tail:
            row_major += 1
        else:
            ambiguous += 1

    if row_major > col_major:
        note("FAIL", f"transforms look ROW-major ({row_major} surfaces vs {col_major} column-major). "
                     "The converter assumes column-major — every wall direction will be wrong and "
                     "rooms will collapse to bbox fallbacks. Fix app/convert/roomplan.py first.")
    elif col_major:
        note("OK", f"transforms look column-major ({col_major} surfaces) — matches the assumption")
    if ambiguous:
        note("WARN", f"{ambiguous} transform(s) have no clean (0,0,0,1) row or column — "
                     "non-rigid or a different encoding entirely")


def check_surface_encodings(surfaces: list[dict[str, Any]]) -> None:
    if not surfaces:
        note("FAIL", "no surfaces at all in this export")
        return

    missing_transform = [s for s in surfaces if flatten_transform(s.get("transform")) is None]
    if missing_transform:
        note("FAIL", f"{len(missing_transform)}/{len(surfaces)} surfaces have an unparseable "
                     f"`transform` (sample: {missing_transform[0].get('transform')!r:.80})")

    nested = sum(1 for s in surfaces if isinstance(s.get("transform"), list)
                 and len(s["transform"]) == 4)
    if nested:
        note("INFO", f"{nested} transform(s) use the nested [[4],[4],[4],[4]] form (accepted)")

    bad_dims = [s for s in surfaces if not (isinstance(s.get("dimensions"), list)
                                            and len(s["dimensions"]) >= 2)]
    if bad_dims:
        note("FAIL", f"{len(bad_dims)} surfaces have unusable `dimensions`")

    conf_kinds = {("dict" if isinstance(s.get("confidence"), dict)
                   else "string" if isinstance(s.get("confidence"), str)
                   else "missing") for s in surfaces}
    if conf_kinds == {"missing"}:
        note("WARN", "no `confidence` on any surface — every item will take the default; "
                     "the editor's flag-for-review affordance goes dark")
    else:
        note("OK", f"confidence encodings present: {sorted(conf_kinds)}")

    if not any("parentIdentifier" in s for s in surfaces):
        note("INFO", "no `parentIdentifier` anywhere — openings are matched purely geometrically")

    curved = sum(1 for s in surfaces if s.get("curve"))
    if curved:
        note("WARN", f"{curved} curved surface(s) — v1 degrades these to straight segments")

    if any("polygonCorners" in s for s in surfaces):
        note("INFO", "`polygonCorners` present (non-rectangular walls) — ignored in v1, so "
                     "non-rectangular walls degrade to their bounding segment")

    ignored = sorted({k for s in surfaces for k in s} - {
        "identifier", "transform", "dimensions", "confidence", "category",
        "parentIdentifier", "story", "curve", "polygonCorners", "edges",
    })
    if ignored:
        note("INFO", f"surface keys not in the documented contract: {ignored}")


def check_rooms(rooms: list[dict[str, Any]]) -> list[dict[str, Any]]:
    section("Format assumptions")
    surfaces: list[dict[str, Any]] = []
    for room in rooms:
        for key in SURFACE_ARRAYS:
            surfaces.extend(room.get(key) or [])

    counts = {k: sum(len(r.get(k) or []) for r in rooms) for k in SURFACE_ARRAYS}
    note("INFO", f"surface counts: {counts}")
    if counts["walls"] == 0:
        note("FAIL", "zero walls — nothing can be converted")
    if counts["doors"] == 0:
        note("WARN", "zero doors — the model will have no exits and no route can be computed. "
                     "Doors must be OPEN during capture for RoomPlan to detect them.")
    if counts["windows"] == 0:
        note("WARN", "zero windows — S1.5 acceptance requires >=1 window mapped")

    check_transform_majorness(surfaces)
    check_surface_encodings(surfaces)

    if not any(r.get("sections") for r in rooms):
        note("WARN", "no `sections` labels — every room converts as type 'other' / 'Room N', "
                     "which the user must rename in the editor")

    stories = {s.get("story") for r in rooms for k in SURFACE_ARRAYS for s in (r.get(k) or [])
               if s.get("story") is not None}
    if len(stories) > 1:
        note("FAIL", f"multiple `story` values {sorted(stories)} in one export — v1 assumes one "
                     "floor per scan session. Scan each floor separately and join with stairs "
                     "in the editor.")
    return surfaces


# --------------------------------------------------------------------------
# 3. Conversion result
# --------------------------------------------------------------------------


def polygon_area(polygon: list[tuple[float, float]]) -> float:
    n = len(polygon)
    return abs(sum(polygon[i][0] * polygon[(i + 1) % n][1]
                   - polygon[(i + 1) % n][0] * polygon[i][1]
                   for i in range(n))) / 2


def is_axis_aligned(polygon: list[tuple[float, float]]) -> bool:
    n = len(polygon)
    return all(abs(polygon[i][0] - polygon[(i + 1) % n][0]) < 1e-6
               or abs(polygon[i][1] - polygon[(i + 1) % n][1]) < 1e-6
               for i in range(n))


def point_in_polygon(polygon, point):
    x, y = point
    inside = False
    n = len(polygon)
    for i in range(n):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % n]
        if ((y1 > y) != (y2 > y)) and (x < (x2 - x1) * (y - y1) / (y2 - y1) + x1):
            inside = not inside
    return inside

def report_model(home: HomeModel, export: dict[str, Any]) -> None:
    section("Converted HomeModel")
    
    from app.convert.converter import _slug
    rooms_data = export.get("rooms", [export])
    raw_objects = [obj for r in rooms_data for obj in r.get("objects", [])]
    orig_cats = {_slug(o["identifier"], "obj"): o.get("category", "unknown") for o in raw_objects if "identifier" in o}
    
    rectangles = 0
    for floor in home.floors:
        print(f"  floor {floor.id!r} level={floor.level} height={floor.height_m}m")
        for room in floor.rooms:
            poly = [tuple(p) for p in room.polygon]
            boxy = len(poly) == 4 and is_axis_aligned(poly)
            rectangles += boxy
            flag = "  <- 4-vertex axis-aligned box" if boxy else ""
            print(f"    room {room.id!r} {room.name!r} type={room.type} "
                  f"conf={room.confidence} verts={len(poly)} "
                  f"area={polygon_area(poly):.1f}m2{flag}")
        for op in floor.openings:
            exit_marker = " EXIT" if "EXTERIOR" in op.room_ids else ""
            print(f"    {op.kind:<7} {op.id!r} conf={op.confidence} "
                  f"w={op.width_m}m rooms={list(op.room_ids)}{exit_marker}")
        for obj in floor.objects:
            orig_cat = orig_cats.get(obj.id, "unknown")
            print(f"    object  {obj.id!r} category={obj.category.value} (raw: {orig_cat}) conf={obj.confidence} "
                  f"size={obj.size_m[0]}x{obj.size_m[1]}m height={obj.height_m}m elev={obj.elevation_m}m")

    all_rooms = [r for f in home.floors for r in f.rooms]
    all_openings = [o for f in home.floors for o in f.openings]
    all_objects = [o for f in home.floors for o in f.objects]
    
    converted_ids = {o.id for o in all_objects}
    dropped = [o for o in raw_objects if "identifier" in o and _slug(o["identifier"], "obj") not in converted_ids]
    for d in dropped:
        print(f"    DROPPED {d['identifier']!r} category={d.get('category')}")

    for floor in home.floors:
        for obj in floor.objects:
            inside = any(point_in_polygon(r.polygon, obj.center) for r in floor.rooms)
            if not inside:
                note("WARN", f"Object {obj.id!r} center {obj.center} is OUTSIDE all room polygons")

    section("Acceptance signals")
    if not all_rooms:
        note("FAIL", "no rooms in the converted model")
        return

    fallbacks = [r for r in all_rooms if r.confidence is not None
                 and r.confidence <= BBOX_FALLBACK_CONFIDENCE]

    # Every room being a rectangle is unremarkable on its own — most rooms are rectangles,
    # and the rectangularize step snaps them to axis-aligned on purpose. It only means
    # "the bbox fallback fired everywhere" when the confidences are also poor, because the
    # fallback is what drags confidence down. Warning on the shape alone would cry wolf on
    # every clean scan of an ordinary apartment.
    if rectangles == len(all_rooms) and len(all_rooms) > 1:
        if fallbacks:
            note("WARN", "every room is a 4-vertex axis-aligned box AND confidences are low — "
                         "this is the bbox-fallback-everywhere symptom. Check the transform "
                         "majorness result above and eyeball scan.usdz before trusting the model.")
        else:
            note("INFO", "every room is a 4-vertex axis-aligned box at good confidence — "
                         "normal for rectangular rooms after the rectangularize step")

    if fallbacks:
        note("WARN", f"{len(fallbacks)}/{len(all_rooms)} rooms at confidence <= "
                     f"{BBOX_FALLBACK_CONFIDENCE} (poor polygon quality): "
                     f"{[r.id for r in fallbacks]}")

    exits = [o for o in all_openings if "EXTERIOR" in o.room_ids]
    doors = [o for o in all_openings if o.kind == "door"]
    windows = [o for o in all_openings if o.kind == "window"]
    exterior_doors = [o for o in exits if o.kind == "door"]

    if exterior_doors:
        note("OK", f"{len(exterior_doors)} exterior door(s) — S1.5 acceptance needs >=1")
    else:
        note("FAIL", "no exterior door — routing has nowhere to route TO. S1.5 acceptance unmet.")

    if windows:
        note("OK", f"{len(windows)} window(s) mapped — S1.5 acceptance needs >=1")
    else:
        note("FAIL", "no windows mapped — S1.5 acceptance unmet")

    interior_doors = [o for o in doors if "EXTERIOR" not in o.room_ids]
    if len(all_rooms) > 1 and not interior_doors:
        note("WARN", "multiple rooms but zero interior doors — shared-door pairing did not fire, "
                     "so the rooms are disconnected and every door reads as an exit. This is the "
                     "adjacency assumption in app/convert/README.md failing on a real export.")

    flagged = [o for o in all_openings if o.confidence is not None and o.confidence <= 0.25]
    if flagged:
        note("INFO", f"{len(flagged)} opening(s) flagged for editor review (confidence <= 0.25) — "
                     "this is the designed behaviour, not a bug")


def check_idempotency(export: dict[str, Any], first: HomeModel) -> None:
    section("Idempotency")
    second, _ = convert_scan(export, home_name="Triage", timestamp=FIXED_TIME)
    a = first.model_dump_json(exclude_none=True)
    b = second.model_dump_json(exclude_none=True)
    if a == b:
        note("OK", "same export -> byte-identical HomeModel (S1.5 acceptance)")
    else:
        note("FAIL", "conversion is NOT idempotent — ids are not deterministic functions "
                     "of the input identifiers")


def check_contract(home: HomeModel) -> None:
    section("Contract validation")
    document = json.loads(home.model_dump_json(exclude_none=True))
    schema_path = Path(__file__).resolve().parents[2] / "schema" / "homemodel.schema.json"
    try:
        import jsonschema
    except ImportError:
        note("WARN", "jsonschema not installed — shape check skipped (pydantic still ran)")
        return
    validator = jsonschema.Draft202012Validator(json.loads(schema_path.read_text()))
    errors = sorted(validator.iter_errors(document), key=lambda e: list(e.path))
    if errors:
        for err in errors[:5]:
            note("FAIL", f"schema: {err.message} at {'/'.join(map(str, err.path)) or '<root>'}")
    else:
        note("OK", "passes JSON Schema and pydantic")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("scan", type=Path, help="raw.roomplan.json copied off the device")
    parser.add_argument("--json-out", type=Path,
                        help="write the converted HomeModel here (for the renderer / editor)")
    args = parser.parse_args()

    export = json.loads(args.scan.read_text())
    print(f"Triaging {args.scan}  ({args.scan.stat().st_size / 1024:.0f} KB)")

    rooms = describe_shape(export)
    if not rooms:
        return 2
    check_rooms(rooms)

    try:
        home, warnings = convert_scan(export, home_name="Triage", timestamp=FIXED_TIME)
        for w in warnings:
            note("WARN", f"Converter: {w}")
    except Exception as exc:  # noqa: BLE001 — the whole point is to report, not raise
        section("Conversion")
        note("FAIL", f"convert_scan raised {type(exc).__name__}: {exc}")
        print("\nThe converter is supposed to degrade, never crash. This is a converter bug — "
              "add this export to schema/fixtures/scans/ and write a failing test first.")
        return 2

    report_model(home, export)
    check_idempotency(export, home)
    check_contract(home)

    if args.json_out:
        args.json_out.write_text(json.dumps(json.loads(home.model_dump_json(exclude_none=True)),
                                            indent=2) + "\n")
        print(f"\nHomeModel written to {args.json_out}")

    fails = sum(1 for level, _ in findings if level == "FAIL")
    warns = sum(1 for level, _ in findings if level == "WARN")
    print(f"\n{'=' * 60}\n{fails} FAIL · {warns} WARN · "
          f"{sum(1 for lvl, _ in findings if lvl == 'OK')} OK")
    if fails:
        print("Fix the FAILs in app/convert/roomplan.py before trusting anything downstream.")
        return 2
    return 1 if warns else 0


if __name__ == "__main__":
    raise SystemExit(main())
