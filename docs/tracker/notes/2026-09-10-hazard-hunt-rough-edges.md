# S7.6 follow-up — the hazard hunt's three rough edges

- **Who:** P3
- **Date(s):** 2026-09-10
- **Status when I stopped:** fixed and green on EditorCore (295 tests, up from 275). **The iOS
  target has NOT been compiled** — `HazardHuntView.swift` was rewritten and only `xcodebuild`
  can typecheck it. See Next steps.

## What happened

Walking the hunt to explain it in plain terms surfaced three defects. All three came from the
same root cause: question generation lived inside `HazardHuntView`, where `swift test` cannot
reach it and the iOS suite never exercised it.

1. **The water-heater question was inverted and silently defeated its own rule.**
   "Water heater — strapped?" → Yes created a heater with `secured: true`; **No created nothing
   at all.** The user with an unstrapped water heater answered honestly and the model learned
   nothing, so `water_heater_unsecured` (the rule that cites FEMA on gas-line rupture) could
   never fire from the hunt. The only route to that finding was knowing to add the object by
   hand afterwards.

2. **Every created object landed at the room centroid.** All four hazard rules are distances, so
   a correctly-identified bookcase in the wrong place is a wrong answer.

3. **It asked cold.** The scan's objects were ignored, so a room already containing a 1.9 m
   `storage` unit was still asked "anything tall and heavy near the bed?" — inviting a duplicate
   object on top of the one RoomPlan had already measured.

**The fix.** `HazardHuntPlan` (new, `escape_plan/Editor/Core/`, Foundation-only so EditorCore
compiles it) returns `[HazardHuntQuestion]` for a room: each carries the `EditAction`s for Yes
*and* for No, an optional `requiresYesOf` for follow-ups, and an optional `placementHint`. The
view walks rooms, renders, dispatches, focuses. 20 new tests.

Specifically: water heater is now two questions with a live No branch; a tall scanned
`storage`/`wardrobe` produces a *relabel* question instead of a cold add; the cold fallback is
only asked when the room has nothing topple-prone; the fallback bookcase is placed beside the
scanned bed (first side that fits inside the polygon); mounted objects go at the bed's center
with `elevation_m`; anything the app cannot place says so instead of guessing.

## Decisions / surprises

- Promoted to `docs/decisions.md` (2026-09-10) in full.
- **The surprise worth carrying:** defect 1 was green in every suite for a day, because the only
  thing that could have caught it was a test of the question list, and the question list was
  inside a view. The repo's Swift rule about keeping logic out of views is usually argued on
  undo/redo grounds; this is the safety-correctness argument for the same rule.
- Scope discipline held: no new colour (`DS.supporting` for the hint), no new `EditAction`, no
  schema change — every answer is expressed in the vocabulary S7.6 already added.
- `Polygon` (the `[Point]` typealias) is ambiguous inside the test target and has to be spelled
  `[Point]` there; a `static` helper used as a default argument must be `nonisolated` under the
  `@MainActor` test class. Both cost a compile cycle.

## Questions for teammates

None. This is a defect fix inside an already-approved session's surface.

## Next steps

1. **Compile the iOS target** — `HazardHuntView.swift` was rewritten and nothing has typechecked
   it. Owner-gated (simulator restriction), one `xcodebuild` run. Until then this is
   "EditorCore-green, iOS-unverified" and `BLOCKERS.md` §4 says so.
2. On the device pass, walk the hunt in a real room and confirm the relabel question fires
   against a real scanned `storage` unit — the whole seeding path is untested against real scan
   output, because no real scan has ever reached it.
3. Still open and unrelated to this fix: routing is elevation-blind, so the mounted object this
   hunt now places correctly is still treated as floor-blocking by the router (`BLOCKERS.md` §3).
