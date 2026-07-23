# Escape Plan

_Last verified: 2026-07-22 @ 2fef343_

An iOS app that builds a structured 3D model of your home and computes personalized fire escape
routes on it.

You capture your home with an Apple RoomPlan LiDAR scan (or build it by hand in a full 3D
editor), and a deterministic Python routing engine computes a primary and a secondary escape
route from every room to an exterior exit. Routes are drawn as animated paths on a SceneKit
dollhouse. A server-side Claude layer explains those routes, answers questions about them, and
agentically audits the home for problems — always grounded in a curated FEMA / NFPA / Red Cross
corpus, never inventing safety advice, and **never computing routes**.

That last separation is the design, not a detail. The routing engine is deterministic and
testable; the AI explains, audits, and cites. Neither does the other's job.

Congressional App Challenge 2026.

## Layout

| Path | What |
|---|---|
| `schema/` | `homemodel.schema.json` — the contract every other part agrees on, plus test fixtures |
| `backend/` | Python 3.11+ / FastAPI: `/convert`, `/routes`, `/score`, `/explain`, `/analyze`, `/chat` |
| `escape_plan/` | The iOS app (SwiftUI + SceneKit). At the repo root, not `ios/` — see `docs/decisions.md` |
| `tools/editorcore/` | SwiftPM harness that tests the editor's pure logic on macOS, fast |
| `docs/` | Playbook, tracker, decisions log, demo materials |

## Running it

**Backend**

```
cd backend
pip install -r requirements.txt
export BACKEND_BEARER_TOKEN=dev-local-token     # the service fails closed without this
export ANTHROPIC_API_KEY=sk-ant-...             # only needed for /explain, /analyze, /chat
uvicorn app.main:app --reload --port 8000
```

Without `ANTHROPIC_API_KEY` the AI endpoints return a clean 502; everything else works. A
deployed instance runs at `https://escape-plan-backend.onrender.com` (the key is currently
unset there, so its AI endpoints 502 too).

**iOS**

Open `escape_plan.xcodeproj` and run. There is no prefilled backend URL or token — set both in
the app's Settings tab (it defaults to `http://localhost:8000`). LiDAR scanning needs a real
iPhone Pro; everything else works on the simulator.

## Verifying

Run `/verify` for the whole gate, or individually:

```
python3 -m pytest backend/tests/ -m "not live"          # 196 tests
swift test --package-path tools/editorcore              # 128 tests
python3 backend/corpus/validate.py                      # 11 sources, 6 corpus files
xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO   # 242 tests
```

SourceKit and VS Code cannot index this project — they show errors that aren't real. Trust
`xcodebuild`.

## Where the truth lives

- **`docs/tracker/TODO.md`** — everything still to do. Start here.
- `docs/tracker/notes/` — one note per work session; why things were done the way they were.
- `docs/tracker/activity-log.md` — machine-written record of what changed when.
- `docs/decisions.md` — every deviation from the plan, with the reasoning.
- `docs/tools-used.md` — every dependency and why (the Challenge requires this).
- `docs/playbook/` — the original execution plan, one file per session (`S0-1.md` … `S5-3.md`).
- `CLAUDE.md` — how Claude Code should work in this repo.

Run `/verify-docs` to check these still match the code. They drifted badly once; the auditor
exists so it gets caught early next time.

## How we work

1. Work is split into checkpointed sessions — `docs/playbook/`, one file per session with
   prerequisites and acceptance criteria.
2. Before starting: read `CLAUDE.md`, the session file, and `docs/decisions.md`. Never start a
   session whose prerequisites aren't done.
3. A session is done only when its acceptance criteria actually pass — verified, not assumed.
4. Every session ends by updating `docs/tracker/TODO.md`, `docs/decisions.md`, and
   `docs/tools-used.md`, and writing a session note in `docs/tracker/notes/`.

## Scope

Fire only. iOS only. LiDAR scan only. No user accounts — local persistence and an anonymous
device id. Deliberately out of scope: furniture detection, camera-only capture, Android,
multi-user sync, other disaster types.
