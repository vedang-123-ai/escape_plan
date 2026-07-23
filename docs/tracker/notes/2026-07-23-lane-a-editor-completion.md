# Lane A — editor completion: openings, manual-creation flow, four editor bugs

- **Who:** Claude (lane/editor worktree, ../ep-editor)
- **Date(s):** 2026-07-23
- **Status when I stopped:** all lane acceptance criteria pass; committed on `lane/editor`,
  NOT merged (integration is a separate lane-integrator step).

## What happened

- **Openings are editable at last.** New EditActions `addOpening` / `deleteOpening` /
  `setOpeningKind` / `setOpeningWidth` in `Editor/Core` (+ pure `OpeningPlacement` helper).
  Interior-vs-exterior is **derived from geometry**, never asked: if another room's footprint
  runs along the host wall over the opening's span (collinear-overlap test), the opening
  connects the two rooms; otherwise `room_ids` gets `EXTERIOR` — which is exactly what makes a
  door an exit for the engine. Defaults match the fixtures (door 0.9×2.0 m sill 0, window
  1.0×1.2 m sill 0.8). New validation: same-edge openings must not overlap in t (fixtures
  audited clean first). EditorCore suite 128 → **146 green** (both runners — the SwiftPM
  package sees the same files through its symlinks, nothing to mirror by hand).
- **Stale-render class killed structurally (bugs 2+3).** `HomeModelStore` and `UndoStack` are
  now `@Observable` (`import Observation` — Foundation-family, core stays UIKit/SwiftUI-free;
  editorcore package platform floor bumped macOS 13→14). Every manual `revision += 1` in
  `EditorScreen`/`EditorSceneView` is deleted, not extended. Tap-selection enables Add Stairs
  immediately; redo works on the first tap (both shown in the evidence recording). The
  2026-07-22 acceptance's cosmetic stale-highlight bug is also gone as a side effect —
  selection changes now reach `updateUIView`.
- **Editor UI**: Add menu (Room / Door / Window / Stairs / Floor Above / Floor Below), one-shot
  wall-tap placement tool with hint bar, selection inspector (rename room, room-type picker,
  delete room; opening kind toggle + Interior/Exterior readout + delete; delete stairs), More
  menu (rename home/floor, delete floor), rejection-reason strip. `HitTesting.wallPoint` added
  for placement taps.
- **Bug 4** was already 90% wired by the earlier integration (EditorSceneController implements
  the three seams; EditorSceneView owns the recognizers) — the bridge's stale
  "TODO(integration), renderer not on this branch" header was the real remainder. Header
  rewritten to describe reality; placement tap handler added to the bridge; drags verified live
  in the recorded run (vertex drags with exact vertex-snap join two rooms on camera).
- **Bug 1** (`HomeModelPersisting`) fixed via new `EditorSession` (@Observable wrapper:
  store + undo stack + `wasDeletedExternally`). Protocol is now `@MainActor`; `HomeLibrary`
  doc comment updated; `EditorScreen` registers/unregisters it, dismisses on external delete;
  `UndoStack.reset()` added. Unit-tested in `HomeLibraryEditorSeamTests` (delete-open-home
  clears undo + flags; deleting a different home leaves the editor alone).
- **Manual path proven end-to-end on the simulator** (fresh-erased iPhone 17 Pro, local
  backend on :8001): `ManualBuildRecordingUITests` (env-gated like the golden-path driver)
  builds a two-story home entirely by hand — 4 rooms across 2 floors, 2 interior doors,
  1 exterior door, 2 exterior windows, stairs — asserting the Interior/Exterior inspector
  readouts on-device, exercising undo→redo-first-tap, then opens the Plan tab and waits for
  the engine's plan. `/routes` returns **primary AND secondary routes for all 4 rooms**.
  Evidence in `docs/evidence/`: `lane-editor-manual-build.mp4` (0.5 MB), the saved
  `…-home.json`, and the `…-routeplan.json` engine response.

## Decisions / surprises

(all promoted to docs/decisions.md)

- @Observable in the pure core + macOS 14 floor for tools/editorcore.
- Opening adjacency derived at **creation time only** — drags never rewrite `room_ids`,
  because scan-converted homes may encode adjacency their geometry can't reproduce exactly.
- Kind switch (door↔window) jumps height/sill to the new kind's defaults, keeps width + span.
- The UI-test tap driver inverts the editor camera's deterministic ortho framing to convert
  floor-plan meters → screen taps; SCNView got accessibility id `editor.scene` for it.
- Surprise: the old bridge header claimed gestures were unwired — they weren't; the header was
  stale documentation, not missing code. Trust the code, not the comment.

## Questions for teammates

- Lane B: opening selection currently highlights nothing visible (highlightCenter returns nil
  for `.opening` — deferred from S2.2). The inspector makes selection legible, but a marker
  on the opening itself would read better on camera.
- `setOpeningWidth` exists + is tested but has no UI entry point yet (brief's "if cheap"
  clause — the action was cheap, a good width UI wasn't). See TODO.

## Next steps

Integration: run the `lane-integrator` agent once all lanes land; watch for
`escape_plan/Screens/HomeScreen.swift` (one-line addition: `library:` param) and
`EditorSceneView`'s changed initializer if Lane B touched the renderer call sites.
