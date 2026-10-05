# Tools used

Every library, framework, service and AI tool used to build Escape Plan, with version, purpose and licence. The
2026 Congressional App Challenge rules ask for this twice: "While participants may use open-source libraries,
frameworks, and external tools, they must clearly document any such usage", and "all AI usage is fully disclosed in
the submission materials" (2026 CAC Rules, §3 App Parameters).

**Completed 2026-10-05 (S11.51) against `origin/main` `988fe94`.** Where a version comes from, it says so:

- Python packages: exact pins in `backend/requirements.lock` (what Render installs). Licences read from each package's
  own metadata after installing that lock file into a scratch venv on 2026-10-05.
- Dev-only Python packages: floors in `backend/requirements-dev.txt`. They are not pinned; the "resolves to" version is
  what `pip` installed on 2026-10-05.
- Apple frameworks: the iOS SDK that ships with Xcode. No version of their own; the deployment target is iOS 17.0
  (`escape_plan.xcodeproj`, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`).
- Xcode and Swift: `xcodebuild -version` and `swift --version` on Anish's Mac, 2026-10-05.
- GitHub Actions: `.github/workflows/gate.yml`.

**The iOS app has no third-party code.** The Xcode project has no Swift Package dependencies (zero
`XCRemoteSwiftPackageReference` entries), no CocoaPods and no Carthage. Everything the app imports is an Apple
framework. All third-party code is in the Python backend and is listed below.

## Languages and build tools

| Tool | Version | What it's used for | Licence |
|---|---|---|---|
| Swift | Swift 5 language mode (`SWIFT_VERSION = 5.0`); compiled by the Swift 6.3.3 toolchain | The iOS app (`escape_plan/`) and its tests | Apache-2.0 (Swift project) |
| Xcode | 26.6 (build 17F113); CI selects the newest Xcode 26 on the runner | Building, running and testing the iOS app | Apple Xcode and SDK licence |
| Swift Package Manager | Swift 6.3.3 toolchain, `swift-tools-version: 6.0` | **Test harness only, never shipped.** `tools/editorcore/` runs the app's pure-Foundation editor, model and readiness code as a macOS package so tests run in seconds without a simulator. Its sources are symlinks to the app's own files; it has no dependencies | Apache-2.0 |
| Python | 3.12.6 on Render (`render.yaml` `PYTHON_VERSION`); 3.12 in CI; 3.13.5 on Anish's Mac | Backend: schema models, the routing and scoring engine, the HTTP service, the AI layer | PSF-2.0 |
| pip (`pip freeze`) | pip bundled with CPython 3.12 (version not recorded) | Produces `backend/requirements.lock`, the exact-pinned list Render installs | MIT |
| JSON Schema | draft 2020-12 | `schema/homemodel.schema.json`, the contract the app and backend share (schema version 2.1) | Open specification |
| git / GitHub | GitHub, private repo `vedang-123-ai/escape_plan` | Version control | GitHub Terms of Service |

## iOS app: Apple frameworks (all ship with the iOS SDK)

| Framework | What it's used for | Licence |
|---|---|---|
| SwiftUI | Every screen of the app | Apple SDK |
| SceneKit | The 3D "dollhouse" of the home and the editor surface: extruded room slabs, walls, openings, stairs, animated routes, camera rig, ambient occlusion, soft shadows. Everything is generated from the home model; there are no 3D asset files. RealityKit is not used | Apple SDK |
| UIKit | Bridging SceneKit into SwiftUI, colours and fonts in the renderer, the share sheet (`UIActivityViewController`), and `UIGraphicsPDFRenderer` for the printable plan | Apple SDK |
| RoomPlan | LiDAR room scanning: `RoomCaptureView`/`RoomCaptureSession`, multi-room merge into one `CapturedStructure`, export for conversion (`escape_plan/Capture/`). Apple's on-device model recognises furniture and appliances; we did not train it | Apple SDK |
| ARKit (through RoomPlan) | World tracking underneath RoomPlan, kept alive across rooms so a multi-room scan shares one origin. Not imported directly | Apple SDK |
| simd | Scan transforms (`simd_float4x4`) | Apple SDK |
| Foundation | JSON coding, `FileManager` local storage (one JSON file per home), `UserDefaults`, `URLSession` networking | Apple SDK |
| Observation | `@Observable` state: the editor's `HomeModelStore` and undo stack, the API client, the scan state machine | Apple SDK |
| Combine | Used in one file (`Persistence/HomeLibrary.swift`) | Apple SDK |
| Core Graphics | The printable plan's drawing (greyscale route encoding), and turning page 1 of a PDF floor plan into an image for the plan importer (`CGPDFDocument` in `Networking/ImagePreparation.swift`). PDFKit is **not** used | Apple SDK |
| ImageIO + UniformTypeIdentifiers | Re-encoding photos to JPEG and reading image types before upload (`Networking/ImagePreparation.swift`) | Apple SDK |
| PhotosUI | `PhotosPicker` for the plan importer | Apple SDK |
| os (`Logger`) | Diagnostic logging | Apple SDK |
| ObjectiveC runtime | One `import ObjectiveC.runtime` in `Renderer/Evacuation/UnifiedSceneController+Evacuation.swift` (associated objects) | Apple SDK |
| UserNotifications | Used once at launch to remove reminders an older build scheduled. It never asks for permission (the reminders feature was cut 2026-10-03) | Apple SDK |
| Security (Keychain Services) | `escape_plan/Auth/KeychainTokenStore.swift`. **Compiled but unreachable**: accounts and cloud sync were switched off on 2026-10-02 and no screen reaches `Auth/` or `Sync/` | Apple SDK |
| XCTest and Swift Testing | The app's unit and UI tests (`escape_planTests/`, `escape_planUITests/`, and the shared tests run by `tools/editorcore`) | Apple SDK |

Tests only: `CGPDFDocument` and a device-grey colour space reopen the generated PDF and measure how legible the routes
are in greyscale.

## Backend: Python packages (deployed)

Exact versions from `backend/requirements.lock`. The first column is what we chose (`requirements.txt`); the rest are
installed because those packages need them.

| Package | Version | What it's used for | Licence |
|---|---|---|---|
| fastapi | 0.142.2 | The HTTP service (`backend/app/main.py`): `/routes`, `/score`, `/evacuate`, `/convert`, `/chat`, `/build` and others. Endpoints are thin wrappers over pure functions | MIT |
| uvicorn | 0.54.0 | The server process FastAPI runs in (locally and on Render) | BSD-3-Clause |
| pydantic | 2.13.5 | The home model and every request and response, plus structural checks (polygons counter-clockwise and not self-intersecting, references resolve, ids unique, size limits) | MIT |
| anthropic | 1.11.0 | Calls to Claude for the assistant chat and the text/photo builder. Never used for routing or scoring | MIT |
| httpx | 0.28.1 | HTTP client inside the anthropic SDK; transport for FastAPI's test client | BSD-3-Clause |
| pymongo | 4.18.2 | Optional cloud sync database client. **Switched off in the app since 2026-10-02**; the backend runs without it when `MONGODB_URI` is unset | Apache-2.0 |
| argon2-cffi | 25.1.0 | Password hashing for the optional accounts. **Switched off in the app since 2026-10-02** | MIT |
| PyJWT | 2.15.1 | Access tokens for the optional accounts. **Switched off in the app since 2026-10-02** | MIT |
| python-multipart | 0.0.32 | Form parsing for the account login endpoint | Apache-2.0 |
| starlette | 1.7.0 | Required by fastapi | BSD-3-Clause |
| pydantic_core | 2.46.5 | Required by pydantic | MIT |
| annotated-types | 0.8.0 | Required by pydantic | MIT |
| typing-inspection | 0.4.4 | Required by pydantic | MIT |
| typing_extensions | 4.16.0 | Required by pydantic and others | PSF-2.0 |
| annotated-doc | 0.0.5 | Required by fastapi | MIT |
| anyio | 4.15.1 | Required by starlette and httpx | MIT |
| sniffio | 1.3.1 | Required by anyio | MIT OR Apache-2.0 |
| h11 | 0.16.0 | Required by uvicorn and httpcore | MIT |
| httpcore | 1.0.9 | Required by httpx | BSD-3-Clause |
| httpx2 | 2.13.1 | Required by the anthropic SDK | BSD-3-Clause |
| httpcore2 | 2.13.1 | Required by httpx2 | BSD-3-Clause |
| certifi | 2026.7.22 | Required by httpx (root certificates) | MPL-2.0 |
| idna | 3.20 | Required by httpx | BSD-3-Clause |
| truststore | 0.10.4 | Required by the anthropic SDK | MIT |
| jiter | 0.17.0 | Required by the anthropic SDK (JSON parsing) | MIT |
| docstring_parser | 0.18.0 | Required by the anthropic SDK | MIT |
| opentelemetry-api | 1.45.0 | Required by the anthropic SDK | Apache-2.0 |
| click | 8.5.0 | Required by uvicorn | BSD-3-Clause |
| dnspython | 2.8.0 | Required by pymongo | ISC |
| cffi | 2.1.1 | Required by argon2-cffi-bindings | MIT-0 |
| argon2-cffi-bindings | 26.1.0 | Required by argon2-cffi | MIT |
| pycparser | 3.0 | Required by cffi | BSD-3-Clause |

## Backend: dev and test only (not deployed)

| Package | Version | What it's used for | Licence |
|---|---|---|---|
| pytest | floor 8.0 (`requirements-dev.txt`); resolves to 9.1.1 | The backend test suite (`backend/tests/`) | MIT |
| jsonschema | floor 4.21; resolves to 4.26.0 | Checking fixtures and documents against `schema/homemodel.schema.json` | MIT |
| matplotlib | floor 3.8; resolves to 3.11.2 | Drawing the navigation-graph pictures in `docs/graphs/` | Matplotlib licence (PSF-based) |
| idb (Facebook iOS Development Bridge) | idb-companion 1.1.8 + fb-idb 1.1.7, as recorded 2026-07-22; installed on one dev Mac, not in the repo, not re-checked | Sending taps to the iOS simulator for a 2026-07-22 acceptance pass | MIT |

Our own stdlib-only scripts (no dependencies): `backend/corpus/validate.py` (checks every citation resolves),
`backend/corpus/check_urls.py` (re-fetches every source URL; opt-in), `scripts/demo-preflight.py`,
`scripts/check-tips-sync.py`, `scripts/smoke-deploy.sh`, `scripts/typecheck-ios.sh`, and
`scripts/make_app_icon.swift` (draws the app icon with Core Graphics; no image generator was used).

## Services

| Service | Plan / version | What it's used for | Terms |
|---|---|---|---|
| Render | Free web service (`render.yaml`, `plan: free`) | Hosts the backend at `https://escape-plan-backend.onrender.com`. Deploys only after the CI checks pass (`autoDeployTrigger: checksPass`; the dashboard setting is still to be confirmed by the owner, see BLOCKERS §1). Free-tier cold start was measured at about 42 to 51 seconds | Render Terms of Service |
| Anthropic API | Model `claude-sonnet-5` (`render.yaml` `ANTHROPIC_MODEL`, default in `backend/app/ai/model_support.py`) | The assistant chat and the text/photo builder. **The account is out of credits**, so these return 502 today; their behaviour is verified with a stub client in tests, not live | Anthropic Commercial Terms |
| GitHub Actions | `ubuntu-latest` and `macos-26` runners; `actions/checkout@v7`, `actions/setup-python@v7`, `actions/upload-artifact@v7` | The `gate` workflow: corpus check and backend tests on every push, iOS type-check and the EditorCore tests on macOS, and a nightly or manual full simulator run. No secrets | GitHub Terms of Service; the actions are MIT |
| MongoDB Atlas | M0 free tier, provisioned 2026-09-15 | Datastore for the optional accounts and cloud sync. **Not reachable from the app since 2026-10-02.** The connection string lives only in Render's environment and a gitignored `.env` | MongoDB Atlas Terms |

## AI tools used to build the app (disclosure)

The CAC rules allow AI tools if every use is disclosed and AI is not "the entirety of the technical development".
This is the complete list the team gave (owner answer recorded in `docs/decisions.md`, 2026-09-29), plus what the
repo itself shows about how they were used.

| Tool | Version | What it was used for | Terms |
|---|---|---|---|
| Claude Code (Anthropic) | Models named in commit trailers: Claude Opus 5, Opus 5.5, Fable 5, Sonnet 5, Sonnet 5.5, Opus 4.8, Haiku 4.5 | An AI coding agent in the terminal. Team members directed the product spec and the session plans (`docs/playbook/`), which were drafted with Claude Code (39 of the 44 commits to `01-product-spec.md` and the playbook `README.md` carry a Claude trailer; the team should confirm this wording), then ran sessions in which Claude Code wrote and edited code, tests and docs, ran the test gate, and reviewed work with project-specific checking agents (`.claude/agents/quality/`). **As of 2026-10-05, 513 of the 634 non-merge commits on `main` carry a `Co-Authored-By: Claude` trailer**, and 18 non-merge commits (22 including merges) are authored by "Claude" directly | Anthropic Consumer / Commercial Terms |
| Claude (claude.ai), including Claude Design | Not recorded | Planning and discussion. Claude Design was used twice: (1) the visual spec and a three.js prototype for the white-model dollhouse (project `344e3e53-37d2-4471-831c-aa50067e9d55`, `docs/decisions.md` 2026-08-05); none of the prototype's code ships in the app. (2) The owner designed the Home, Assistant, Settings, Onboarding, Score and House dock screens (project `66734cd4-4e07-4cf5-a116-5ded7e6dec0c`, exported to `docs/design/claude-design-export/`, `docs/decisions.md` 2026-09-07); the app restyled its screens to match | Anthropic Consumer Terms |
| Google Antigravity (Gemini models) | Not recorded | An AI coding agent used for some sessions; session notes name it for S6.8/S6.9 (2026-09-08), S7.3, S7.7 (2026-09-09, finished by Claude when Antigravity usage ran out), the S11.29 to S11.46 audit and S11.47 (2026-10-04, then reviewed and corrected with Claude) | Google Terms of Service |

`docs/ai-assistance/improved_prompt.md` is one of the prompts used to direct the agents, kept as disclosure.

What the AI tools did **not** do: no AI model computes a route, a score or a hazard finding in the app. Those come from
our deterministic Python engine. The app's safety guidance comes from the cited corpus, not from a model.

**Still for a person to write (BLOCKERS, S11.51):** a sentence in the team's own words on what each team member
personally designed, built, decided or checked. The rules expect "significant individual contributions and technical
understanding", and only the team can state that truthfully.

## No new dependencies: features a judge might assume were bought in

Each of these is our own code on top of the tools above. Recorded because "did you use a library for that?" is a fair
originality question.

| Capability | Where it comes from | Note |
|---|---|---|
| Escape routing | `backend/app/routing/` (graph build, Dijkstra) | Pure Python, deterministic. No routing or graph library |
| Fire-spread simulation | `backend/app/routing/hazard.py` | Earliest-arrival spread over the same navigation graph, then routes re-solved around it. No simulation library, no AI call |
| Earthquake cover and tornado shelter | `backend/app/routing/perils/` | Picks the nearest table to get under, and the lowest, most interior reachable room. Guidance-based, labelled "Guidance-based" in the app (`Readiness/ScoreBasisLabel.swift`) |
| Object-hazard findings | `backend/app/routing/object_hazards.py`, `math` from the stdlib | Oriented-box distance and point-in-polygon geometry, about 470 lines. No Shapely, numpy or scipy. Objects come from RoomPlan or are tagged by hand in the House object inspector |
| Thresholds | `backend/corpus/egress_thresholds.json`, `object_hazard_thresholds.json` | Each cited value carries a source id from `sources.json`; our own engineering constants are kept apart and never shown as a safety standard |
| Citation checking | `backend/app/ai/` | Every `[cite: id]` is checked against `sources.json` on the server; an uncited safety claim is retried once, then replaced by an honest deferral. Verified in stub tests |
| AI eval set | `backend/tests/evals/` | Plain dataclasses and regex graders. No eval framework and no LLM judge |
| 3D look (ambient occlusion, orthographic camera, soft shadows, route ghosting) | SceneKit properties | No post-processing library and no shaders bought in |
| Contrast checks | `Theme.swift`, `DollhousePalette.swift` | WCAG contrast formulas, about 40 lines, unit-tested |
| Cloud sync (switched off) | `escape_plan/Sync/` | Our own reconciler and change detector. No sync SDK. Not reachable in the app since 2026-10-02 |
| Photo recognition (Vision) | **Cut** | A 2026-09-10 spike found 1 of 5 target object classes usable, so it was dropped |

## Content sources (the grounding corpus, not code)

`backend/corpus/sources.json` lists **36 sources** (validated 2026-10-05: `python3 backend/corpus/validate.py` reports
36 sources, 13 corpus files, 44 prevention tips). Organisations: NFPA (8), USFA/FEMA (6), American Red Cross (4), USGS
(4), FEMA including FEMA Building Science (4), NOAA/NWS (4), Earthquake Country Alliance / Great ShakeOut (3), ICC
2021 IRC (2), and the California Legislature (1). The text is paraphrased in our own words, with a citation on each
claim and the URL and retrieval date for every source.
