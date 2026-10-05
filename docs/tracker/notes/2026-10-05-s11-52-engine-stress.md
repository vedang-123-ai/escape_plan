# S11.52 — Engine and endpoint stress pass

- **Who:** agent C (parallel run of 4)
- **Date(s):** 2026-10-05
- **Status when I stopped:** merged; backend gate green (1249 passed, 1 skipped, 31 deselected); corpus valid.

## What happened
- Threw odd homes at `/routes` (all three perils), `/score`, `/evacuate`, `/diff_obstructions`: no exits, one room,
  one room with no doors, islands, 8 floors stacked by stairs, slivers 1e-9 m tall, 1 µm rooms, rooms at the ±200 m
  bound, 200 rooms, 200 objects, unicode/RTL/NUL and 20 KB names, duplicate ids, bad t0/t1/edge_index, empty floors,
  9 floors, bad stairs, bad and extreme checklist timestamps, NaN/Infinity tokens, non-string `schema_version`.
- Real bugs found and fixed (each with a failing test first and a mutation check):
  1. 200-room home took minutes: `find_bottlenecks` O(rooms³), tornado shelter search recounting exterior walls.
  2. 500s: non-string `schema_version`; checklist timestamp overflowing UTC; NaN/Infinity in any body (422 renderer).
  3. Infinity in `RoutingConstraints` accepted and echoed as `null`.
  4. `/diff_obstructions` skipped exits, and blamed stored `scan_*` objects as new.
- Everything else held: valid odd homes get finite, byte-identical answers; invalid ones get plain 422s.
- Timings (2026 Mac, after fixes): 200-room grid `/score` 0.96 s; 8 floors × 25 rooms `/score` 0.58 s; 200 objects
  piled at doors `/score` 11.6 s.

## Decisions / surprises
- Touched `app/schema_migrator.py` and added an app-wide 422 handler in `main.py` (logged in `docs/decisions.md`).
- The perf fix was checked by hashing every peril's plan plus the score for all fixtures and three grid homes under
  the old and new engine: identical.

## Questions for teammates
- None blocking. Two contract-level items left in BLOCKERS (opening wider than its wall; diff id collisions).

## Next steps
- If the schema is touched again, add the opening-width-vs-wall validator (BLOCKERS, S11.52 findings).
