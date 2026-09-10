# app/convert — RoomPlan → HomeModel scan converter (S1.5)

Pure-function module (no I/O, no globals): `convert_scan(export, home_name=..., timestamp=...)`
takes a parsed RoomPlan JSON export and returns a validated `app.models.HomeModel`.
The FastAPI `/convert` endpoint (S1.6) is a thin wrapper — do not add I/O here.

**Status: built against an ASSUMED input format (below), validated only on synthetic
fixtures in `schema/fixtures/scans/`. S1.4's real device exports must be diffed against
this document before S1.5 can be called DONE.** Anything a real export does differently
gets fixed here first, then in the parser.

## Assumed input format

RoomPlan's `CapturedRoom` / `CapturedStructure` encoded with Swift's `JSONEncoder`
(the standard `try JSONEncoder().encode(capturedStructure)` export path).

### Top level

Either shape is accepted:

- **CapturedStructure** (iOS 17 multi-room merge): `{"rooms": [CapturedRoom, ...], ...}`
- **CapturedRoom** (single-room session): `{"walls": [...], "doors": [...], ...}` —
  treated as a structure with one room.

### CapturedRoom

| Key | Assumed shape | Used for |
|---|---|---|
| `walls` | `[Surface]` | room polygon |
| `doors` | `[Surface]` | door openings |
| `windows` | `[Surface]` | window openings |
| `openings` | `[Surface]` | doorless passages → treated as doors |
| `sections` | `[{"label": "bedroom", "center": [x,y,z]}]` | room name + `RoomType` |
| `identifier` | UUID string (optional) | stable room id |
| `objects`, `floors`, `ceilings`, `version`, `story`, ... | present in real exports | **ignored in v1** |

### Surface

| Key | Assumed shape | Notes |
|---|---|---|
| `identifier` | UUID string | drives deterministic output ids and shared-door matching |
| `transform` | 16 floats, **column-major** `simd_float4x4` (how Swift's JSONEncoder flattens simd) | translation at indices 12/13/14; local x-axis (columns 0–2) is the surface's along-wall direction. A nested `[[4],[4],[4],[4]]` form is also accepted (flattened in order). |
| `dimensions` | `[width, height, depth≈0]` floats | width = extent along local x; height along local y |
| `confidence` | `{"high": {}}` (Swift enum encoding) or bare `"high"` | `high/medium/low` → 0.9 / 0.6 / 0.3 |
| `category` | `{"wall": {}}` / `{"door": {"isOpen": true}}` or bare string | informational; the containing array is authoritative |
| `parentIdentifier` | UUID string or null | doors/windows point at their containing wall |
| `story` | int (optional) | **v1 assumes one story per scan session** (multi-floor = one scan per floor, stairs added in the editor) |
| `polygonCorners`, `curve`, `edges` | present on iOS 17 exports | **ignored in v1** (non-rectangular walls degrade to their bounding segment) |

### Coordinate conventions

- RoomPlan/ARKit world space is right-handed, **y-up**, meters.
- Floor-plan projection used here: `plan = (world.x, world.z)`. Winding is normalized
  to CCW afterward (the schema requires CCW), so the handedness flip is harmless.
- A wall's 2D segment = `center ± (local_x_axis projected to plan) * width/2`.
- Floor elevation per room = the minimum of `(center.y − height/2)` over its walls;
  window `sill_height_m` = opening bottom minus floor elevation.

### Shared-door / adjacency assumptions

A door shared between two rooms of a merged CapturedStructure is assumed to appear in
**both** rooms' `doors` arrays, either

1. with the **same `identifier`** (merged-structure dedup), or
2. with different identifiers but **coincident geometry** (plan centers within 0.35 m,
   directions parallel within ~25°).

Both paths are implemented; real exports decide which one actually fires.
Unpaired doors/windows/openings are emitted as `[room, "EXTERIOR"]` — with a scan of a
subset of the home this can mislabel interior doors as exits; that is exactly the class
of error the Phase-2 editor is designed to let the user correct.

## Conversion pipeline (per room)

1. Project each wall to a 2D plan segment; drop degenerate (<1 cm) segments.
2. Chain segments end-to-end greedily (nearest endpoint, flipping as needed); gaps up
   to any size are closed by midpoint-welding, but gaps > 0.25 m cost polygon quality.
3. Merge near-collinear consecutive edges (< 8° turn).
4. Rectangularize: find the dominant wall direction (length-weighted, mod 90°); snap
   every edge within 12° of a dominant axis onto it and re-intersect neighboring edges.
5. Normalize: dedupe vertices, force CCW, verify the polygon is simple. If anything is
   degenerate, **fall back to the axis-aligned bounding box** of the wall endpoints and
   mark the room low-confidence — never crash, never drop the room.
6. Map each door/window/opening to `(room_id, edge_index, t0, t1)` on the nearest
   roughly-parallel polygon edge; an opening whose center sits > 0.5 m from every edge
   is still attached to the nearest edge but demoted to `confidence ≤ 0.25`
   (flagged-for-review, never dropped).

Room `confidence` = mean RoomPlan wall confidence × polygon quality (gap/fallback
penalties). All output ids are deterministic functions of the input identifiers
(uuid5), so conversion is idempotent: same export → byte-identical HomeModel.

## Known failure modes (to verify against S1.4 real exports)

- Column-major transform assumption — if real exports encode row-major, every wall
  direction is wrong (symptom: polygons collapse to bbox fallback everywhere).
- Curved walls (`curve != null`) become straight segments.
- Rooms scanned with missing walls (open-plan) rely on the fallback bbox.
- `sections` labels may be absent → rooms come out as `type: "other"`, "Room N".
- Two doors legitimately 0.35 m apart in different rooms could be falsely paired by
  proximity if they lose their UUIDs.
- Object transformations are assumed to map identically to surface transforms.
- Dropped object categories (chairs, bathtubs) could be desired in the future, requiring a migration.
- Elevation extraction relies on a < 0.01m floor threshold logic that might misidentify rugs as floating.
