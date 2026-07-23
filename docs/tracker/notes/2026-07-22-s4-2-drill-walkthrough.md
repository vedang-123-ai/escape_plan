# S4.2 — Drill / practice mode (guided walkthrough half)

- **Who:** P3 (Claude)
- **Date(s):** 2026-07-22
- **Status when I stopped:** CODE DONE — walkthrough built and unit-tested; nav entry point and
  the two-profile device acceptance remain.

## What happened

Built the playbook's recommended format, small, entirely in new `escape_plan/DrillMode/`:

- `DrillSession.swift` — pure state machine: profile's primary `Route` (from `/routes`, fetched
  with `profile_id`) → steps: start card → one `.move` per waypoint pair → `.stairs` card for
  floor crossings (paired `stair` waypoints, same `node_id`) → terminal `.meetingPoint`.
- `DrillInstructions.swift` — instruction-card copy paraphrased from
  `backend/corpus/escape-planning-nfpa.md`; safety claims carry inline
  `[cite: nfpa-escape-planning]` / `[cite: usfa-escape-plans]` tags (rendered verbatim + id
  chips, AssistantScreen precedent); navigational lines are uncited.
- `DrillScreen.swift` — `DrillScreen(homeID:)`: profile picker → 3D dollhouse with the S2.3
  overlay (`includeSecondary: false`) → each "Next" flies `RouteOverlay.startTour` along a
  two-waypoint slice of the engine's route (camera path only — no route computed client-side) →
  meeting-place card → **"Mark plan as practiced"** flips `practice.drill_recent` in
  `ChecklistStateStore`; ScoreScreen's next `/score` POST moves the number (backend math only).
- `escape_planTests/DrillModeTests.swift` — 8 tests: step derivation, stair-crossing handling,
  advance/back clamping, every citation id resolves against the real `sources.json`, practiced
  state persists across "relaunch" and leaves other checklist items alone.

Gate: full `escape_planTests` **TEST SUCCEEDED** on the iPhone 17 Pro simulator, EditorCore
128/128, backend 196 green, corpus valid. `swift-scenekit-reviewer` pass: no must-fixes; its two
should-fixes (onAppear re-entry orphaning a live drill on tab switches; silent dead-end on a
`home_id` mismatch) and a continuous-rendering battery nit were fixed and re-verified green.

## Decisions / surprises

- Built ahead of S4.1 (paper prereq) — no shared code; recorded in decisions.md.
- Only `practice.drill_recent` is auto-flipped; `practice.meeting_point` stays a manual
  ScoreScreen toggle (the drill can't verify the family actually agreed on a spot).
- The test-coverage lane's board note about "one WIP DrillSessionTests failure" was this lane
  mid-flight (same working tree); it's fixed — the suite is green including DrillModeTests.
- The engine's final exterior waypoint reuses the exit's x/y, so the last flight segment is
  sub-0.1 m and `startTour` completes synchronously — card still shows, gracefully no flight.

## Questions for teammates

- @P2/@flow-owner: `DrillScreen.swift` carries the `TODO(integration)` — wire "Practice drill"
  into HomeScreen's per-home swipe/context menu (mirror Score/Profiles
  `.navigationDestination(item:)`), or a button in PlanScreen's routeControls.

## Next steps

Device acceptance (leave the checklist boxes unchecked until a human watches it):
1. Wire the entry point (TODO above), build+run on the simulator/device.
2. On a home with ≥2 profiles (twostory: Grandpa vs Maya), complete the drill for BOTH —
   different bedrooms should give visibly different camera paths; stairs step should appear for
   the upstairs profile.
3. Tap "Mark plan as practiced", open ScoreScreen → score must move (practice component, +5
   style bump per `docs/preparedness-score-weights.md`), then kill/relaunch → still practiced.
