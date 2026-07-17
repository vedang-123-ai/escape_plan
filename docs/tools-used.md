# Tools used

Every library, framework, API, and tool used in this project — required for Congressional App Challenge originality documentation. Includes our AI-assisted development process (Claude Code is used as a pair programmer; all output is reviewed, tested, and understood by the team).

| Tool | Version | What it's used for | License |
|------|---------|--------------------|---------|
| Xcode / Swift / SwiftUI | Xcode 16+ (S1.3 built on 26.6; iOS deployment target 26.5) | iOS app | Apple SDK |
| SceneKit | iOS SDK (built-in) | 3D dollhouse renderer (`escape_plan/Renderer/`, S1.3): extruded room slabs (`SCNShape`), semi-transparent walls, parametric opening markers, stair proxies, orbit/pan/zoom camera (`SCNView.allowsCameraControl`). Playbook default; RealityKit not used | Apple SDK |
| UIKit | iOS SDK (built-in) | Renderer support only — `UIColor`/`UIFont` for the palette and room labels, `UIBezierPath` to feed `SCNShape`. App UI is SwiftUI; SceneKit is bridged via `UIViewRepresentable` | Apple SDK |
| XCTest | iOS SDK (built-in) | iOS test suite (`escape_planTests/`) — renderer geometry, fixture decoding, bundled-fixture drift check | Apple SDK |
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
| Foundation (FileManager / JSONEncoder / UserDefaults) | iOS 17+ SDK | S2.4 local persistence: home documents on disk, JSON coding, anonymous device id. No third-party persistence library — the store is ~350 lines of Apple SDK | Apple SDK |
| XCTest | Xcode 26 | Swift test suite (`escape_planTests/`) | Apple SDK |
| Swift Package Manager | bundled | Dev/test only: `scripts/verify_export_validates.sh` builds the Persistence module as a throwaway macOS package so tests run without an iOS simulator runtime. Not a shipping dependency | Apache-2.0 |

## Content sources (grounding corpus, not code dependencies)

Full index with URLs and retrieval dates: `backend/corpus/sources.json`. Orgs: NFPA (escape planning, smoke-alarm fire statistics, disability evacuation guide), USFA/FEMA (smoke alarms, escape plans, disability fire safety), American Red Cross (escape plan steps, two-minute campaign, planning fact sheet), ICC (2021 IRC §R310/§R311 egress requirements). All corpus content is paraphrased with per-claim citations.
