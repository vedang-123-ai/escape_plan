# Audit remediation — verified findings from the 2026-09-25 external audit

- **Who:** Claude Code (autonomous session for Anish)
- **Date(s):** 2026-09-25
- **Status when I stopped:** see "Part A" and "Part B" below; BLOCKERS "Audit remediation (2026-09-25)" is the live list.

## What happened

### Part A · backend + CI (`audit-backend-fixes` → `main`)

- `/diff_obstructions` now requires the bearer token. `tests/test_route_guards.py` walks every route (FastAPI 0.141 wraps
  included routers in `_IncludedRouter`, so the walk recurses into `original_router` and is cross-checked against the
  OpenAPI document) and asserts 401 with no/wrong credentials outside a four-path allow-list. Confirmed it goes red
  against the old `main.py`.
- `app/rate_limit.py`: AI cost guard (token bucket per IP + global semaphore), on the four AI routes, 429 + `Retry-After`.
  `conftest.py` relaxes the limits for unrelated tests; `test_rate_limit.py` sets its own.
- `.github/workflows/gate.yml` (backend, ios-typecheck, manual ios-tests). `macos-26` exists and carries Xcode 26.
- `backend/requirements.lock` from a clean CPython 3.12 venv; Render installs it.
- `cloud_repo._is_duplicate_key_error` by `isinstance`.
- Backend 843 → **893** passed (1 skipped, 29 deselected). CI run 36178279583 green on both jobs; EditorCore 609.

## Decisions / surprises

- CI installs the lock, not `requirements.txt` (what Render deploys), with a drift check against `requirements.txt`.
- The AI limits are not pinned in `render.yaml`, so dashboard tuning survives a blueprint sync.
- The route walk needed the `_IncludedRouter` handling: on FastAPI 0.141 `app.routes` no longer lists `/chat`, `/auth/*`
  or `/homes*` directly, so a naive walk would have silently skipped exactly the routers most likely to be added later.
- This sandbox cannot reach `onrender.com` (egress policy), so the deployed smoke check is left to the owner.
- `/score?include_recommendations` also spends AI credit and is not guarded; logged, not fixed (outside the listed scope).

## Questions for teammates

- @owner: after Render redeploys `main`, run `curl -s https://escape-plan-backend.onrender.com/health` (200) and
  `curl -s -o /dev/null -w '%{http_code}' -X POST https://escape-plan-backend.onrender.com/diff_obstructions -H 'Content-Type: application/json' -d '{}'` (401).

## Next steps

- Part B (iOS) on `audit-ios-fixes` → `ui-revamp-1-foundation`; see the section below once it lands.
