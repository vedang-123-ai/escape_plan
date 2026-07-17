# Tools used

Every library, framework, API, and tool used in this project — required for Congressional App Challenge originality documentation. Includes our AI-assisted development process (Claude Code is used as a pair programmer; all output is reviewed, tested, and understood by the team).

| Tool | Version | What it's used for | License |
|------|---------|--------------------|---------|
| Xcode / Swift / SwiftUI | Xcode 16+ | iOS app | Apple SDK |
| Claude Code | — | AI pair-programming assistant (P3 lane + support); all code reviewed and understood by the team | Anthropic ToS |
| git / GitHub | — | Version control, private repo `vedang-123-ai/escape_plan` | — |
| Python 3 | 3.11+ | Backend: models, validation, routing engine | PSF |
| pydantic | ≥2.7 | HomeModel domain models + structural invariant validation (`backend/app/models.py`) | MIT |
| jsonschema | ≥4.21 | Validating documents against `schema/homemodel.schema.json` (draft 2020-12) | MIT |
| pytest | ≥8.0 | Backend test suite (`backend/tests/`) | MIT |
| matplotlib | ≥3.8 | Dev/debug only (`requirements-dev.txt`): fixture navigation-graph renderings in `docs/graphs/` (S1.1 handoff) | PSF-based |
| FastAPI | ≥0.115 | HTTP service wrapping the routing engine + AI layer (`backend/app/main.py`) | MIT |
| uvicorn | ≥0.30 | ASGI server running the FastAPI app (local + Render) | BSD-3 |
| httpx | ≥0.27 | FastAPI TestClient transport; HTTP client inside the anthropic SDK | BSD-3 |
| anthropic (Python SDK) | ≥0.60 | Grounded explanation layer (S3.1+): Claude API calls with prompt caching + tool-use structured output | MIT |
| Render.com | free tier | Backend hosting (blueprint `render.yaml`; deploy pending human account creation) | Render ToS |
| SceneKit | Apple SDK (iOS 17+) | 3D dollhouse renderer + the editor's gesture/hit-test surface (`escape_plan/Editor/SceneKit/`) | Apple SDK |
| XCTest | Apple SDK | Swift unit tests (`escape_planTests/EditorCore/`) — run by both `xcodebuild test` and SwiftPM | Apple SDK |
| Swift Package Manager | Swift 6.3 toolchain | **Test harness only, never shipped** (`tools/editorcore/`): runs the pure editor-core tests on macOS because no iOS simulator runtime is installed on the dev machine. Symlinks the app's own sources — no vendored copies, no third-party dependencies | Apache-2.0 (toolchain) |

## Content sources (grounding corpus, not code dependencies)

Full index with URLs and retrieval dates: `backend/corpus/sources.json`. Orgs: NFPA (escape planning, smoke-alarm fire statistics, disability evacuation guide), USFA/FEMA (smoke alarms, escape plans, disability fire safety), American Red Cross (escape plan steps, two-minute campaign, planning fact sheet), ICC (2021 IRC §R310/§R311 egress requirements). All corpus content is paraphrased with per-claim citations.
