# S2.2 — Editor: openings, stairs, undo

- **Who:** P3
- **Date(s):** 2026-07-22
- **Status when I stopped:** Code done, unit-tested (115/115 editor-core tests + full `escape_planTests` suite pass on a real simulator), builds clean. On-screen gesture/tap acceptance not run — left for a human.

## What happened

Closed all three S2.2 gaps that S2.1's code explicitly earmarked as "S2.2's job":

1. **Opening drag** — `EditAction.dragOpening(openingId:t:)`, where `t` is the requested
   midpoint position (normalized `[0,1]`) along the opening's host wall. The `HomeModelStore`
   reducer derives `t0`/`t1` from `t` and the opening's existing `width_m`, clamping into
   `[0,1]`. `SceneKitEditorBridge`'s `.opening` branch (previously `return nil`) now projects the
   drag point onto the host wall edge via `Geometry.closestPointOnSegment` to get `t`.
2. **Stairs** — `EditAction.addStairs(fromFloorId:fromRoomId:toFloorId:toRoomId:footprint:kind:)`
   + `deleteStairs(stairsId:)`. Reducer checks both floor/room ids resolve;
   `EditorValidation.validateStairs` (unchanged) is the real gate. Minimal toolbar UI: select a
   room, tap "Add Stairs," pick a room from a sheet listing the floor above.
3. **Undo/redo** — new `Editor/Core/UndoStack.swift`, built on `HomeModelStore.Commit`'s
   before/after snapshots. Continuous drags are coalesced into one undo entry per gesture via
   explicit `beginCoalescing`/`endCoalescing` calls bracketing `SceneKitEditorBridge.handleDrag`'s
   `.began`/`.ended` states (not by matching the action's subject — that can't tell "still
   dragging" from "new drag on the same thing"). `EditorScreen` gained Undo/Redo/Add Stairs
   toolbar buttons.

Added `Selection.stairs(stairsId:)` (structurally needed for `deleteStairs`); its SceneKit
highlight is a no-op, same as the pre-existing `.opening` case.

**Verification:** `swift test --package-path tools/editorcore` (115/115 pass, incl. 20 new tests
for opening drag / stairs / undo coalescing). Then discovered a real iOS 26.5 simulator runtime
IS installed on this machine (contradicting every prior session's assumption) — ran
`xcodebuild build` (clean), `xcodebuild build-for-testing` (clean), and
`xcodebuild test -destination 'platform=iOS Simulator,id=...'` for the whole `escape_planTests`
target: everything passes except one pre-existing, unrelated failure
(`DollhouseRendererTests.testBundledFixturesMatchSchemaFixtures`, references a path deleted in
the S2.1×S0.3 merge — not touched by this session). Also booted the simulator, installed, and
launched the app — reaches the Home tab without crashing.

## Decisions / surprises

All promoted to `docs/decisions.md`: the `dragOpening(t:)` action shape and the deliberately
unclosed opening-overlap gap; the stairs action shape and the deliberately unclosed
footprint-containment gap; the gesture-bracketing design for undo coalescing and why
subject-matching doesn't work; and — the big surprise — **a simulator is actually installed now**,
which every S1.3–S2.4 session assumed didn't exist. I did not go back and re-open those sessions'
device-acceptance boxes; flagging it here and in decisions.md for the team to decide whether to
revisit them.

No schema changes. No new dependencies.

## Questions for teammates

- @P1/@P2: S1.3, S1.4, S2.1, S2.4 all have unchecked "on-device" acceptance boxes citing "no
  simulator runtime installed" — that's no longer true on this machine. Worth a pass to actually
  run those now that a real simulator exists, rather than leaving them permanently deferred.
- @P2: the `DollhouseRendererTests.testBundledFixturesMatchSchemaFixtures` failure (references
  `escape_plan/Resources/Fixtures/`, which doesn't exist — only `escape_plan/Fixtures/` does)
  looks like dead test code from the S2.1×S0.3 merge cleanup. Worth a quick look/deletion in a
  Renderer-owned session — didn't touch it here since Renderer wasn't in scope.

## Next steps

- A human (ideally on a real device, but the simulator works now) should run the three acceptance
  criteria by hand: drag a door/window along a wall and confirm it slides smoothly and stays
  parametric; place stairs between a hand-built 2-story's floors via the new toolbar sheet and
  confirm the 3D stairs render (renderer side already existed); do ~20 mixed operations
  (adds/drags/deletes across rooms/openings/stairs) and confirm Undo/Redo stay consistent and
  autosave keeps up.
- Consider whether the opening-overlap and stairs-footprint-containment gaps (both pre-existing/
  deliberately unclosed, see decisions.md) are worth a follow-up.
