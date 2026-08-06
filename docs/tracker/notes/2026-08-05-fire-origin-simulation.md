# Fire-origin simulation, colorblind-safe routes, accessibility, drill, print, offline

- **Who:** Claude Code (Lane A: engine, product surface, accessibility), 8 parallel sub-lanes
- **Date(s):** 2026-08-05
- **Status when I stopped:** All eight lanes shipped and committed. Full gate green. Nothing has
  been seen by a human on a device — this is simulator + unit tests only.

## What happened

Eight fenced lanes run in parallel against one working tree, each owning a disjoint file set,
integrated and committed by lane as they landed.

| Lane | What shipped | Commit |
|---|---|---|
| A | `backend/app/routing/hazard.py` + `POST /evacuate`, 31 tests | `76ac7ed` |
| B | `EvacuationPlayback` observable, ignite UI, scrubber, overtaken finding | `222eb3f` |
| E | Drill practice log, corpus-cited reminders, time-to-exit | `6fd6220` |
| D1 | Accessibility on 12 screens; 15 real WCAG failures fixed | `4e1f7e9` |
| F | Printable per-floor PDF, greyscale-proven, + `RouteNarration` | `8c35408` |
| C | Cool routes / warm hazard, dashed geometry, numbered stops | `3411258` |
| G | One failure classifier everywhere, offline proof, drill fire-origin step | `3babbc0` |
| D2 | 3D-scene VoiceOver, `Theme.routeInk` fix, exit/hazard collision fix | `59ba1bc` |
| — | Four cross-fence gaps the lanes could only report | `4503f53` |

### The gate (real output, run by me after every lane landed)

```
python3 backend/corpus/validate.py
  Corpus valid: 11 sources, 6 corpus files, thresholds consistent.

cd backend && python3 -m pytest tests/ -m "not live" -q
  295 passed, 13 deselected in 6.09s          (was 264)

swift test --package-path tools/editorcore
  Executed 261 tests, with 0 failures          (was 192)

xcodebuild test -scheme escape_plan -destination 'iPhone 17 Pro'
  563 passed, 1 failed, 8 skipped              (was 337)
```

The one red was `EntryPointUITests.testScanEntryPointPresentsCaptureFlow`:
`Failed to tap "Home" Button: … is no longer valid after interruption handling`. That is the
**tab bar** button, tapped before any code from this session executes. Re-ran the UI target
immediately: **5 passed, 0 failed**. Recorded in TODO.md as a second face of the known flake —
it is *not* a launch failure, so anything grepping for `Simulator device failed to launch` will
miss it.

## Decisions / surprises

Twelve entries went into `docs/decisions.md`; the ones worth reading twice:

- **The hazard never becomes an AI call, and it never fabricates.** Spread walks the same S1.1
  `NavGraph` `/routes` builds; every path is Dijkstra through the same `_edge_cost`, so S3.4
  profile constraints apply unchanged. Igniting the apartment's only-exit room returns
  `tracks: []` plus the **existing** `no_viable_route` finding — no new failure mode, no
  fabricated path through fire. **No constant was tuned to make anyone escape.**
- **Cool hues are reserved for routes, warm for hazard.** This is now a standing rule the
  renderer lane must honour. Orange route plus red hazard was the textbook deuteranopia
  collision, on exactly the distinction this app cannot blur.
- **The "Illustrative" disclaimer's presence is unconditional**; the server's `is_illustrative`
  flag only picks the wording. Gating a safety caveat on a server boolean makes it deletable by
  a backend bug.
- **Only "twice a year" is corpus-backed.** NFPA and Red Cross both state it; both cite chips
  render; a test reads the corpus markdown off disk so the number cannot drift from its source.
  Every other cadence ships as explicitly-unclaimed user preference.

### Surprises

1. **Two lanes independently found bugs in a third lane's work, through tests they wrote for
   their own remit.** D1's contrast suite caught the printable PDF distinguishing primary/backup
   and door/window **by colour alone**; C's palette re-key exposed that `Theme.routeInk` was
   pinned to a retired orange. Neither would have been caught by the lane that caused it.
2. **The premise I handed lane G was half wrong, and it said so.** I asserted three screens
   needed the cached-routes fallback. `ScoreScreen` and `OnboardingState` never fetch routes at
   all — they POST `/score` and `/analyze`. The real gap was one caller, `DrillScreen`. The
   correction is in the commit message rather than quietly dropped.
3. **Copy-drift is this codebase's recurring failure mode.** `Theme.routeInk` held a dead colour;
   `EvacuationPalette.swift` holds a `routeSecondary` that *still* doesn't match
   `DollhousePalette`. D2's fix asserts the light halves **are** the renderer's `UIColor`s, so at
   least that pair can't drift silently again.
4. **`escape_plan/Models/` is symlinked into the `tools/editorcore` SwiftPM package**, so
   `EvacuationPlayback` had to be Foundation + Observation only — no SwiftUI, no UIKit. That is
   why the Reduce Motion *flag* is injected by the view rather than read by the model.

## Questions for teammates

- **@Codex** — the renderer lane's binding surface is below. The one thing I need back: delete
  `Renderer/Evacuation/EvacuationPalette.swift`'s duplicated `routeSecondary` (`#4A86D8`) and
  read `DollhousePalette.routeSecondary` (`#4180D4`) directly. They currently disagree.
- **@Anish** — `/evacuate` is local-only. The deployed Render backend predates it, so **ignite
  will 404 in any demo filmed against production** until a redeploy. This is the highest-value
  item on the list and it is not a code change.
- **@Anish** — two colour calls worth an eyeball on a device before filming: the darkened
  `exitGreen` (`#16A34A → #0F8140`) and `Theme.caution`, which went from dark amber to light
  amber in dark mode.

## Handoff — the exact interfaces the renderer lane must bind to

1. **`EvacuationPlaybackModel`** (`escape_plan/Models/EvacuationPlayback.swift`, `@Observable`).
   All times are **seconds of modeled time from ignition**. Main-actor by convention, not
   annotation, so `tick(deltaTime:)` stays testable without an actor hop.
   - State: `timeline`, `currentTime_s`, `isPlaying`, `playbackRate`, `duration_s`, `progress`,
     `hasTimeline`, `isFinished`, `isIllustrative`, `originRoomID`, `findings`
   - Hazard queries the drawing layer reads each frame: `untenableRoomIDsNow`,
     `untenableRoomIDs(at:)`, `untenableTime(forRoom:)`
   - Occupant queries: `hasEscaped(_:at:)`, `activeTracks(at:)`, `overtakenTracks`
   - Control: `load(_:)`, `play()`, `pause()`, `togglePlayback()`, `seek(to:)`, `restart()`,
     `tick(deltaTime:)`, `isSteppedMode` (Reduce Motion — degrade, never disable)
   - **Deliberately absent:** position interpolation along a track. `PathSampler` owns that.
2. **Colours** — take hazard from `DollhousePalette.hazardCore` / `hazardEdge` / `hazardHalo`.
   Do **not** introduce a cool hazard tone; routes own cool. For chrome/legend swatches use
   `Theme.hazardInk` (`#C2410C`), not `hazardCore` — `hazardCore` is 2.80:1 on white.
3. **Wiring point** — `HouseScreen.swift` carries a marked `INTEGRATION POINT (renderer lane)`
   comment where `playback` is passed down. One line; `HouseScreen` was outside Codex's fence.
4. **Timeline JSON** is field-for-field `EvacuationTimeline.swift` with one additive
   `findings: [RouteFinding]`. Guarantees: `steps[0].t_s == 0`, `t_s` monotonically
   non-decreasing (**not** strictly — equal consecutive values are legal, do not assert
   strictness), `egress_time_s == steps[-1].t_s`, `steps[-1].kind == "exterior"`, hazard sorted
   by `(untenable_at_s, room_id)`.

## Next steps

1. **Redeploy the backend to Render** so `/evacuate` exists in production. Nothing else on the
   list blocks the demo this directly.
2. Codex binds the figure/hazard layer to `EvacuationPlaybackModel` and fixes the palette
   duplicate.
3. Device-acceptance for the whole session: ignite → playback, scrubber feel, Reduce Motion in
   the camera tour, VoiceOver end-to-end with a real screen reader, and the PDF printed on paper
   in greyscale. Every claim in this note is simulator-and-unit-test evidence only.
