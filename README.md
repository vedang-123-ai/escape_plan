# Escape Plan

An iOS home-safety **readiness and prevention** app. A family scans its home with Apple RoomPlan LiDAR
(or builds it in a full 3D editor), and a deterministic Python engine computes escape routes, shelter
choices, hazard findings, a readiness score and a checklist for **fire, earthquake and severe weather
(tornado)**. Routes are drawn as animated paths on a SceneKit dollhouse. A server-side Claude layer
explains and chats, grounded in a curated, cited FEMA / NFPA / Red Cross / USFA corpus.

**The AI never computes a route and never invents safety guidance.** The engine is deterministic and
testable; the AI explains and chats. Neither does the other's job.

Congressional App Challenge 2026. Submit by Oct 24, 2026.

## Layout

| Path | What |
|---|---|
| `schema/` | `homemodel.schema.json`, the contract every other part agrees on, plus fixtures |
| `backend/` | Python 3.11+ / FastAPI: routing, scoring, corpus, AI layer, optional accounts and sync |
| `escape_plan/` | The iOS app (SwiftUI + SceneKit), at the repo root rather than under `ios/` |
| `tools/editorcore/` | SwiftPM harness that tests the pure Foundation logic on macOS, fast |
| `docs/` | Product spec and playbook, tracker, decisions log, demo materials |

## Running it

**Backend**

```
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
export BACKEND_BEARER_TOKEN=dev-local-token     # the service fails closed without this
export ANTHROPIC_API_KEY=sk-ant-...             # only needed for /explain, /analyze, /chat, /build
.venv/bin/uvicorn app.main:app --reload --port 8000
```

Without `ANTHROPIC_API_KEY` the AI endpoints return a clean 502; the deterministic endpoints
(`/routes`, `/score`, `/convert`, `/evacuate`) still work. A deployed instance runs on Render.

**iOS.** Open `escape_plan.xcodeproj` and run (iOS 17+). Set the backend URL and token in Settings, or
create the gitignored `escape_plan/BackendConfig.local.json`. LiDAR scanning needs a real iPhone Pro;
everything else works on the simulator.

## Verifying

Run `/verify` for the whole gate, or individually:

```
python3 backend/corpus/validate.py
backend/.venv/bin/python -m pytest backend/tests/ -m "not live"
swift test --package-path tools/editorcore
bash scripts/typecheck-ios.sh                      # fast iOS type-check, no simulator needed
xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Exact test counts change often; the current ones live in `docs/tracker/BLOCKERS.md`. SourceKit and VS Code
cannot index this project and show errors that are not real: trust `xcodebuild`.

## Where the truth lives

- **`docs/tracker/BLOCKERS.md`**: everything blocking or unverified, ranked. Start here.
- `docs/tracker/TODO.md`: the long-tail backlog. `docs/tracker/notes/`: one note per session.
- `docs/playbook/README.md`: the S11 session plan (13 sessions, three lanes, branch protocol).
- `docs/playbook/01-product-spec.md`: the product spec and scope lock. `docs/decisions.md`: every deviation, with reasons.

## How we work

Three people work in parallel, each session on its own branch (`s11-N-slug`), merging to `main` only after the
session's gate is green. See `docs/playbook/README.md` for lanes, branch protocol and conflict rules, and
`CLAUDE.md` for how Claude Code behaves in this repo. Run `/verify-docs` to catch documentation drift.

## Scope

Fire, earthquake and severe weather (tornado); iOS only; LiDAR scan plus editor as the primary capture, with a
draft-only text/photo builder as an accessibility fallback; accounts and cloud sync optional and soft-gated;
no custom or trained ML. The scope has moved deliberately, each time with a dated entry in
[`docs/decisions.md`](docs/decisions.md). The current lock is in
[`docs/playbook/01-product-spec.md`](docs/playbook/01-product-spec.md) §4.
