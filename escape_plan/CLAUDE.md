# escape_plan/ — iOS app (SwiftUI)

The iOS half of the project. Read the root `CLAUDE.md` first; Swift conventions are in
`.claude/rules/languages/swift.md`.

The project stays at the repo root (not the playbook's `ios/` layout) — see `docs/decisions.md`;
revisit only if the team wants the monorepo layout. The Xcode project uses a
`PBXFileSystemSynchronizedRootGroup`, so any `.swift` file added under `escape_plan/` (or
`escape_planTests/`) is compiled automatically — no project.pbxproj edit, but also no stray
scratch files.

## Structure (current)

- `Models/` — Codable schema mirror, field-for-field exact vs `schema/homemodel.schema.json` and
  `backend/app/models.py`. **Pure mirror** — round-trip test in `escape_planTests/`. Non-schema
  conveniences live in `Editor/Core/ModelSupport.swift` / `Renderer/HomeModel+Renderer.swift`,
  never as new fields here (that would be a schema change).
- `Persistence/` — local JSON documents via FileManager, one file per home
  (`<Documents>/Homes/<home_id>.homeplan.json`), schema-versioned, atomic writes. Plus
  `ConversationStore` (chat thread) and `ChecklistStateStore` (score checklist, UserDefaults).
- `Editor/Core/` — `HomeModelStore` reducer (the ONLY path that mutates a `HomeModel`),
  `EditAction`, `UndoStack`, validation, hit-testing, snapping. Pure Foundation — also compiled &
  tested as the `tools/editorcore` SwiftPM package.
- `Editor/SceneKit/` — `EditorSceneView` (unified free-camera editor surface, hosts
  `UnifiedSceneController` + `OrbitCameraRig`) and `SceneKitEditorBridge` (gesture →
  `EditAction`, with `GestureArbiter` deciding edit-drag vs orbit).
- `Renderer/` — SceneKit dollhouse (`DollhouseScene*`) + `RouteOverlay`/`RouteGeometry` (animated
  escape routes drawn from a `/routes` RoutePlan — never computed client-side).
- `Capture/` — RoomPlan LiDAR capture + raw JSON/USDZ exporter matching the converter contract.
- `Networking/` — `APIClient` (base URL + bearer token, `/health`) plus sibling extensions:
  `APIClient+Routes`, `+Chat`, `+Score`. Keep new endpoints as new extension files.
- `Auth/` — S8.3 accounts: `AuthClient` (`/auth/register` `/auth/login` `/auth/me`),
  `AuthSession` (the state machine — restore, sign in, register, refresh, sign out),
  `KeychainTokenStore`, `AuthFailure`, `AuthValidation`, `FormURLEncoding`. **Pure Foundation,
  no SwiftUI or UIKit** — the directory is symlinked into `tools/editorcore` as
  `Sources/EditorCore/Auth`, so `swift test` covers it on a machine with no simulator. Adding a
  SwiftUI import here silently removes that coverage. Screens live in `Screens/Auth/`.
- `Sync/` — S8.4 cloud sync: `CloudHomesClient` (`GET`/`POST /homes`), `SyncReconciler` (the
  pure function deciding each home's direction), `SyncManager` (the observable run + status),
  `HomeFingerprint`, `SyncState` (the sidecar), `SyncFailure`. **Pure Foundation, no SwiftUI or
  UIKit** — symlinked into `tools/editorcore` as `Sources/EditorCore/Sync`, exactly like
  `Auth/`, so `swift test` covers it with no simulator. Two rules that are easy to break:
  the per-user JWT goes on `/homes` and nowhere else (the deterministic endpoints are on the
  shared-bearer axis), and the dirty check fingerprints the **decoded model**, never bytes — a
  server round trip differs by bytes but not by value. App-side adapter is
  `Persistence/HomeDocumentSyncRepository.swift`; the badge is `Screens/SyncStatusBadge.swift`.
- `Screens/` — the tab shell + per-home sub-screens.

## Screen → session ownership (non-obvious after the five-lane merge)

| Screen | Session | Notes |
|---|---|---|
| `HomeScreen` | S0.3/S2.4 | home library; swipe/menu → Score & Profiles |
| `HouseScreen` | revamp A3 | THE unified screen: free-orbit translucent dollhouse that is editor (rooms, openings, stairs, undo/redo) AND route viewer (overlay, tour, profile picker) at once — replaced EditorScreen + PlanScreen |
| `AssistantScreen` | S3.3 | grounded chat; graceful error when the key is unset |
| `ScoreScreen` | S3.5 | preparedness score; backend does all the math |
| `ProfilesScreen` / `ProfileEditorView` | S3.4 | per-home family profiles CRUD |
| `SettingsScreen` | S0.3 | app-global config |
| `SyncStatusBadge` | S8.4 | the cloud glyph in the Home tab's toolbar. Tapping syncs and shows the detail popover. Sync is never a wall — it is a badge and a sentence, never a modal |
| `AuthGateView` / `LoginView` / `SignupView` | S8.3 | accounts. The gate is SOFT — "Continue without an account" is a real button, and the app is fully usable without one. `RootView` chooses gate vs `ContentView`; `AuthSheetView` is the same flow from Settings |

## Hard rules (from rules/languages/swift.md — don't relearn them the hard way)

- Mutate the model only through `HomeModelStore` + an `EditAction`. Never from a view.
- Openings are parametric (`wall_segment` = `edge_index` + `t0/t1`) — never absolute coordinates.
- Routes always come from a real `/routes` response — the app never computes or approximates one.
- No API keys / tokens in source; they come from configuration.
