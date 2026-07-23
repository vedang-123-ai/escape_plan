# Board — where we are right now

_Last updated: 2026-07-22 (by P3/Claude — device-acceptance pass cleared S2.2/S2.3/S3.4/S3.5 on-screen boxes). Update this whenever a session flips status._

## 🆕 2026-07-22 (latest) — simulator device-acceptance pass: S2.2 / S2.3 / S3.4 / S3.5 (P3)

Drove the app click-by-click on a **dedicated** iPhone 17 Pro simulator (`p3-acceptance`) with
`idb` HID taps/swipes, against a **local** backend (`localhost:8000`, dev bearer token — the
Render token wasn't available; /routes and /score are deterministic, no Anthropic key needed).
Evidence (screenshots + recordings = S5.1 b-roll) in **`artifacts/acceptance-2026-07-22/`**.

- **S2.3 fully observed**: pulse primary + blue secondary from Kids' Bedroom, exploded view,
  camera tour recorded, apartment shows red no-second-way-out badges + findings list (twostory
  kids' room correctly shows none). Only the real-device 60fps box remains.
- **S3.4 money shot recorded**: Everyone→Maya (route + camera to Kids' Bedroom) →Grandpa
  (Master Bedroom + red "No viable escape route" flag). Profile CRUD (Grandpa, Maya) exercised
  on Apartment 4B. Explanation-text box stays key-blocked.
- **S3.5 DONE**: breakdown legible (expanded rationale w/ citation), toggle → POST /score →
  75→77 on screen (matches backend cross-check).
- **S2.2 mostly observed**: opening drag + stairs sheet + ~15-op mixed undo/redo unwind all
  watched happen. Two UI bugs found for P2 (see decisions.md): tap-selection doesn't re-render
  the toolbar (Add Stairs stays disabled until a revision-bumping action), and a redo tap
  immediately after undo was dropped once. Real-scan door-fix box still awaits S1.4/S1.5.
- **Ops note**: sharing the default 'iPhone 17 Pro' simulator + `.build-merge` derived-data
  with a concurrently running session causes device shutdowns and build swaps mid-pass — use a
  dedicated device + private derived-data path (this pass used `.build-p3`).

Details: `docs/tracker/notes/2026-07-22-device-acceptance-pass.md`.

## 🆕 2026-07-22 (latest) — S4.1 golden-path backbone CODE DONE, device half remains (P3)

The onboarding loop now stitches everything together on the twostory fixture: first launch →
seeded demo home with 3 flagged low-confidence items → "N items need review" (Review-in-Editor
or confirm) → Plan step with live routes + background /analyze findings + /score chip → done.
Every backend call has explicit loading/failed/offline states; /routes now falls back to a
last-good cached plan (`RouteCache/`, atomic JSON) when offline. New: `Onboarding/`,
`APIClient+Analyze`, `APIClient+Cache`, `Models/AnalyzeModels`; minimal pre-agreed touches to
`ContentView` + `PlanScreen`. **Also fixed two latent bugs:** homes saved via `save(model:)`
could never load back (date-strategy mismatch in `HomeDocument`), and `PlanScreen` spun on
"Loading…" forever when a home already existed at first appearance — @P2 please review both.
Suite: 238 iOS unit tests + UI tests green, EditorCore 128. The two S4.1 acceptance boxes
(real home, live failure injection) are **device-only and stay unchecked**; simulator
recording is the handoff. Details: `docs/tracker/notes/2026-07-22-s4-1-onboarding-flow.md`.

## 🆕 2026-07-22 — test-coverage lane: +42 unit tests for the merged code (P3)

Pure test-authoring pass over the five-lane merge, no source edits. First-ever coverage for
`ScoreModels` and `ChecklistStateStore`, RoutePlan decode-error paths, ConversationStore
corrupt-file/relaunch, `ChatError` messages, and the EditAction edges the lane suites missed
(13 of the 42 run in the fast `tools/editorcore` harness → now 128/128). Full gate green:
196 backend, corpus valid, 231 iOS tests on the simulator — excluding only a *concurrent*
S4.2 drill lane's in-flight `DrillSessionTests` (one WIP failure there, theirs to fix).
Details + coverage map: `docs/tracker/notes/2026-07-22-test-coverage-lane.md`.

## 🆕 2026-07-22 — five lanes integrated, whole suite green (P3)

S2.2 (editor openings/stairs/undo), S2.3 (route visualization), S3.3 (chat UI), S3.4 (profiles
CRUD) and S3.5 (score screen) were all built the same day and all landed in this one working
tree. Integration pass verified they coexist, closed S3.4's cross-lane `TODO(integration)`
(PlanScreen now has a live "Who" profile picker that re-fetches `/routes` with `profile_id`),
and fixed a fixture-path test that had been failing since 2026-07-16.

**Everything automated is green:** 115/115 EditorCore · full `escape_planTests` + UI tests on the
iPhone 17 Pro simulator with **zero failures** · 195 backend tests · corpus valid.

**What's left is eyes-on-a-screen, not code.** One simulator session clears S2.2's three
criteria, S2.3's recording, S3.4's Grandpa-vs-Maya switch, and S3.5's legibility box. Details and
the click-by-click list: `docs/tracker/notes/2026-07-22-five-lane-integration.md`.
Still key-blocked (not device-blocked): S3.3's live chat acceptance.

**Late-day backend pass (P3):** the S3.3 500-vs-502 finding is FIXED (`/chat` now 502s on a
missing key, regression-tested) and S3.2's missing `test_agent_live.py` is written (key-skipped
live acceptance suite). Backend now 197 green. P1's key session is now run-and-review only.

**Schedule check:** enormous day — S0.3 landed, the backend is deployed and code-complete
through Phase 3, and big chunks of Phase 1–2 iOS code merged. **We are far ahead of schedule.**
What's left is mostly device/human verification, not code. Immovable milestone: end-to-end
demo path working by **Oct 5**; submit by **Oct 24**.

## 🆕 2026-07-22 — Home/Editor/Plan tabs now wired to real code (P3)

The S1.3/S2.1/S2.4 modules were fully coded and tested but never actually read by the tab
screens — `EditorScreen`/`PlanScreen` were still S0.3 placeholders, `HomeScreen` only showed a
bundled fixture. That's why the app looked "broken" when run: 3 of 5 tabs genuinely did nothing.
Fixed by wiring existing, already-tested code into the screens — no new backend/schema work.
Full details: `docs/tracker/notes/2026-07-22-home-editor-plan-integration.md`.
**Needs an Xcode build+run to confirm** (VSCode's SourceKit can't index this project at all —
even old files show phantom "cannot find type" errors — so this has not been compiler-verified
yet). See the message accompanying this session for the click-by-click test steps.

## 📱 P2 — READ THIS FIRST

**S0.3 (iOS scaffold) landed on `main` 2026-07-16** — stock Core Data template is gone,
replaced with the real `Models/`/`Screens/`/`Networking/` layer. Your one human step:

1. `git pull`, open `escape_plan.xcodeproj`, build+run on your real iPhone (click-by-click
   steps in `docs/tracker/notes/2026-07-16-s0-3-ios-scaffold.md`).
2. Confirm the **Home** tab shows "Two-Story House" with rooms per floor, then flip S0.3 to
   DONE here + check the device box in `checklist.md`.
3. Note: S1.3 renderer / S2.1 editor / S1.4 capture / S2.4 persistence code ALSO merged today
   (see below) — after the device run, the next P2 jobs are the device acceptance checks in
   the table below, not building those modules from scratch.
4. ⚠️ Model-layer unification is in progress on the merge terminal: the S2.1 lane's stub
   `Models/Generated/HomeModel.swift` is being retired in favor of S0.3's `Models/` — read
   the decisions.md 2026-07-16 rows before renaming any model fields.

## ✅ DONE

| Session | What landed |
|---|---|
| S0.1 | Repo, CLAUDE.md, playbook, .claude/ control center |
| S0.4 | Grounding corpus + sources.json + egress_thresholds.json + validate.py ⚠️ P1 review still advised |
| S0.2 | HomeModel schema v1 + pydantic mirror + 3 fixtures + invalid/ fixtures + validate CLI |
| S1.1 | Navigation graph builder + egress checker (docs/graphs/*.png) |
| S1.2 | Routing engine: primary/secondary/bottlenecks/constraints (docs/route-samples/) |
| S1.6 | **DEPLOYED** — live at `https://escape-plan-backend.onrender.com`; `/health` + `/routes` verified 200 OK ~0.3–0.4s. Cellular timing check deferred by team decision (see decisions.md). `ANTHROPIC_API_KEY` not yet set on Render (AI endpoints 502 until then). Bearer token: Render dashboard → Environment. |

## 🟡 CODE DONE — human/device/key steps remain (all lanes audited 2026-07-16)

| Session | What landed | Remaining step |
|---|---|---|
| S0.3 iOS scaffold | `Models/` Codable mirror + round-trip test PASSED (simulator on teammate's machine), tab shell, APIClient | **P2: build+run on real iPhone (box above)** |
| S3.1 grounded explanations | `/explain`, citation validation w/ reject-retry, golden + red-team live tests | **P1: live `-m live` run with key, review `tests/golden/`** |
| S3.2 agentic analysis | `/analyze` 6-tool loop, 22 scripted-client tests, trace example; **`tests/test_agent_live.py` written 2026-07-22** (key-skipped acceptance suite w/ golden snapshots) | **Key + live run/review (suite exists, just run it)** |
| S3.3 chat backend (prep) + iOS UI (2026-07-22) | `/chat` stateless multi-turn on the S3.1 grounding layer; **iOS chat screen built** (`AssistantScreen` + `APIClient+Chat` + `ConversationStore`) — verbatim `[cite:]` rendering, graceful 5xx "AI unavailable" state, thread persists across background/force-quit; 4 new unit tests green on simulator (a runtime is installed on this machine now). ~~Missing key → `/chat` 500s~~ **fixed 2026-07-22: now a deliberate 502** (regression-tested, see decisions.md) | **Key session: live smoke tests + in-app acceptance (cited answer, deferral) + 5 screenshot Q&As** |
| S1.3 renderer | SceneKit dollhouse (`Renderer/`), 3 fixtures decode+build, 18 tests compiled (no simulator runtime to run them) | **Simulator/device: run `scripts/s13-acceptance.sh`, 60fps check, 3 recordings (b-roll)** |
| S1.4 RoomPlan capture | `Capture/` + raw JSON/USDZ exporter matching converter contract; synthetic round-trip PASSES | **LiDAR device: real 2–3 room scan, commit device-{clean,messy} fixtures (gates S1.5 calibration), verify UIFileSharingEnabled on device** |
| S2.1 editor core | `HomeModelStore` reducer + validation-on-mutation, drag/snap/hit-test; 89 tests RUN green (SwiftPM) | **On-device bungalow hand-build <5 min + recording; wire `EditorSceneAdapter` seam to the renderer** |
| S2.4 persistence | Document store + migration stub; 17 tests run green; export schema-validated. ⚠️ landed directly on main | **On-device kill/relaunch check** |
| S3.4 profiles (backend half + iOS CRUD 2026-07-22) | Tag→constraint mappings (docs/profile-constraint-mappings.md), `/routes profile_id`, Grandpa-vs-Maya proven on twostory; **iOS CRUD UI built** (`ProfilesScreen`/`ProfileEditorView` from Homes list, new `EditAction` profile cases, autosave via S2.4 store; 11 new store tests green via SwiftPM) | **Live 3D re-fetch on profile switch (S2.3 overlay now exists — wire the TODO(integration) in ProfilesScreen); device eyes-on pass** |
| S2.3 route viz (2026-07-22) | **Full overlay code built**: `/routes` fetch (`APIClient+Routes`, `Models/RoutePlan.swift`), animated primary pulse tube + dashed secondary (`RouteGeometry`/`RouteOverlay`, per-floor containers so explode/hide just work), stair-crossing stubs, exit glow, engine-findings warning badges, camera tour, room picker + cold-start/error banners in PlanScreen; 14 new tests + full suite green on simulator | **Device eyes-on: pulse/tour smoothness + the acceptance recording (twostory bedroom both routes; apartment badges) — the 📦 handoff** |
| S3.5 score | `/score` + pure engine, weights doc hand-reproducible, 34 tests; **iOS score screen built 2026-07-22** (`ScoreScreen` under Home, live re-POST per toggle, count-up animation; math cross-checked 75→80→100 / 75→77) | **Simulator/device eyes-on pass (legibility + toggles end-to-end); optional live golden for AI recommendations** |
| S4.2 drill mode — walkthrough half (2026-07-22) | **Guided walkthrough built** in new `escape_plan/DrillMode/`: profile picker → waypoint-by-waypoint camera steps reusing `RouteOverlay.startTour` on two-waypoint route slices → cited instruction cards (`[cite:]` ids test-resolved against sources.json) → meeting-place card → "mark plan as practiced" flips `practice.drill_recent` in `ChecklistStateStore` (score moves via ScoreScreen's next `/score` POST). 8 new tests; full gate green (the earlier "WIP DrillSessionTests failure" note below is this lane, fixed same day). Built ahead of S4.1 — no shared code (decisions.md). Writeup: `docs/tracker/notes/2026-07-22-s4-2-drill-walkthrough.md` | **Flow owner: wire the `TODO(integration)` entry point (HomeScreen menu → `DrillScreen(homeID:)`); then device: complete a drill for two profiles, score moves + persists** |
| S2.2 editor: openings/stairs/undo (2026-07-22) | **Opening drag** (`dragOpening(openingId:t:)`, parametric t0/t1, preserves width), **stairs authoring** (`addStairs`/`deleteStairs` + minimal toolbar sheet), **undo/redo** (`UndoStack.swift`, coalesces a whole drag gesture into one entry via explicit begin/endCoalescing, doesn't fight autosave). 20 new tests (115/115 total) run green on **a real simulator** — see below. Full writeup: `docs/tracker/notes/2026-07-22-s2-2-editor-openings-stairs-undo.md` | **On-screen: drag a door, place stairs on a 2-story, 20 mixed undo/redo ops — no simulator-automation tool available this session, needs a human tap-through** |

## ▶️ CAN START NOW

| Who | Session | Notes |
|---|---|---|
| **P2** | Device acceptance sweep | One device session clears S0.3 + S1.3 + S2.1 + S2.4 + S2.2 checks — **a real iOS 26.5 simulator is now installed on the dev machine** (iPhone 17/17 Pro/17 Pro Max/17e/Air), so "no simulator runtime" is no longer a reason to defer these; see decisions.md 2026-07-22. |
| **P1** | Key session | Set `ANTHROPIC_API_KEY` on Render + locally, run all `-m live` suites → clears S3.1/S3.2/S3.3. |
| **P1** | Review pass | backend/app/ grew a lot today; CAC requires the team to understand every line. |

## ⏸ BLOCKED

- S2.3 route viz CODE DONE 2026-07-22 (device recording ← S1.3-style device pass) · S1.5 calibration ← S1.4 device fixtures
- S4.1 golden path **flow backbone CODE DONE 2026-07-22** (fixture-driven; the real-home + live failure-injection half still ← S1.5 + S3.1 device/key steps) · S4.2's walkthrough half CODE DONE 2026-07-22 ahead of S4.1 (independent — see table above); rest of S4.x after S4.1 · S5.1 **v1 DELIVERED 2026-07-22** (script-v1 + storyboard-v1 w/ b-roll path contract in docs/demo/) — remaining: team table-read + P1 accuracy pass; re-read once S4.1 runs

## 🔑 Critical path to the Oct 5 demo milestone

P2's device sessions (S0.3 run → S1.3/S2.1 acceptance → S2.3) are the longest pole.
Backend is deployed and code-complete; one API-key session closes the whole AI column.

Cut order if we slip (never cut scan → editor → 3D routes → profile switch):
1. S4.2 drill · 2. S3.3 chat · 3. S3.5 score · 4. camera tour · 5. simplified agent
