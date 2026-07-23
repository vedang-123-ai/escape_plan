# S4.1 — Golden path: onboarding flow backbone (device-independent half)

- **Who:** P3 (Claude Code)
- **Date(s):** 2026-07-22
- **Status when I stopped:** flow backbone CODE DONE against the twostory fixture; the two
  acceptance boxes (real home, live failure injection) are device-only and stay unchecked.

## What happened

Built the onboarding loop that stitches the existing modules together, entirely against the
bundled twostory fixture (real scans wait on S1.4/S1.5 — deliberately not blocked on them):

- **`Onboarding/`** (new): `OnboardingFlowView` (welcome → review → plan → done, shown as a
  full-screen cover on first launch from `ContentView`), `OnboardingState` (@Observable; every
  backend call is a `LoadState` = idle/loading/loaded/failed/offline — no implicit dead ends),
  `FixtureSeeder` (seeds twostory as a demo home with 3 items re-marked `source: scan`,
  `confidence: 0.4` so "N items need review" exercises the real review path; pure function,
  fixture file untouched, N computed with the editor's own `HitTesting.needsReview`).
- **Review step** lists the flagged items, "Review in Editor" pushes the existing
  `EditorScreen(homeID:)`, "Confirm & Continue" lands on the plan step.
- **Plan step** embeds the real `PlanScreen` (which auto-fetches /routes) and kicks off
  `/analyze` + `/score` in background tasks with an explicit status panel: spinner → findings
  list / score chip → failure state with Retry → distinct offline state.
- **`Networking/APIClient+Analyze.swift`** (new): POST /analyze following the established
  extension pattern; `Models/AnalyzeModels.swift` mirrors `backend/app/ai/agent.py`'s
  AnalysisResult/Finding (lenient decode; trace not decoded — the app doesn't render it).
- **`Networking/APIClient+Cache.swift`** (new): `RoutePlanCache` — last-good RoutePlan per
  home at `<Documents>/RouteCache/<home_id>.routeplan.json`, atomic writes, corrupt/missing
  reads as nil. `fetchRoutesCached` is the choke point: success updates the cache;
  connection-class failures (URLError offline/timeout/DNS) fall back to it; server answers
  (401/422/500) never do — they'd mask a config problem with a stale plan.
- **`PlanScreen`** (minimal touch, pre-agreed): fetch goes through `fetchRoutesCached`; a
  cached fallback shows "Offline — showing the last saved plan from <date>" with Retry.

## Decisions / surprises

- **Latent persistence bug found and fixed** (`Persistence/HomeDocument.swift`, outside my
  declared surface — flagged here deliberately): `init(model:)`/`decode(as:)` used plain
  JSONEncoder/JSONDecoder (dates as Doubles) while `touched()` stamps `meta.modified` as an
  ISO-8601 string. Net effect: **any real HomeModel saved via `save(model:)` (EditorScreen
  autosave, ProfilesScreen) could never be loaded back** — DecodingError on `meta.modified`.
  The S2.4 test suite missed it because its stub model has no Date fields; my seeding test hit
  it immediately. Fix: both coders now use `.iso8601`, matching the schema and every fixture.
  @P2 note: documents autosaved before this fix carry a Double `meta.created` and still fail
  to load (they also failed before the fix). If any exist on your device, delete and rebuild —
  or we add a SchemaMigrator normalization if it matters.
- Seeded review items are the twostory copy's top-floor first room + first two openings at
  confidence 0.4 (< the 0.5 threshold) — matches what the converter emits for uncertain
  surfaces; fixture files and drift-guard untouched.
- `AnalyzeModels.swift` lives in `Models/` next to RoutePlan/ScoreModels (wire mirrors, not
  schema mirrors — same precedent).
- Onboarding shows once (`@AppStorage "onboarding.completed"`); "Skip" also completes it.

## Late findings while producing the recording

- **Second latent dead end found and fixed:** `PlanScreen` never called `reload()` when its
  `HomeLibrary` was already populated at init — `.onChange(of: library.homes)` never fires
  for the initial value, so with a saved home present the screen sat on an infinite
  "Loading…" spinner forever. One-line fix in `.task`. This predates S4.1 (S2.3's device
  eyes-on pass hadn't run yet, which is why nobody hit it).
- **Handoff artifact:** `docs/demo/broll/s41-golden-path-simulator.mp4` (~57 s, iPhone 17 Pro
  simulator, local backend on :8001 without an Anthropic key — so the /analyze panel
  deliberately shows the graceful "AI inspection unavailable" state, which is itself an S4.1
  acceptance behavior). Driven unattended by `escape_planUITests/GoldenPathRecordingUITests`
  (skips unless `TEST_RUNNER_GOLDEN_PATH=1`, so the normal suite stays hermetic); re-record
  any time with a keyed backend for the findings-populated version.

## Failure-state inventory (what kills each dead end)

| Call | loading | failure | offline | empty |
|---|---|---|---|---|
| seed (local) | n/a (sync) | inline error label | works offline | n/a |
| review | n/a | n/a | works offline | "Everything looks good" + Continue |
| /routes | PlanScreen banner | banner + Retry | cached last-good plan + dated banner; plain error if no cache | "No home to show" |
| /analyze | spinner panel | message + Retry (401 gets its own text) | distinct offline text + Retry | "no issues found" |
| /score | spinner | message + Retry | distinct offline text + Retry | n/a |

## Questions for teammates

- @P2: the HomeDocument date-strategy fix above touches your persistence layer — review it.
- @P1: /analyze returns 502 when ANTHROPIC_API_KEY is unset; onboarding shows the graceful
  "AI inspection unavailable — routes still work" state, so the key session is not a blocker
  for the golden-path recording, just for the findings actually appearing.

## Next steps

- Device half of S4.1: real-home scan loop + live failure injection on device (needs
  S1.4/S1.5) — the two acceptance boxes stay unchecked until then.
- Simulator screen-recording of the full loop (handoff artifact).
- Optional follow-up: a Settings "replay walkthrough" affordance (deliberately not added —
  SettingsScreen is outside this session's surface).
