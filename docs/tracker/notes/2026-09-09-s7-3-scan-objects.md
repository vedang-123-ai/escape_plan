# S7.3 - Scan objects: stop throwing them away

## Context
Carried RoomPlan's detected objects through the whole pipeline: CapturedRoom.objects → raw export (formatVersion 3) → /convert → FloorObject entries on the scanned floor.

## Decisions / surprises
- We drop chairs, sinks, toilets, bathtubs, and stairs entirely. None of these present a hazard in our corpus, and keeping them would clutter the payload.
- We map television->tv, stove/oven/fireplace->heat_source, and refrigerator/dishwasher/washerDryer->appliance.
- Bounding box elevations are computed as `obj.center_y - obj.dimensions[1] / 2.0 - host_floor_y`. Anything < 0.01m is clamped to 0.0 to account for floor-standing noise.

## Walkthrough after all changes
- **Data/code path**: iOS now exports `objects` in `formatVersion` 3. The backend converter parses these `RPObject`s, checks for major/minor geometries via `SURFACE_ARRAYS`, and maps them to `FloorObject` using a strict dictionary. Unsupported categories fallback to `other` or are explicitly ignored.
- **Testing**: We expanded `synthetic-bungalow.roomplan.json` to include 7 objects, including mixed-confidence and unknown-category to prove mapping. Validation is green, `test_convert.py` covers category mapping exhaustively, and idempotency is preserved.

## Schema Contract Guardian Findings
```
I have verified the `FloorObjects` emitted by `backend/app/convert/converter.py` and `backend/scripts/triage_scan.py`.

- The `convert_scan` function correctly converts RoomPlan iOS 17 (formatVersion 3) `RPObject` outputs into the 2.1 `FloorObject` schema.
- The `elevation_m` property is correctly extracted from the raw object's 3D bounding box (calculated as the relative height of its base above the floor), clamped at `minimum: 0`, matching the JSON schema.
- The `mounted` property defaults to `false` via the `FloorObject` pydantic model, correctly matching the schema's `default: false`.
- The parsed `ObjectCategory` choices from `RoomPlan` are safely mapped through `_OBJ_CATEGORY_MAP`, safely falling back to `other` and exactly satisfying the 11 enum cases allowed in schema 2.1.
- `triage_scan.py` has been updated cleanly to read and print the new `objects` array and `elevation_m`.

ZERO CONFIRMED BUGS.
```
Disposition: The Guardian's findings confirm that the schema contract is satisfied. No fixes were required.
