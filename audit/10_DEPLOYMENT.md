# 10 · Deployment, Release & Submission

Canonical home for AUD-001, AUD-002, AUD-034, AUD-037, AUD-038, AUD-041. There is no Vercel/web deployment; the
backend deploys to Render from `render.yaml`, the app is built with Xcode 26.

## Current state (observed 2026-09-28)

| Item | State | Evidence |
|---|---|---|
| Deployed backend up | ✅ `/health` 200 (after 51 s cold start) | curl |
| Deployed DB | ✅ `{"database":"ok","db_name":"escape_plan"}` | curl `/health/db` |
| 2026-09-25 guard fix live | ✅ `POST /diff_obstructions` without token → 401 | curl — **clears the BLOCKERS "Deployed backend NOT smoke-checked" line** |
| Deployed bearer token matches the app's | ❓ not re-checked (reading `.env` is blocked by the repo's secrets guard, correctly) | BLOCKERS §1 says it does not match |
| Anthropic credits | ❓ not re-checked (would spend credit) | BLOCKERS §1 says exhausted |
| `origin` branches | only `main` | `git ls-remote --heads origin` |
| This branch vs `origin/main` | 2 ahead, 0 behind, **unpushed** | `git branch -vv` |
| Render deploy pinning | `pip install -r requirements.lock`, Python 3.12.6 | `render.yaml` |
| iOS deployment target | 17.0 (all configs), type-checks at 17.0 | `typecheck-ios.sh` |

## Environment variables (backend)

| Var | Required | Default | Validated at startup | Notes |
|---|---|---|---|---|
| `BACKEND_BEARER_TOKEN` | yes | — | yes (refuses to start) | Render `generateValue`; also bundled into the app (AUD-003) |
| `ANTHROPIC_API_KEY` | no | — | no | missing → AI endpoints 502 |
| `ANTHROPIC_MODEL` | no | `DEFAULT_MODEL` | yes (supported set) | `render.yaml` pins `claude-sonnet-5` (validity re-checked 2026-09-25, rejected finding) |
| `MONGODB_URI` / `MONGODB_DB_NAME` | no | — / `escape_plan` | malformed → cloud disabled, logged | |
| `JWT_SECRET_KEY` | no | — | ≥ 32 bytes | |
| `JWT_ACCESS_TTL_MINUTES` | no | 60 | int | AUD-031 |
| `AI_RATE_PER_MIN` / `AI_RATE_BURST` / `AI_MAX_CONCURRENT` | no | 6 / 3 / 4 | positive | Not pinned in `render.yaml` on purpose |

iOS configuration: base URL (default `https://escape-plan-backend.onrender.com`) and token from `UserDefaults` or the
bundled, gitignored `escape_plan/BackendConfig.local.json` (AUD-003, AUD-009). `scripts/demo-preflight.py` checks both.

---

### [AUD-001] Deployed bearer token does not match the app's (known, owner-only)

**Severity:** P0 (if still true)
**Location:** Render dashboard `BACKEND_BEARER_TOKEN`; root `.env`; `escape_plan/BackendConfig.local.json`;
`docs/tracker/BLOCKERS.md` §1
**Category:** deployment
**What I found:** Carried from BLOCKERS §1 ("a fresh install gets 401 on every deterministic endpoint"); not
independently re-verified in this audit because it requires reading the secret.
**Current behavior (per BLOCKERS):** `/routes`, `/score`, `/convert`, `/evacuate` → 401 → the whole demo path fails.
**Expected behavior:** The token the app ships with is accepted by the deployed service.
**Evidence:** BLOCKERS §1 (2026-09-16 narrowing) and `scripts/demo-preflight.py` output recorded there.
**Potential fix direction:** Owner makes the two match, then runs `backend/.venv/bin/python scripts/demo-preflight.py`.
**Dependencies / considerations:** Any tester whose app persisted the old token keeps it (AUD-009). Consider AUD-003's
token model before rotating again.

### [AUD-002] Anthropic account out of credits (known, owner-only)

**Severity:** P1
**Location:** Anthropic console; `docs/tracker/BLOCKERS.md` §1
**Category:** deployment / external service
**Current behavior (per BLOCKERS):** `/chat`, `/build`, `/explain`, `/analyze` return 502 by design; 13 `-m live`
tests and the live eval runner cannot run.
**Why this matters:** The Assistant and Import Plan are dead in any demo until topped up; AUD-024/AUD-030 cannot be
validated live.
**Potential fix direction:** Top up; then run `-m live` tests and `tests/evals/test_evals_live.py`.

---

### [AUD-034] The drill fix exists only on this machine

**Severity:** P1
**Location:** local branch `drill-3d-fallback`: `147b5ef` (button `minHeight`), `3dc9c8e` (3D drill restored, AR opt-in);
`origin` has only `main`
**Category:** deployment / process
**What I found:** `git branch -vv` → `[origin/main: ahead 2]`; `git ls-remote --heads origin` lists one head.
**Current behavior:** Everyone else building from `origin/main` gets the S9.2 behaviour where "start drill" opens only
the AR cover — no drill at all on the Simulator or non-LiDAR phones (BLOCKERS "Drill regression"). The fix, its
BLOCKERS entry and its decisions row are also unpushed.
**Expected behavior:** Per `CLAUDE.md`: run the gate, `git merge --no-ff` into `main`, push.
**Evidence:** git commands above.
**Potential fix direction:** Push the branch, run the gate (all green today except the 7 known iOS failures, see
11_TESTING), merge. **Considerations:** The activity-log modification in the working tree is Stop-hook output.

---

### [AUD-037] Nothing blocks a broken `main` from deploying, and the app test suite gates nothing

**Severity:** P2
**Location:** `.github/workflows/gate.yml` (`ios-tests` is `workflow_dispatch` only), `render.yaml` (no
`autoDeployTrigger`/`autoDeploy` setting — Render's default deploys on every push to the tracked branch)
**Category:** deployment / CI
**What I found:** Backend and iOS type-check run on push, but Render deploys independently of CI (unless configured in
the dashboard, which this audit cannot see). The simulator suite — currently red with 7 failures — runs only when
someone remembers to press the button.
**Current behavior:** A merge that breaks `pytest` still deploys to the service the demo depends on (this happened on
2026-09-19 per BLOCKERS). iOS regressions like AUD-020 (a test could reach Profiles from Home) are invisible until someone
runs the suite.
**Expected behavior:** Render "deploy after CI checks pass" (dashboard setting or `autoDeployTrigger: checksPass` in the
blueprint), and a scheduled nightly `ios-tests` run.
**Evidence:** File reading; dashboard state unknown (**low confidence** on the Render half).
**Potential fix direction:** Add `schedule:` to `gate.yml` for `ios-tests`; set the Render trigger.
**Dependencies / considerations:** Fix the 3 environmental test failures first (AUD-036) or the nightly run is always red.

---

### [AUD-038] `docs/tools-used.md` may not disclose every AI tool used on the project

**Severity:** P2
**Location:** `docs/tools-used.md` (lists Claude Code as the AI pair programmer; no other AI coding agent);
`git worktree list` on the audit machine shows worktrees of this repository under
`~/.gemini/antigravity/brain/…/worktrees/` (named `subagent-INDEPENDENT-REVIEWER-…`, `subagent-Vision-Spike-Implementer-…`);
root `improved_prompt.md` is a prompt for orchestrating agents
**Category:** submission compliance
**What I found:** Evidence on the audit machine that Google Antigravity agents were run against this repo, including one
named for the Vision spike. The Congressional App Challenge requires disclosure of tools used (the file says so itself).
**Current behavior:** Not listed.
**Expected behavior:** Every AI tool that produced or reviewed project work is listed with its role.
**Evidence:** `git worktree list`; `grep -ci "gemini\|antigravity" docs/tools-used.md` → 0. **Medium confidence**: the
worktrees prove the tool touched the repo, not what it contributed; the owner knows.
**Potential fix direction:** Owner adds a row (tool, version, what it did) or confirms it contributed nothing shipped.
**Dependencies / considerations:** Also prune the stale worktrees (`git worktree prune` after review).

---

### [AUD-041] Local Python differs from production; test tools ship to production

**Severity:** P3
**Location:** `backend/.venv` (CPython **3.13.5**), `render.yaml` (`PYTHON_VERSION 3.12.6`), `gate.yml` (3.12),
`backend/requirements.txt` (`pytest`, `jsonschema`, `httpx` as runtime requirements)
**Category:** deployment
**What I found / current behavior:** The local gate runs on a different interpreter than the one that serves traffic;
production installs pytest.
**Expected behavior:** Local venv on 3.12 (e.g. `uv venv -p 3.12`); split `requirements-dev.txt` for test-only packages
(one already exists for graph rendering) and keep `requirements.lock` runtime-only.
**Evidence:** `backend/.venv/bin/python --version`; file reading.
**Considerations:** `httpx` is also an `anthropic` dependency — keep it.

## Release checklist gaps (for S11.12/S11.13)

- Run `scripts/demo-preflight.py` after AUD-001 is fixed; record output in BLOCKERS.
- Make `/health` report the deployed commit (`RENDER_GIT_COMMIT` is available on Render) so smoke checks prove *which*
  build is live.
- Decide on Render paid tier (cold start 51 s) vs. an in-app "waking the server" state before filming (AUD-032).
- App Store privacy label must match AUD-050's corrected copy.
