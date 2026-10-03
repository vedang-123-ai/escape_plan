# escape_plan/ — iOS app (SwiftUI)

The iOS half of the project. Read the root `CLAUDE.md` first; Swift conventions are in
`.claude/rules/languages/swift.md`. The Xcode project lives at the repo root (not `ios/`) and uses a
`PBXFileSystemSynchronizedRootGroup`: any `.swift` file added under `escape_plan/` or `escape_planTests/` is
compiled automatically (no `project.pbxproj` edit, and no stray scratch files). Deployment target is iOS 17.0.

## Structure

- `Models/` — Codable schema mirror, field-for-field exact vs `schema/homemodel.schema.json` and
  `backend/app/models.py`. **Pure mirror**; non-schema conveniences live in `Editor/Core/ModelSupport.swift` or
  `Renderer/HomeModel+Renderer.swift`, never as new fields here (that would be a schema change).
- `Persistence/` — local JSON documents via FileManager, one file per home, schema-versioned, atomic writes;
  `ConversationStore`, `ChecklistStateStore`, and `HomeDocumentSyncRepository` (adapter for `Sync/`).
- `Editor/Core/` — `HomeModelStore` reducer (the ONLY path that mutates a `HomeModel`), `EditAction`, `UndoStack`,
  validation, hit-testing, snapping, `CameraRigModel`, `EvacuationJourney` (a fire simulation's tracks in words). Pure
  Foundation, also tested as `tools/editorcore`.
- `Editor/SceneKit/` — `EditorSceneView` (+ `UnifiedSceneController`, `OrbitCameraRig`), `SceneKitEditorBridge`.
- `Renderer/` — SceneKit dollhouse plus `RouteOverlay`/`RouteGeometry`. Routes are drawn from a `/routes` plan,
  never computed client-side.
- `Capture/` — RoomPlan LiDAR capture and the raw JSON/USDZ exporter matching the converter contract.
- `Networking/` — `APIClient` (base URL + shared bearer token) plus `+Routes`, `+Chat`, `+Score` extensions.
- `Onboarding/` — first-run flow, household interview, `FixtureSeeder` (seeds the demo home only into an empty library).
- **No drill folder since trim 2 (2026-10-03).** "Run a fire drill" opens House on its fire simulation
  (`AppRouter.openFireDrill`); the old practice drill, practice log, reminders and the AR walk (`Drill/`, `DrillMode/`)
  were deleted. History: git before the trim-2 merge.
- `Export/` — plan PDF/JSON export, `MeetingPointStore`, and the Responder Snapshot (`ResponderSnapshot*`).
- `Auth/`, `Sync/` — accounts and cloud sync, **switched off since 2026-10-02** (no screen reaches them; `RootView`
  signs out any stored login once). `AccountPrivacy` copy and `HomeFingerprint` are still live. **Pure Foundation, no SwiftUI/UIKit**: both are symlinked into
  `tools/editorcore`; a SwiftUI import there silently removes test coverage.
  The per-user JWT goes on `/homes` only; the dirty check fingerprints the decoded model, never bytes.
- `Screens/` — the tab shell and sub-screens (table below).

## Screens

Tabs (`ContentView`): **Home, Tasks, House, Assistant, Settings** (the Linear dark-only revamp, 2026-09-25: the Beta tab
is gone, switching homes lives in Home's top bar, and the checklist has its own tab). `ReadinessStore` owns the active
home, its score and checklist; `AppRouter` owns the selected tab and cross-tab requests; `ContentView` creates both and
injects them with `.environment(...)`. `RootView` chooses the soft auth gate vs the app.

| Screen | What it is | Playbook owner |
|---|---|---|
| `HomeScreen` | overview of the active home: score card, next three tasks, fire-drill and 3D shortcuts (both open House), home switcher, add a home | S11.5 |
| `TasksScreen` | the full readiness checklist (Urgent / To do / Done), peril filter, family plan | revamp |
| `ReadinessStore`, `AppRouter` | shared state: active home + `/score` result + checklist; tab and cross-tab requests | revamp |
| `ScoreScreen`, `ProfilesScreen`, `ProfileEditorView` | score breakdown (reads `ReadinessStore`); per-home family profiles CRUD | S11.5 / stable |
| `HouseScreen` | THE unified 3D screen: editor (rooms, openings, stairs, undo/redo), route viewer and fire simulation (the drill) at once; `EvacuationPeoplePanel` is its "Who does what" | S11.9 (camera) |
| `AssistantScreen` | grounded chat against `/chat`; degrades gracefully with no key or bearer | stable |
| `SettingsScreen` | server URL/token, fire-department share, Privacy ("what leaves this iPhone") | S11.7 |
| `BuildFromPlanView` | text/photo `/build` intake, draft-only, mandatory editor review | stable |
| `ConsentSheet` (+ `Export/`) | "Share with your fire department" consent and snapshot | S11.6 |
| `AuthGateView`, `LoginView`, `SignupView`, `AuthSheetView`, `SyncStatusBadge` | **unreachable since 2026-10-02** (accounts cut, code kept); `AccountPrivacyDisclosure` is still used by Settings | — |
| `RouteFindingViews`, `HomeThumbnailView`, `BackendFailureBanner` | presentation only; the shared failure notice | stable |

## Hard rules

- Mutate the model only through `HomeModelStore` + an `EditAction`. Never from a view.
- Openings are parametric (`wall_segment` = `edge_index` + `t0/t1`), never absolute coordinates.
- Routes always come from a real `/routes` response. The app never computes or approximates one.
- No API keys or tokens in source; they come from configuration. Colours come only from `Screens/Theme.swift`, under the
  three guardrails in the root `CLAUDE.md` (safety colours distinct and colour-blind-safe, accessibility floors,
  `CameraRigModel` purity).
- Never re-enable `allowsCameraControl`. Keep `CameraRigModel` free of SceneKit/UIKit.
