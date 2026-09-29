# 01 · Architecture

Audit date: 2026-09-28. Branch audited: `drill-3d-fallback` at `3dc9c8e` (2 commits ahead of `origin/main`, 0 behind).
Conventions for every file in this directory are in [`00_EXECUTIVE_SUMMARY.md`](00_EXECUTIVE_SUMMARY.md).

## 1. What the system is

Escape Plan is a two-part system:

| Part | Tech | Where | Size |
|---|---|---|---|
| iOS app | SwiftUI + SceneKit + RoomPlan/ARKit, iOS 17.0 deployment target, Xcode 26 | `escape_plan/` (177 app files), `escape_planTests/` (86), `escape_planUITests/` (10) | ~36k lines Swift in the app |
| Backend | Python 3.12 (deploy) / FastAPI 0.141 / pydantic 2.13 / anthropic 1.8 / pymongo 4.18 async | `backend/app/` | ~12k lines Python |
| Contract | JSON Schema draft 2020-12, `schema_version` 2.1 | `schema/homemodel.schema.json`, `schema/fixtures/` | — |
| Corpus | 13 markdown docs, 36 sources, 2 threshold files, 44 prevention tips | `backend/corpus/` | — |
| Pure-Swift test harness | SwiftPM package that symlinks Foundation-only app folders | `tools/editorcore/` | 614 tests |
| Hosting | Render free web service (`render.yaml`), MongoDB Atlas (optional) | — | — |
| CI | GitHub Actions `gate.yml` (backend + iOS type-check on push; iOS simulator suite manual) | `.github/workflows/gate.yml` | — |

There is **no web frontend and no Vercel deployment**. "Frontend" in this audit means the iOS app.

## 2. Component map

```
iOS app (escape_plan/)
 ├─ escape_planApp.swift ── creates: APIClient, AuthSession(+Keychain), HomeDocumentStore.launchStore(),
 │                           FileSyncStateStore, HomeDocumentSyncRepository, SyncManager
 ├─ RootView ── soft auth gate (AuthGateView) OR ContentView
 ├─ ContentView ── TabView: Home | Tasks | House | Assistant | Settings
 │     owns HomeLibrary (ObservableObject), ReadinessStore (@Observable), AppRouter
 │
 ├─ Screens/HomeScreen ── home switcher, score card, next tasks, scan / build manually / import plan,
 │                        recheck-a-room (partial re-scan → /convert → /diff_obstructions → DiffReviewSheet)
 ├─ Screens/TasksScreen ── full checklist, ExportPlanSheet, ShareWithFireDepartmentCard
 ├─ Screens/HouseScreen (2,726 lines) ── the editor + route viewer + fire simulation (/routes, /evacuate)
 ├─ Screens/AssistantScreen ── /chat
 ├─ Screens/SettingsScreen ── server URL/token, account, "share with fire department", about
 ├─ DrillMode/DrillScreen ── practice drill (/routes per profile, /evacuate optional); AR opt-in (Drill/)
 ├─ Editor/Core (pure) ── HomeModelStore reducer, EditAction, UndoStack, EditorValidation
 ├─ Persistence ── HomeDocumentStore (Documents/Homes/<id>.homeplan.json), ChecklistStateStore (UserDefaults),
 │                 DrillLogStore, ConversationStore (single file), ScoreCache (Caches), SchemaMigrator
 ├─ Networking ── APIClient (+Routes/+Score/+Chat/+Build/+Convert/+Evacuate/+Analyze/+Cache), BackendFailure
 ├─ Auth, Sync (pure, symlinked into tools/editorcore) ── JWT session, SyncReconciler (pure), SyncManager (I/O)
 └─ Capture ── RoomPlan scan → Documents/Scans/<stamp>/raw.roomplan.json (+ apple-raw.json, scan.usdz)

Backend (backend/app/)
 ├─ main.py ── /health, /health/db (open); /routes /evacuate /convert /score /diff_obstructions (shared bearer);
 │             /explain /analyze /build (shared bearer + AI cost guard)
 ├─ api_chat.py ── /chat (shared bearer + AI cost guard)
 ├─ api_auth.py ── /auth/register, /auth/login (open); /auth/me GET/DELETE, /homes GET/POST, /homes/{id} DELETE (JWT)
 ├─ routing/ (pure) ── graph + nav_grid (0.1 m cells) + Dijkstra; perils/ (earthquake, tornado); hazard.py (/evacuate)
 ├─ scoring/ (pure except recommend.py) ── checklist.py (1,225 lines), score.py
 ├─ ai/ ── grounded.py (/explain), agent.py (/analyze), builder.py (/build), chat/ (/chat), model_support.py
 ├─ convert/ ── RoomPlan export → HomeModel
 ├─ rate_limit.py ── in-process token bucket per client IP + global semaphore (AI routes only)
 └─ database.py, cloud_repo.py, cloud_models.py, auth/ ── optional Mongo + Argon2id + HS256 JWT
```

## 3. Trust boundaries (as built)

| Boundary | Mechanism | Real strength | See |
|---|---|---|---|
| Anyone → deterministic + AI endpoints | One shared bearer token (`BACKEND_BEARER_TOKEN`) | The token ships **inside every app build** as a plaintext bundled JSON (`APIClient.swift:67-78`), so it is a build identifier, not a secret | AUD-003 |
| Anyone → `/auth/register`, `/auth/login` | none | Open, unthrottled, Argon2 on the event loop | AUD-005 |
| User → own cloud homes | Per-user HS256 JWT, ownership in every Mongo filter | Sound (ownership is in the query) | 06 §"What is solid" |
| Client geometry → routing engine | pydantic validation (topology, CCW, ids) | No size/extent/count bounds | AUD-004 |
| AI output → user | Citation-id validation; structured output for `/explain` | `/chat` accepts uncited text | AUD-030 |
| AI → routes | Architecture: AI never routes | Holds (agent/builder tools call the deterministic engines) | 13 |

## 4. Data ownership (who is the source of truth)

| Data | Source of truth | Synced? | Exported? |
|---|---|---|---|
| Home geometry, profiles, household, objects | `Documents/Homes/<home_id>.homeplan.json` (HomeModel JSON) | Yes (optional, `/homes`) | Yes (JSON via store, PDF) |
| Checklist done-state | `UserDefaults["checklistState.<home_id>"]` | **No** | **No** |
| Drill log | `Documents/DrillLog/…` (`DrillLogStore`) | No | No |
| Assistant conversation | `Documents/Assistant/conversation.json` — **one slot for all homes** | No | No |
| Score / checklist | Recomputed server-side on every `/score`; cached in Caches | n/a | PDF |
| Route plans | Server-computed; last-good cached per home in `Documents/RouteCache` | n/a | PDF |
| Sync bookkeeping | `Documents/sync-state.json` (`FileSyncStateStore`) | n/a | n/a |
| Raw scans | `Documents/Scans/<stamp>/` (never cleaned) | No | Visible in Files app |

Consequence: the "same" synced home can score differently on two devices (AUD-018), and several writers share one
home file with no coordination beyond an "open in editor" flag (AUD-013).

## 5. Architectural findings

The architectural core — deterministic engine, AI as explainer, one schema across three languages, pure logic tested
without a simulator — is sound and well defended by tests (backend 893 passed, EditorCore 614 passed). The problems are
at the seams:

1. **One home file, many writers, no single owner (root cause of AUD-013, AUD-017, AUD-015).** `HouseScreen`,
   `ProfilesScreen` (currently unreachable), `HomeScreen`'s re-scan diff, `OnboardingState`, `BuildFromPlanView`,
   `FixtureSeeder` and `HomeDocumentSyncRepository` all write `Documents/Homes/<id>.homeplan.json` directly. Only
   `HouseScreen` holds a long-lived in-memory copy, and it never reloads. The documented rule "mutate only through
   `HomeModelStore`" is honoured per screen but there is one `HomeModelStore` **per screen instance**, not per home.
   A fix needs a per-home owner (for example a library-level `HomeModelStore` cache that screens borrow) or a
   file-version check before autosave.

2. **The revamp removed the old navigation hub without re-homing its actions (root cause of AUD-020, AUD-021, AUD-023).**
   `BetaScreen.swift` (deleted in `87c0610`, 2026-09-25) was the only place that opened Profiles, deleted/duplicated a
   home, exported a home, and opened the editor after `/build`. None of those were moved to the new tabs.

3. **Shared-token model for a public app (root cause of AUD-003, AUD-004, AUD-006).** The deterministic and AI
   endpoints are guarded by a secret that is distributed with the client. Every "requires the bearer token" statement
   in the backend docs should be read as "requires a copy of the app".

4. **Two feature halves wired on one side only.** `/analyze` and `/explain` exist, are tested, and have iOS client
   code, but nothing in the UI calls them (AUD-022). `HomeDocumentStore.importDocument` exists with no UI (AUD-021).
   Checklist recurrence exists server-side but no production caller supplies the clock or the timestamp format it
   needs (AUD-026).

5. **Per-screen copies of cross-cutting state.** Several screens build their own `HomeDocumentStore()` (bypassing the
   launch-time temp-directory fallback — AUD-019), their own route cache reads, and their own failure mapping. The
   shared `BackendFailure` classifier (good) is still fed wrong operation labels in places (AUD-029).

## 6. What is solid (checked, not assumed)

- **Routing is deterministic and AI-free.** `app/routing/` has no I/O; the agent and builder only call engine functions.
- **Schema lockstep.** Bundled fixtures are byte-identical to `schema/fixtures/` (checked with `cmp` for all 7);
  Swift `SchemaMigrator.currentVersion`, pydantic `Literal["2.1"]` and the JSON Schema enum agree on 2.1.
- **Cloud ownership checks are in the query** (`cloud_repo.py:140-169`), 404 for unowned ids, the user is re-read on
  every request, the JWT decode pins the algorithm and requires `exp/iat/sub`.
- **The `/diff_obstructions` guard fix is deployed**: a POST with no token to the live service returned **401** on
  2026-09-28 (this clears an open BLOCKERS "not smoke-checked" line).
- **Secrets are not in git**: no `sk-ant-api…` pattern in any tracked file; `BackendConfig.local.json` and `.env` are
  not tracked.
