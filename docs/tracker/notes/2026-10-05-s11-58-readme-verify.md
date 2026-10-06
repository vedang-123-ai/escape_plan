# S11.58 — README verified on a stranger's path

- **Who:** agent I (Claude), for Anish
- **Date(s):** 2026-10-05
- **Status when I stopped:** README and backend/CLAUDE.md corrected; every README step run from a fresh tree.

## What happened
- Fresh tree: `git archive f3cd237` (origin/main) into the scratchpad. Cloning from GitHub was blocked by the agent
  sandbox; the archive is what a "Download ZIP" gives a judge, with nothing gitignored in it.
- Backend: `python3.12 -m venv .venv`, `pip install -r requirements.txt`,
  `BACKEND_BEARER_TOKEN=judge-local-token uvicorn app.main:app --port 8001` (8000 was busy). curl: `/health` 200,
  `/routes` 401 without token / 200 with, `/score` 200 (66 empty checklist, 71 with meeting point), the four AI
  endpoints 502 with a plain message, no traceback.
- macOS `/usr/bin/python3` 3.9.6: installs, then crashes on import (`str | None`). README now steers to 3.12.
- Tests: `pip install -r requirements-dev.txt`, corpus valid, pytest 1249 passed / 1 skipped / 31 deselected,
  EditorCore 646 tests, 0 failures.
- iOS: `xcodebuild build ... DEVELOPMENT_TEAM=ZZZ9999999` (signing on) and `... CODE_SIGNING_ALLOWED=NO` both
  BUILD SUCCEEDED for `iPhone 17 Pro`. A scratch-only UI test (never committed) on a new simulator device then walked
  README steps 3-4 with no launch arguments, screenshotting each step. All steps passed; see BLOCKERS "S11.58 findings".
- Cleanup: scratch simulator deleted, derived data deleted, iOS lock released.

## Decisions / surprises
- No project change needed for signing: Simulator builds sign "Sign to Run Locally" whatever the team id.
- "Test connection" uses `/health`, which needs no token, so "Connected" does not prove the token is right; the score
  loading does.

## Questions for teammates
- @Anish: an old uvicorn (started about 10 days ago) holds port 8000 on the dev Mac. Stop it if it is not needed.

## Next steps
- `backend/README.md` fixes listed in BLOCKERS S11.58.
