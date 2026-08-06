# Evacuation renderer — closing the seam between the two parallel lanes

- **Who:** P1
- **Date(s):** 2026-08-05
- **Status when I stopped:** Wired and green. Figures, hazard and the playback camera are now
  reachable in the running app. Nothing here has been seen on a device.

## What happened

Two lanes had run in parallel against a shared contract (`Models/EvacuationTimeline.swift`):
the engine lane (hazard spread, `/evacuate`, `EvacuationPlaybackModel`, ignite UI, scrubber)
and a renderer lane (articulated figures, gait math, hazard visuals, playback camera). The
renderer lane hit its usage limit mid-verification and stopped.

Picking it up:

**The renderer lane's work was real.** Its narration claimed interfaces that the session-start
git status didn't show, so I checked rather than assumed — the engine lane had in fact
committed all ten of its commits, and every file the renderer claimed to consume existed. All
16 of its evacuation tests execute and pass.

**One broken thing.** `EvacuationSceneLayerTests.swift` and `EvacuationRenderingTests.swift`
guarded their *bodies* with `#if !SWIFT_PACKAGE` but left `import UIKit` / `import SceneKit`
outside the guard. Those files live in `escape_planTests/EditorCore/`, which is symlinked into
the macOS SwiftPM harness — so UIKit-on-macOS failed the **entire** fast runner, not just those
files. The renderer lane never saw it because it only ever ran the iOS-only
`-only-testing:` invocation. Moved the imports inside the guard.

**The actual gap: nothing was wired.** No screen referenced `EvacuationPlaybackCoordinator`,
`HazardLayer`, `EvacuationTrackLayer` or `PlaybackCameraController`. Both lanes had built to a
well-designed seam — `UnifiedSceneController.bindEvacuationPlayback(…)` — and neither could
call it, because the caller lives in `Screens/`, which was fenced to the other lane. Every
component was tested and none of it was on screen. `HouseScreen.attach(_:)` now binds it.

**A performance bug the renderer lane flagged but couldn't fix.** `EditorSceneView.updateUIView`
rebuilt the whole dollhouse unconditionally, on the documented reasoning that a rebuild is cheap
and only follows an edit commit. Playback broke that assumption: `HouseScreen`'s body reads the
playback clock, so `@Observable` invalidates the view on every tick — meaning the dollhouse,
route overlay, people layer and animated evacuation layers were being torn down and rebuilt
sixty times a second, restarting the very animation they were drawing. Added
`UnifiedSceneController.rebuildIfNeeded(home:activeFloorId:)`, gated on `(home, activeFloorId)`
equality. Safe because `DollhouseSceneBuilder.build` is a pure function of exactly those inputs.

## Decisions / surprises

- **`rebuildIfNeeded` is a new method, not a change to `rebuild`.** Explicit callers keep force
  semantics; only the per-update path memoizes. `rebuild` records the inputs itself, so the two
  entry points cannot disagree about what is on screen. → `decisions.md`.
- **The ordinary route overlay is suspended while a timeline is loaded.** The pre-fire route
  answers a different question than the fire-aware one; drawing both at once is the one way this
  screen could actively mislead. Restored on clear.
- **Evacuation renderer issues get their own `@State`**, not merged into `overlayIssues` —
  `applyOverlay` overwrites that array wholesale, so two writers would erase each other every
  redraw. The change-comparison reads from the stable holder box, because the handler can fire
  from inside a rebuild where a captured `@State` read is stale.
- **Surprise: a fenced TODO item was already stale.** The tracker flagged
  `EvacuationPalette.swift` as duplicating `routeSecondary` as `#4A86D8` and told this lane not
  to touch the file. It had already been fixed — every colour references `DollhousePalette`, and
  `0x4A86D8` appears nowhere in the tree. Marked verified rather than carried forward.
- The fence that made the lanes safe is exactly what left the seam uncalled. Worth planning for
  next time: give one lane explicit ownership of the integration point, or schedule an
  integration pass that owns both sides.

## Questions for teammates

- @P2 `/evacuate` still exists only locally — the deployed Render service predates it, so ignite
  will 404 against the demo backend. That deploy is the last thing between this and a filmable
  demo.

## Next steps

1. Deploy the backend so `/evacuate` is reachable (already on the tracker).
2. Device pass: confirm figures move continuously rather than restarting, that editing still
   redraws immediately after a commit, and that the 8-figure frame budget holds on hardware —
   the 0.16 ms/update figure is a simulator number.

## Verification

Full gate, real output:

- `swift test --package-path tools/editorcore` — **261 passed, 0 failures**
- `xcodebuild test … -only-testing:escape_planTests` — **465 XCTest + 99 swift-testing passed**,
  `TEST SUCCEEDED`
- `python3 -m pytest backend/tests/ -m "not live"` — **295 passed**, 13 deselected
- `python3 backend/corpus/validate.py` — 11 sources, 6 corpus files, thresholds consistent

Not verified: anything on a physical device.
