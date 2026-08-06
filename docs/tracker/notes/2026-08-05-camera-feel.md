# Camera interaction feel: orbit, pan and pinch in the 3D dollhouse

- **Who:** Claude Code
- **Date(s):** 2026-08-05
- **Status when I stopped:** All ten items addressed or explicitly left open with a reason. Full
  gate green. **Nothing has been felt by a human** — "feel" is not something `xcodebuild` can
  report, and one item (#10 frame-time profiling) needs hardware I do not have.

## What happened

The scene rendered correctly; the controls did not feel connected to the finger. Ten defects,
four commits, in the order the brief specified — math and frame-time defects first, tuning
constants last, because the constants are only judgeable once the defects are gone.

| Commit | What |
|---|---|
| `d83c184` | #1 pan projection math, #2 cached pinch anchor, #3 one transform write, #4 redraw model, #6 pan inertia |
| `2b0cd0d` | One shared `CameraGestureDriver`; #7 arbitration; #4/#5 host side |
| `a94996a` | #5 instrumentation and its measurement; the one part of #10 that needed no hardware |
| `7bcaadf` | #8 movement limits, #9 orbit rate and axis-lock threshold, plus 16 new tests |

### Step 0 — which gesture host is live

**Both.** `HouseScreen:402` mounts `EditorSceneView`; `DrillScreen:136` mounts
`UnifiedSceneView`. The brief's guess that `UnifiedSceneView` might be dead code was wrong, so
deleting it was not an option — and everything the brief predicted would follow from it being
live was true on the drill surface: no inertia, no axis-lock reset, no rubber-band spring-back,
and `rig.onChange`/`rig.continuousRenderingSink` never assigned, so any frame the rig drove
itself was computed and never drawn. Both hosts now call one `CameraGestureDriver`.

### The gate (real output, run by me)

```
python3 backend/corpus/validate.py
  Corpus valid: 11 sources, 6 corpus files, thresholds consistent.

cd backend && python3 -m pytest tests/ -m "not live" -q
  295 passed, 13 deselected in 2.44s          (unchanged)

swift test --package-path tools/editorcore
  Executed 270 tests, with 0 failures          (was 261)

xcodebuild test -scheme escape_plan -destination 'iPhone 17 Pro'
  ** TEST SUCCEEDED **
  xcresulttool: 594 total, 586 passed, 0 failed, 8 skipped   (was 563 passed / 1 failed / 8 skipped)
```

Fully green — the known `EntryPointUITests` tab-bar flake did not reproduce this run. That is
one clean run, not evidence the flake is gone.

## Decisions / surprises

Nine rows went into `docs/decisions.md`. The ones worth reading twice:

- **#1 was the big one, and it failed silently.** `truck` converted screen points to meters
  with perspective math unconditionally while `CameraTuning.usesOrthographic` is `true`. The
  wrong answer still *moves* the house — just at a constant wrong ratio — so it reads as
  "panning feels floaty" rather than as a bug. `CameraRigModel.Projection` is an enum
  specifically so a call site cannot default past naming its projection.
- **#2 is a correctness fix, not just a performance one.** Zoom-toward-anchor is defined
  against a *fixed* point; re-resolving it per frame let the anchor crawl under the fingers
  while also running 60–120 full-scene hit tests a second.
- **The new `simdTransform` had to be provably identical to `look(at:)`**, because
  `PlaybackCameraController` restores `pointOfView` to this node when a tour ends — any
  divergence shows as a jump. `testTransformMatchesWhatLookAtProduced` compares all sixteen
  matrix components against a real `look(at:)` node rather than trusting the derivation.

### Surprises

1. **Two writers were fighting over `scnView.rendersContinuously`.** HouseScreen set it true
   for the route pulse; the rig's sink set it false the instant inertia stopped. So finishing an
   orbit silently froze the route pulse until something else re-enabled it. This was an existing
   rendering bug, not merely the starvation issue #4 describes.
2. **The rubber band never sprang — it snapped.** `settle()` ran as an `SCNTransaction`
   animation, which interpolates the node but does not ask anyone to draw the intermediate
   frames. On a static scene exactly one redraw happened, at the end. Nothing in the brief
   predicted this; it fell out of thinking through what "continuous rendering while a spring is
   running" actually means.
3. **The loosened limits would have been a bug on their own.** `isOffHome` fired above
   `0.15 × extent` drift against an apron of `0.25` — over half the pan range — and below
   `0.7 × extent` distance against a floor of `0.8`, i.e. on any zoom-in at all. Loosening the
   limits without loosening these would have pinned the recenter chip on permanently.
4. **#5 measured out at zero, which was not what the brief expected.** HouseScreen's ~40
   `@State` vars do not churn during a plain orbit. See below.
5. **`RouteRedrawAfterEditUITests` can no longer pass.** It detects the route by counting
   *orange* pixels; routes have been blue since the 2026-08-05 colour pass. It is skipped
   unless `ROUTE_REDRAW=1`, so it does not gate CI — which is precisely why it will stay broken.
   Recorded in TODO.md; out of scope here (it needs a live backend).

## The #5 measurement

`-editor.gestureInstrumentation YES` counts SwiftUI update passes and how many landed while a
camera gesture was in flight, surfaced on the scene view's `accessibilityValue` (log streams do
not reach a cloned test simulator — decisions.md 2026-07-23). `GestureFrameCostUITests` drives
a real press-drag and reads it back. On iPhone 17 Pro, idle house, no routes, no playback:

```
before=(updates: 4, duringGesture: 0)
after =(updates: 4, duringGesture: 0)
provokedByDrag=0  landedOnGestureFrames=0
```

So the starvation risk is real only when something genuinely changes mid-drag — a playback
tick, a route fetch landing — which the new deferral gate covers. The test asserts the zero, so
a future `@State` read in the wrong place shows up as a failure rather than as "feels worse
lately". **Caveat: measured with no routes drawn and no playback running**, which is the
cheapest case, not the worst one.

## Questions for teammates

- **@Anish** — every "feels better" claim here is inference from corrected math, not
  observation. Four things to check on a device, in this order: (1) hold a corner of the house
  under your thumb and pan — it must stay under your thumb, in both orientations and both
  projections; (2) pinch and confirm the point between your fingers does not crawl; (3) flick to
  orbit and confirm it coasts and eases out; (4) pan to the edge and confirm the band springs
  back visibly rather than snapping. If (1) still fails, the projection branch is reading the
  wrong camera and nothing downstream matters.
- **@Anish** — the tuning numbers (apron `0.6`, distance `0.35…4.0`, orbit `0.6 π`, axis lock
  20 pt) are a starting point. The orbit rate and the axis-lock threshold interact; move them
  together.

## Next steps

1. **Profile frame time on the oldest supported device** — #10 is genuinely not done. MSAA 4X,
   SSAO and the pulse shader all still run during gestures. Both levers are already isolated
   behind `CameraGestureDriver.onPhaseChange`; nothing was changed on guesswork because
   dropping MSAA mid-drag is a visible change to a scene the brief said not to alter.
2. Device pass on the four feel checks above, then tune #8/#9 by hand.
3. Fold recognizer installation into `CameraGestureDriver` as well — both hosts still duplicate
   their `shouldRecognizeSimultaneouslyWith` policy, so a third surface could still arrive with
   a fourth gesture model.
