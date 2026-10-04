# Tools used

Every library, framework, API, and tool used in this project — required for Congressional App Challenge originality documentation. Includes our AI-assisted development process (Claude Code is used as a pair programmer; all output is reviewed, tested, and understood by the team).

| Tool | Version | What it's used for | License |
|------|---------|--------------------|---------|
| Xcode / Swift / SwiftUI | Xcode 26.6 (Swift 5, iOS 17+ target, tested against iOS 26.5 SDK) | iOS app: S0.3 model layer (`Models/`), tab shell (`Screens/`), `Networking/APIClient.swift`, renderer/editor/capture/persistence modules | Apple SDK |
| SceneKit | iOS SDK (built-in) | 3D dollhouse renderer (`escape_plan/Renderer/`, S1.3): extruded room slabs (`SCNShape`), semi-transparent walls, parametric opening markers, stair proxies, orbit/pan/zoom camera. Also the editor's gesture/hit-test surface (`escape_plan/Editor/SceneKit/`). Playbook default; RealityKit not used | Apple SDK |
| UIKit | iOS SDK (built-in) | Renderer support only — `UIColor`/`UIFont` for the palette and room labels, `UIBezierPath` to feed `SCNShape`. App UI is SwiftUI; SceneKit is bridged via `UIViewRepresentable` | Apple SDK |
| Observation (Apple framework) | iOS 17+ / macOS 14+ | `@Observable` on the editor core's `HomeModelStore`/`UndoStack` (Lane A, 2026-07-23): SwiftUI re-renders directly off model/selection/undo state, replacing manual revision counters. Foundation-family, so `tools/editorcore` (the macOS SwiftPM test harness) compiles it too | Apple SDK |
| RoomPlan (Apple framework) | iOS 17+ | LiDAR room capture: `RoomCaptureView`/`RoomCaptureSession` scanning, `RoomBuilder` per-room processing, `StructureBuilder` multi-room merge into `CapturedStructure`, parametric USDZ export (`escape_plan/Capture/`, S1.4) | Apple SDK |
| ARKit (via RoomPlan) | iOS 17+ | World tracking underneath RoomPlan; kept alive across rooms (`stop(pauseARSession: false)`) so multi-room scans share one world origin (S1.4) | Apple SDK |
| simd (Apple) | — | `simd_float4x4` surface transforms, flattened column-major for the scan export contract (S1.4) | Apple SDK |
| Observation (Apple) | iOS 17+ | `@Observable` state: APIClient (S0.3) and the scan state machine (`RoomCaptureController`, S1.4) | Apple SDK |
| Security / Keychain Services (Apple framework) | iOS SDK (built-in) | Storing the per-user access token (`escape_plan/Auth/KeychainTokenStore.swift`, S8.3): `kSecClassGenericPassword`, `AfterFirstUnlock`, non-synchronizable. The first Keychain use in the project — the shared backend bearer token stays in UserDefaults, which is appropriate for a value that ships in the build but not for a credential that authenticates one person's account. No third-party keychain wrapper was added | Apple SDK |
| Claude Code | — | AI pair-programming assistant; all code reviewed and understood by the team | Anthropic ToS |
| git / GitHub | — | Version control, private repo `vedang-123-ai/escape_plan` | — |
| Python 3 | 3.11+ | Backend: models, validation, routing engine | PSF |
| pydantic | ≥2.7 | HomeModel domain models + structural invariant validation (`backend/app/models.py`) | MIT |
| jsonschema | ≥4.21 | Validating documents against `schema/homemodel.schema.json` (draft 2020-12) | MIT |
| pytest | ≥8.0 | Backend test suite (`backend/tests/`) | MIT |
| matplotlib | ≥3.8 | Dev/debug only (`requirements-dev.txt`): fixture navigation-graph renderings in `docs/graphs/` (S1.1 handoff) | PSF-based |
| FastAPI | ≥0.115 | HTTP service wrapping the routing engine + AI layer (`backend/app/main.py`) | MIT |
| uvicorn | ≥0.30 | ASGI server running the FastAPI app (local + Render) | BSD-3 |
| httpx | ≥0.27 | FastAPI TestClient transport; HTTP client inside the anthropic SDK | BSD-3 |
| pymongo (async API) | ≥4.13,<5.0 (4.18.1 installed) | S8.1 cloud sync: MongoDB connection lifecycle (`backend/app/database.py`) via `pymongo.AsyncMongoClient`, owned by the FastAPI `lifespan` handler. **Deliberately not Motor**, which reached end-of-life 2026-05-14 — PyMongo's native async API is MongoDB's stated replacement (GA in 4.13) | Apache-2.0 |
| argon2-cffi | ≥23.1.0 (25.1.0 installed) | S8.2 password hashing (`backend/app/auth/passwords.py`). Argon2id — OWASP's first choice; defaults m=64MiB/t=3/p=4 exceed every OWASP minimum. **Deliberately not passlib** (no release since 2020, hard-fails against bcrypt 5.x) and not bare bcrypt (72-byte limit, now filed under legacy) | MIT |
| PyJWT | ≥2.13.0,<3.0 (2.14.0 installed) | S8.2 access tokens (`backend/app/auth/tokens.py`), HS256. 2.13.0 is a **security floor**: CVE-2026-48522..48526 (algorithm allow-list bypass, public JWK accepted as an HMAC secret, JWKS SSRF) are fixed there. Not python-jose — patched, but 3.7 years between releases and dropped from FastAPI's docs | MIT |
| python-multipart | ≥0.0.20 | Form parsing for `OAuth2PasswordRequestForm` on `/auth/login` (S8.2) | Apache-2.0 |
| anthropic (Python SDK) | ≥0.60 | Grounded explanation layer (S3.1+): Claude API calls with prompt caching + tool-use structured output | MIT |
| Render.com | free tier | Backend hosting (blueprint `render.yaml`); **live** at `https://escape-plan-backend.onrender.com` since 2026-07-16 | Render ToS |
| GitHub Actions | hosted runners (`ubuntu-latest`, `macos-26`); actions `checkout@v4`, `setup-python@v5`, `upload-artifact@v4` | CI gate `.github/workflows/gate.yml` (added 2026-09-25): corpus validator + backend pytest on every push, iOS type-check + EditorCore `swift test` on macOS, and a manual full simulator run. No secrets | GitHub ToS; actions MIT |
| pip (`pip freeze`) | pip 26.2.1 on CPython 3.12 | Generates `backend/requirements.lock`, the exact-pinned deploy manifest Render installs (added 2026-09-25). No pip-tools; the header of the lock says how to regenerate it | MIT |
| MongoDB Atlas | M0 free tier | S8 cloud sync datastore (cluster `escape-plan`, database `escape_plan`), provisioned 2026-09-15. Holds accounts (`users`) and synced home models (`homes`). The connection string is an environment variable in Render and in a gitignored local `.env` — never in git. A managed cluster rather than a self-hosted `mongod` because the deployed backend and a developer laptop need the same reachable instance | MongoDB Atlas ToS (SSPL server) |
| Foundation (FileManager / JSONEncoder / UserDefaults) | iOS 17+ SDK | S2.4 local persistence: home documents on disk, JSON coding, anonymous device id. No third-party persistence library — the store is ~350 lines of Apple SDK | Apple SDK |
| XCTest | Xcode 26 | Swift test suites (`escape_planTests/`, incl. `EditorCore/`) — run by both `xcodebuild test` and SwiftPM | Apple SDK |
| Swift Package Manager | Swift 6.3 toolchain | **Dev/test harnesses only, never shipped**: `tools/editorcore/` (editor-core tests) and `scripts/verify_export_validates.sh` (S2.4 persistence tests + export validation) give a ~5s macOS feedback loop instead of a simulator boot. Symlinked app sources — no vendored copies, no third-party dependencies. As of S2.2 (2026-07-22) an iOS 26.5 simulator runtime IS installed on the dev machine (iPhone 17/17 Pro/17 Pro Max/17e/Air) — earlier sessions' "no simulator" blockers are stale; `xcodebuild test`/`xcodebuild build` now run for real, see decisions.md | Apache-2.0 (toolchain) |
| PDFKit + PhotosUI (Apple SDK) | iOS 17+ SDK | Revamp C2 plan-import: PhotosPicker for floor-plan photos; PDFKit rasterizes page 1 of a PDF plan to PNG client-side so the backend never needs a PDF dependency | Apple SDK |
| UserNotifications (Apple framework) | iOS 17+ | Was drill-practice reminders (`PracticeReminderScheduler`, 2026-08-05), deleted in demo trim 2 (2026-10-03). Now used only once at launch (`RootView`) to remove reminders an earlier build scheduled; it never asks for permission | Apple SDK |
| UIGraphicsPDFRenderer + Core Graphics (Apple SDK) | iOS 17+ | The printable escape plan (`escape_plan/Export/`, 2026-08-05): one page per floor drawn top-down from the schema polygons. `CGContext` stroke/fill/`setLineDash`/`addArc` carry the whole greyscale encoding (solid vs dashed routes, door arc vs window double-line, shaped waypoint markers). PDFKit deliberately **not** used for generation — `UIGraphicsPDFRenderer` covers it, so PDFKit would add a framework for nothing | Apple SDK |
| CGPDFDocument / CGDataProvider + `CGColorSpaceCreateDeviceGray` | iOS 17+ | **Tests only** — reopen the produced PDF, count pages, and rasterise into a device-grey bitmap. That colour space *is* the desaturation step, which is how greyscale legibility is measured rather than asserted | Apple SDK |
| UIActivityViewController (UIKit) | iOS 17+ | Share sheet for the printable plan: Print, Save to Files, AirDrop, Mail. Popover anchored for iPad | Apple SDK |
| idb (Facebook iOS Development Bridge) | idb-companion 1.1.8 (brew) + fb-idb 1.1.7 (pip) | **Dev/test only, never shipped**: sends real HID taps/swipes/text to the iOS simulator for the 2026-07-22 device-acceptance pass (no XCUITest edits needed). Installed on the dev machine, not in the repo | MIT |

### White Model dollhouse overhaul (2026-08-05)

No new dependencies. The overhaul is materials, lighting, camera and geometry built on APIs the
project already used — recorded here explicitly because "did you add a library for that?" is a
fair originality question and the answer is no.

| Capability | Where it comes from | Note |
|---|---|---|
| Screen-space ambient occlusion | `SCNCamera.screenSpaceAmbientOcclusion*` (Apple SDK) | The single biggest contributor to the white model reading as solid. Replaces the three.js prototype's baked-gradient AO hack — no post-processing library, no `SCNTechnique`. |
| Orthographic projection | `SCNCamera.usesOrthographicProjection` (Apple SDK) | Scale is driven from the rig's distance so ortho and perspective frame identically. |
| Soft shadows | `SCNLight` deferred shadow mode, 2048 map (Apple SDK) | Shadow *strength* is dialled by splitting the key between a casting light and a shadowless twin — SceneKit exposes no shadow-opacity property. |
| Route occlusion ghosting | Two draw passes ordered via `renderingOrder` + `readsFromDepthBuffer` (Apple SDK) | Deliberately avoids `SCNTechnique`; `SCNMaterial` has no depth-comparison function to set. |
| White furniture, exit markers, slab outlines | `SCNBox` / `SCNShape` / `SCNGeometry` primitives, built parametrically | No modeled assets, no `.usdz` files — everything is generated from the HomeModel schema at build time. |

Design source: Claude Design project `344e3e53-37d2-4471-831c-aa50067e9d55` — brief
`DOLLHOUSE-REDESIGN-SPEC.md`, three.js prototype `Dollhouse Prototype.dc.html` +
`dollhouse-three.js`, locked values `swift-implementation-notes.md`. The prototype is our own work
product, used as a visual spec; none of its code ships in the app.

### Fire-origin simulation + accessibility pass (2026-08-05)

**No new dependencies, in either half.** Recorded explicitly because the headline feature is the
one a judge is most likely to assume was bought in or handed to a model.

| Capability | Where it comes from | Note |
|---|---|---|
| Hazard spread over the home | `backend/app/routing/hazard.py` — pure Python over the existing S1.1 `NavGraph` | Breadth-first earliest-arrival traversal of the graph `/routes` already builds. No simulation library, no fire-modelling package, no AI call. Reusing the one graph is why blocked openings and egress thresholds are automatically true of the simulation too |
| Route re-solve around the hazard | Dijkstra, same `engine._edge_cost` as `/routes` | A fixpoint loop bans rooms the hazard reaches first and re-runs. S3.4 profile constraints apply unchanged, so a wheelchair user's simulated route obeys the same hard constraints as their planned one |
| Dashed route geometry | `RouteGeometry.dashes` — arc-length splitting in metres | Replaced a fragment-shader stipple. No shader, so the PDF lane consumes the same mark list |
| WCAG contrast maths | `Theme.swift` (`WCAG.contrastRatio`, `SRGB`) and `UIColor.relativeLuminance` in `DollhousePalette.swift` | Relative-luminance and contrast-ratio formulas implemented from the W3C definition, ~40 lines. No colour library. Both halves are unit-tested against real palette pairs rather than eyeballed |
| Greyscale legibility proof | `CGColorSpaceCreateDeviceGray` bitmap raster of the production stroke code | Measurement, not assertion: primary column-coverage 1.0 vs backup ≈0.58 |

## Content sources (grounding corpus, not code dependencies)

Full index with URLs and retrieval dates: `backend/corpus/sources.json` (**36 sources** as of 2026-09-21). Orgs: NFPA (escape planning, smoke-alarm and heating/cooking fire statistics, disability evacuation guide, electrical safety), USFA/FEMA (smoke alarms, escape plans, disability fire safety, clothes-dryer fires, **fire extinguishers**, **lithium-ion battery safety**), American Red Cross (escape plan steps, two-minute campaign, planning fact sheet, tornado safety), ICC (2021 IRC §R310/§R311 egress requirements), USGS (earthquake preparedness, plus the **"Triangle of Life"** and **"what NOT to do"** FAQs), **Earthquake Country Alliance / Great ShakeOut** (Seven Steps to Earthquake Safety, steps 1, 5 and 6), NOAA/NWS (tornado safety, watch-vs-warning, severe-weather shelter guidance, **NOAA Weather Radio accessibility for the deaf and hard of hearing**), **FEMA Building Science** (Safe Rooms; Tornado Recovery Advisory RA2), and the **California Legislature** (Health & Safety Code §19211, water-heater strapping). All corpus content is paraphrased with per-claim citations.

Added S11.1 (2026-09-21): Earthquake Country Alliance, FEMA Building Science and the California Legislature are new **source organisations**; the USGS, NOAA/NWS and USFA entries gained new documents. Every source added or touched that session was fetched and content-checked before its `retrieved` date was stamped — see `backend/corpus/check_urls.py`.

| Tool | Version | What it's used for | License |
|------|---------|--------------------|---------|
| `backend/corpus/check_urls.py` | in-repo, stdlib + `curl` | S11.1 source verification: re-fetches every URL in `sources.json`, confirms 200, and greps per-source `verify_keywords` so a page that stops saying what we cite it for is detectable. Network-dependent and **opt-in — deliberately not part of `validate.py` or the gate** | own work |

### The AI layer's eval set (2026-09-23, S11.4)

**No new dependencies.** Recorded because "we evaluated the model" is a claim a judge may
reasonably assume means a framework, a judge model, or a paid harness. It is none of those.

| Capability | Where it comes from | Note |
|---|---|---|
| The 14 eval cases | `backend/tests/evals/cases.py` — plain dataclasses | Each case carries a question, the behaviours required and forbidden, and a pass/fail probe pair. No dataset was downloaded or generated |
| Grading | `backend/tests/evals/graders.py` — `re` from the stdlib | Deterministic. **No LLM judge**: it would need credits and would make the suite non-deterministic, and every behaviour here is checkable against the corpus, the RoutePlan and a regex |
| Running without a key | a ~20-line stub replaying scripted text through the real `chat()` | Not a mocking framework and not a recording of real output — a stand-in for one SDK call, so citation validation and the retry loop run exactly as in production |
| Measurements in the cases | read from `app.routing` at import | Never typed by hand; S11.4's own correction row in `decisions.md` says why |
| The model | `claude-sonnet-5` via the official `anthropic` SDK (already listed) | Live scoring is `pytest -m live` and needs a funded key; nothing is cached or faked to stand in for it |

### Object-hazard detection (2026-09-22, S11.3 — arc shipped S7)

**No new dependencies.** Recorded explicitly because "detects hazards in your home" is the
single claim in this project most likely to be read as a bought-in model, and it is not one.
The reasoning behind that is `docs/decisions-object-detection-future.md`.

| Capability | Where it comes from | Note |
|---|---|---|
| Object recognition | **Apple RoomPlan**, on device, shipped with iOS | ~16 furniture/appliance classes with 3D oriented bounding boxes. Apple's model, not ours, not trained by us, and mapped to the schema by a table in the spec (§7) |
| The facts no sensor can see | The hazard hunt — a guided editor flow, zero network calls | `secured` is the field that gates R1 and R5, and a strap behind a wardrobe is occluded by the wardrobe. It is a question, not a detection |
| Every finding | `backend/app/routing/object_hazards.py` — pure Python, `math` from the stdlib | Oriented-bounding-box distance, ray-cast point-in-polygon and segment geometry, ~400 lines, no geometry library (no Shapely, no numpy, no scipy). Pure and deterministic, so the agent's `check_object_hazards` tool and the score read the identical implementation |
| The thresholds | `backend/corpus/object_hazard_thresholds.json` | Cited values carry a `source_doc_id` resolving in `sources.json`; our own geometric judgment calls are segregated under `engineering_constants` with a written `basis` and are never shown to the user as a safety standard |
| Vision photo-assist | **cut** | The S7.9 feasibility spike returned NO-GO (1 of 5 target classes usable, 2026-09-10). Listed here because a cancelled dependency is still part of the originality story |

### iOS cloud sync (2026-09-16, S8.4)

**No new dependencies.** Recorded explicitly because "syncs across devices" is the kind of
feature a judge would reasonably assume was bought in — a sync SDK, a CRDT library, a
backend-as-a-service.

| Capability | Where it comes from | Note |
|---|---|---|
| `GET`/`POST /homes` client | `escape_plan/Sync/CloudHomesClient.swift` — `URLSession` | Same injected-session shape as `AuthClient`, which is what makes the wire contract testable with no simulator |
| Conflict resolution | `escape_plan/Sync/SyncReconciler.swift` — a pure function, ~90 lines | Server-owned `revision` decides who is ahead; `meta.modified` breaks a genuine two-sided conflict, tie to the server. No CRDT, no operational transform, no sync framework |
| Change detection | `escape_plan/Sync/HomeFingerprint.swift` — FNV-1a over a canonical re-encoding | ~15 lines. Non-cryptographic on purpose (a change detector, not a security primitive), which also keeps the directory free of a CryptoKit import so it still compiles as a Foundation-only package |
| Sync-state persistence | `escape_plan/Sync/SyncState.swift` — `Codable` + `FileManager`, atomic writes | A versioned sidecar file. No database on the client |
| The fake `/homes` backend the tests run against | `escape_planTests/EditorCore/SyncTestSupport.swift` — `URLProtocol` | Our own ~150-line stand-in implementing the two routes as `api_auth.py` defines them, so the real client is exercised rather than a protocol double. No HTTP-mocking library |
