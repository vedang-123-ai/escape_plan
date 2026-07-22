# Integration pass — Home/Editor/Plan tabs wired to real code — short title: tab-shell integration

- **Who:** P3
- **Date(s):** 2026-07-22
- **Status when I stopped:** Code complete, compiles by inspection (VSCode SourceKit indexing
  is broken project-wide in this environment — see below); **needs a real Xcode build+run to
  confirm**, per the device-run boxes this closes out.

## What happened

The team's S1.3 (renderer), S2.1 (editor core), and S2.4 (persistence) sessions all landed
fully tested code, but nobody had wired that code into the actual tab screens yet —
`EditorScreen`, `PlanScreen` were still the S0.3 `ContentUnavailableView` placeholders, and
`HomeScreen` only ever showed the bundled `twostory.json` fixture. That's why the user (running
the built app in Xcode) saw an app with 5 tabs where 3 of them visibly did nothing: the
placeholder text, not a crash, was the actual shipped behavior. This session closes that gap —
it's pure integration, no new product decisions, following the `TODO(integration)` comments the
original sessions already left as breadcrumbs (`SceneKitEditorBridge.swift`,
`Persistence/HomeLibrary.swift`, `Renderer/DollhouseDemoView.swift`).

New:
- `Editor/SceneKit/EditorSceneController.swift` — the `EditorSceneAdapter` conformance
  `SceneKitEditorBridge` was written against but that didn't exist yet (S2.1 was built in a
  parallel worktree before S1.3 merged). Uses a fixed top-down **orthographic** camera per
  active floor (not `allowsCameraControl`'s free orbit, which is for the read-only Plan/demo
  views) — that makes screen↔floor-plane unprojection exact via `SCNView.unprojectPoint` and a
  plane intersection at the floor's world Y, instead of an approximation.
- `Editor/SceneKit/EditorSceneView.swift` — `UIViewRepresentable` hosting that controller +
  tap/pan gesture recognizers wired to `SceneKitEditorBridge.handleTap/handleDrag`.
- `Screens/EditorScreen.swift` (rewritten) — real editor: loads a saved home or starts a blank
  one, drives `HomeModelStore`, autosaves through `HomeDocumentStore` on every accepted commit,
  "Add Room" toolbar action, floor picker for multi-floor homes.
- `Screens/HomeScreen.swift` (rewritten) — real `HomeLibrary`-backed list (create/open/delete/
  duplicate), replacing the static fixture display. Tapping a home pushes `EditorScreen(homeID:)`.
- `Screens/PlanScreen.swift` (rewritten) — real read-only 3D view of a saved home via the
  existing (already-tested) `DollhouseSceneView`/`DollhouseSceneBuilder`, with the same
  explode/floor-toggle controls `DollhouseDemoView` proved out on fixtures. **Does not** attempt
  animated route overlays — that's S2.3 and needs new geometry/animation work against the live
  `/routes` backend, not just wiring existing pieces.
- `ContentView.swift` — comment updated to reflect Home/Editor/Plan now being real.

Deliberately not touched: `AssistantScreen` (still a placeholder — needs `ANTHROPIC_API_KEY` set
on Render first, an existing known blocker, not a wiring gap), route visualization (S2.3, new
feature work).

## Decisions / surprises

- **This is why "nothing works"**: every module (renderer, editor core, persistence) had its
  own passing unit tests, but the *tab screens themselves* were never updated past their S0.3
  placeholder bodies. Session-level "CODE DONE" status in `board.md`/`checklist.md` was accurate
  per-module but didn't surface that the product surface (what you actually see running the
  app) hadn't caught up. Worth watching for on future parallel-lane merges: a session isn't
  "visible" until something reads its output, and inline TODO(integration) comments are the
  contract that made this pass mechanical instead of a design exercise.
- Chose an **orthographic top-down camera** for the editor rather than reusing
  `allowsCameraControl`'s free-orbit perspective camera — a free-orbit camera makes exact
  screen→floor-plane unprojection an approximation (parallax depends on tilt), and conflicts
  with drag-to-edit gestures anyway (SceneKit's own pan-to-orbit would fight the editor's
  pan-to-drag-a-wall). This means the editor's visual style (strict top-down) differs from the
  Plan tab's free-orbit dollhouse — that's intentional, not a bug: you're drawing a floor plan
  in one, sightseeing a dollhouse in the other.
- The editor rebuilds the entire SceneKit node graph (`DollhouseSceneBuilder.build`) on every
  accepted commit, including every intermediate step of a live drag. `DollhouseSceneBuilder` is
  a pure function of the model (by design, per its own doc comment) so this is correct, but it
  is **not** proven performant for a live 60fps drag on-device — if dragging feels janky on a
  real phone, the fix is memoizing/patching the SceneKit graph instead of rebuilding, not
  redesigning the seam.
- **SourceKit in this VSCode environment cannot resolve ANY type in this Swift package** — even
  pre-existing, previously-compiling files (`AssistantScreen`, `APIClient`) show "cannot find
  type in scope." This confirms the project's own guidance (CLAUDE.md: "we are in vscode so
  automated testing won't work the way you expect") — these are not real compile errors, just
  a broken local index. The only trustworthy compile signal is `xcodebuild` or Xcode itself.

## Questions for teammates

- @P2: once you've built+run this, the highlight-marker vertical offset
  (`EditorSceneController.highlight`) and the orthographic camera framing/padding are the two
  places most likely to look "off" on a real device — tell me what you see rather than assuming
  it's you.
- @P1: none — no backend or schema changes in this pass.

## Next steps

1. Human: build+run in Xcode (see the message accompanying this note / board.md for the exact
   click-by-click checklist).
2. If Home/Editor/Plan work as described: this clears the on-device acceptance boxes for S1.3,
   S2.1, and S2.4 in `checklist.md` (rows below) — check them by hand after verifying, don't
   take this note's word for it.
3. S2.2 (openings/stairs/undo) is still the next real feature session — it slots into the same
   `EditorScreen`/`SceneKitEditorBridge` seam this pass wired up.
4. S2.3 (animated route visualization) is the next big lift on the Plan tab — new SceneKit path
   geometry + animation, consuming the already-live `/routes` endpoint.
