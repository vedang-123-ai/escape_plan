# Demo trim 2 — the drill becomes House's fire playback; old drill, AR walk and practice log deleted

- **Who:** P1 (Anish's session, agent-run)
- **Date(s):** 2026-10-03
- **Status when I stopped:** **trim 2 DONE**, merged to `main` and pushed. Nothing left on this branch.

## What happened

Anish's design, "Reuse House" (2026-10-02, changed after the plan's Step 2 was written): no new drill screen and no
SceneKit change. "Run a fire drill" now opens the existing House screen straight on its **Fire simulation** tab.

- **Entry points.** `AppRouter.openFireDrill(homeID:)` makes a `HouseRequest` with `opensFireSimulation`; `ContentView`
  passes it to `HouseScreen(startsOnFireSimulation:)`, which seeds `dockMode = .fire`. Home's "Run a fire drill" card,
  Home's and Tasks' `.drill` task button all call it. The `drillHomeID` pushes are gone.
- **Home card subtitle:** "Never practised" → "See everyone's way out of a fire" (two lines allowed).
- **"Who does what"** in House's fire dock, once a simulation is loaded: one card per person with their start room, the
  rooms they pass, the way out, the time they are outside, and a warning when the engine set `overtaken_by_hazard`. One
  VoiceOver element per card; Dynamic Type (scaled icon column, text wraps); colours from `Theme` only (route ink for
  the way through, exit ink for the way out, hazard ink for the warning icon and border; the warning words stay full
  contrast). The words come from `Editor/Core/EvacuationJourney.swift`, pure Foundation: each of the server's
  `OccupantTrack.steps` points is put in a room with the editor's point-in-polygon test, repeats fold, points in no room
  are skipped. It narrates the engine's route and never computes one. Worked out once per timeline, not per frame.
- **No people yet:** the engine puts one stand-in per room, named after the room. The fire dock now says "No one is added
  to this home yet, so the simulation puts one person in each room. Add your household from the Home tab." This replaces
  the old drill's empty state (AUD-020).
- **Speeds** 0.25×, 0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×; `rateLabel`/`spokenRateLabel` moved into `EvacuationPlaybackModel`
  so they are tested (VoiceOver hears "Quarter speed", "Three quarter speed", "1.25 times speed", "Double speed").
- **`practice.drill_recent`** is ticked by hand like the other manual items: its row circle is a button, its sheet's main
  button is "Run a drill" (opens the fire simulation) and a second button, "We practiced it for real", marks it done.
  No auto-tick; `scoring=False`.
- **No way out:** someone the engine cannot get out has no track, only a `no_viable_route` finding; "Who does what" lists
  those first, in the engine's words, under "No way out found". "Simulation check" now sits above the person cards.
- **Old reminders:** a phone that scheduled a practice reminder in an earlier build has it removed once at launch
  (`RootView`; ids `practice-reminder.<home>`).
- **Deleted:** `DrillMode/` (7 files), `Drill/` (4, incl. `SemanticMatcher` and the EditorCore symlink),
  `Editor/Core/DrillNotice.swift`, `Persistence/DrillLogStore.swift`, `Persistence/PracticeReminderScheduler.swift`,
  `Renderer/UnifiedSceneView.swift` (only `DrillScreen` used it; dead after the change), `ReadinessStore.lastPracticed` /
  `refreshLastPracticed`, the Tasks reminder card. Tests: `DrillModeTests` (9), `DrillPracticeTests` (33),
  `DrillNoticeTests` (10), `SemanticMatcherTests` (8), `SemanticMatcherRotTests` (2), `WallGroupingTests` (11 — its
  `WallGrouping` lived in `SemanticMatcher.swift` and only the AR matcher used it).
- **Offline note:** "the practice drill and its log" is no longer promised offline; "the fire drill simulation" is listed
  as needing the server.
- **UI tests:** `ProfilesEntryUITests` rewritten for the new drill (household person → fire drill with no "no one" note;
  blank home → note → add a person → note gone); new `FireDrillUITests` (Home → Run a fire drill → House selected, dock
  on Fire, ignite controls, room list opens); stale drill steps in `S44ScreenshotUITests` (skipped by default) now go
  through Home's card.
- **Docs:** root `CLAUDE.md`, `escape_plan/CLAUDE.md`, `.claude/rules/paths/editorcore.md` (no SemanticMatcher),
  `docs/demo/feature-inventory.md`, script beat 6 and its truth row ("timed" removed), storyboard b-roll line, the
  playbook README (S11.10, S11.35, S11.36 lose their DrillScreen parts), four `decisions.md` rows, BLOCKERS.

**Evidence (2026-10-03).**
- `swift test --package-path tools/editorcore`: **642 tests, 0 failures**. Count: 662 (trim 1) − 10 DrillNotice − 10
  SemanticMatcher − 11 WallGrouping + 11 EvacuationJourney = 642.
- `bash scripts/typecheck-ios.sh`: all four targets ok.
- Targeted iOS run before the review fixes: `xcresulttool` 69 / 69 passed (`.build-trim2/targeted.xcresult`; includes
  `FireDrillUITests` and both `ProfilesEntryUITests`).
- **Full suite on the final code: `xcresulttool` 1005 total / 994 passed / 0 failed / 11 skipped
  (`.build-trim2/full.xcresult`)**, first run, no re-runs needed. Count: 1064 (trim 1) − 73 deleted (DrillModeTests 9,
  DrillPracticeTests 33, DrillNoticeTests 10, SemanticMatcherTests 8, SemanticMatcherRotTests 2, WallGroupingTests 11)
  + 14 new (EvacuationJourneyTests 11, AppRouterTests 1, TaskDestinationTests 1, FireDrillUITests 1) = 1005.
  `ProfilesEntryUITests` stays at 2 (both rewritten); the 11 skips are the same opt-in tests as before.
- Backend `pytest -m "not live"`: 1003 passed, 1 skipped; `corpus/validate.py`: valid. Untouched by this branch.
- Simulator walk (iPhone 17 Pro, Ranch House from `demo-homes/`, live Render server): Home's card → House opened on
  "Fire simulation" → Choose a room → fire in Primary Bedroom → playback ran → speed menu listed 0.25×…2× → "Who does
  what" showed Sam (overtaken, warm border and warning), Leo, Grandpa Joe and Biscuit with real rooms and exits.

**Review (swift-scenekit-reviewer): 0 Must fix, 4 Should fix, plus stale-file Shoulds and nits.** Taken: (1) a `room`
step is matched by the engine's area-weighted centroid, so an L-shaped room's centroid in a neighbour no longer names the
neighbour (known-answer test with a concave room); (2) people with no way out (no track, a `no_viable_route` finding)
are listed first in "Who does what"; (3) "Simulation check" moved above the person cards; (4) the drill task's tick says
"We practiced it for real", with a hint that watching does not count; leftover reminders removed at launch;
`docs/tools-used.md` UserNotifications row; stale comments (BackendFailure, ProfilesScreen, AuthGateView, HomeScreen,
Haptics, two UI tests, `verify-all` skill); "same fact as" wording; neutral start icon; the Home card subtitle is no
longer clipped at accessibility sizes. **Not taken:** the `CameraGestureDriver.swift` comment (renderer, no edits this
trim; in BLOCKERS); moving `rateLabel` out of `Models/` (it sits beside the existing `timeLabel`, which has the same
shape, and `Models/` is symlinked so it stays tested); sharing `buildBlankHome` between two UI test files (test-only
duplication of 15 lines); stair and back-into-start test cases (no behaviour depends on them beyond the tested fold).

## New user-facing words (for Anish to review)

Every new or changed on-screen string, verbatim:

- Home, drill card subtitle (was "Never practised"): **"See everyone's way out of a fire"**
- House, fire dock, home with no people: **"No one is added to this home yet, so the simulation puts one person in each
  room. Add your household from the Home tab."**
- House, fire dock, section header: **"Who does what"**
- Per-person card lines (examples from the Ranch House run):
  - **"Starts in Primary Bedroom"** (pattern: "Starts in {room}")
  - **"Goes through Hallway and Entry"** (pattern: "Goes through {A}", "{A} and {B}", "{A}, {B} and {C}"); when no other
    room is crossed: **"Goes straight to the way out"**
  - **"Leaves through the door in the Entry"** / for a window: **"Climbs out through the window in the {room}"**; if the
    model has no such opening: "Leaves through an outside door" / "Climbs out through a window"
  - **"Outside at 0:13"** (pattern: "Outside at m:ss", seconds after the fire starts)
  - Warning (only when the engine flags it): **"The modeled fire reaches a room on their way out before they clear it."**
- VoiceOver for one card (one swipe): "Sam. Starts in Primary Bedroom. Goes through Hallway and Entry. Leaves through the
  door in the Entry. Outside after 13 seconds. Warning. The modeled fire reaches a room on their way out before they
  clear it."
- Speed menu entries: **"0.25×", "0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"**; VoiceOver: "Quarter speed", "Half speed",
  "Three quarter speed", "Normal speed", "1.25 times speed", "1.5 times speed", "Double speed".
- Drill task sheet, second button: **"We practiced it for real"** (VoiceOver hint: "Ticks this task. Watching the
  simulation does not count as practice.") / once ticked: **"Mark as not done"**.
- "Who does what", someone with no way out: heading **"No way out found"**, then the engine's own sentence, e.g. "Bo,
  starting in 'Bathroom', has no escape route that avoids the rooms this fire reaches first." 
- Offline note, "Works without a connection": **"the 3D editor, your saved homes, and the printable escape plan"**;
  "Needs the server" now says **"the fire drill simulation"** where it said "the fire simulation".
- Not on screen, but pitch words: demo script beat 6 now reads "And a fire drill you can watch with your kids: a fire
  starts, and you see who goes where, so you find the problems now."

Screenshots (Ranch House, iPhone 17 Pro simulator, live server): `img/trim-2/01-home-fire-drill-card.png`,
`02-house-opens-on-fire.png`, `03-fire-playing.png`, `04-speed-menu.png`, `05-who-does-what.png`. They were taken before
the review fixes: since then "Simulation check" sits above the cards and the start icon is a standing figure, not a bed.

## Questions for teammates

- @Anish: are the words above right? The two to look at: the card subtitle, and "Outside at 0:13" (it is the modeled
  time after the fire starts, not a stopwatch).

## Next steps

- Owner: review the words above and the screenshots.
- S11.10 (device pass): walk the fire drill with VoiceOver on a phone; the AR Drill checks are gone.
