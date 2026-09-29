# 17 · Verification Log

Every command whose output this audit relies on, in the order run (2026-09-28, audit Mac, repo root unless noted).
Scratch artefacts (scripts, raw logs, `ios.xcresult`) were written to the session scratchpad, not the repo; re-run the
commands to reproduce.

## Repository state

```bash
git fetch origin
git rev-list --left-right --count HEAD...origin/main     # 2 0
git branch -vv                                            # drill-3d-fallback [origin/main: ahead 2]
git ls-remote --heads origin                              # 1 head (main)
git worktree list                                         # includes ~/.gemini/antigravity/.../worktrees/* (AUD-038)
git show --stat 3dc9c8e 147b5ef                           # drill fix + button minHeight (AUD-034)
```

## Gates

```bash
python3 backend/corpus/validate.py
# Corpus valid: 36 sources, 13 corpus files, 2 threshold file(s) consistent, 44 prevention tips, 1 orphan exception(s).

backend/.venv/bin/python -m pytest backend/tests/ -m "not live" -q
# 893 passed, 1 skipped, 29 deselected, 4 warnings in 29.74s   (CPython 3.13.5)

swift test --package-path tools/editorcore
# Executed 614 tests, with 0 failures

bash scripts/typecheck-ios.sh
# ok escape_plan (177 files, -DDEBUG) / (177 files, release) / escape_planTests (86) / escape_planUITests (10)

xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,id=ED8548A7-6B64-4BC4-B7C3-1908C4206AC5' \
  -derivedDataPath .build-merge -resultBundlePath <scratch>/ios.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path <scratch>/ios.xcresult
# result Failed: totalTestCount 987, passed 972, failed 7, skipped 8
```

## Live service (read-only)

```bash
curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' https://escape-plan-backend.onrender.com/health
# 200 51.199440s
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://escape-plan-backend.onrender.com/diff_obstructions \
  -H 'Content-Type: application/json' -d '{}'
# 401
curl -s https://escape-plan-backend.onrender.com/health/db
# {"database":"ok","db_name":"escape_plan"}
```

## Measurements

```python
# bigroom.py (scratch): scale every coordinate of schema/fixtures/twostory.json by k, time compute_route_plan(fire)
# k=1: 0.07s   k=4: 1.15s   k=10: 7.24s          (AUD-004)

# Argon2 verify, 5 iterations, app.auth.passwords.verify_password
# 36.5 ms average                                 (AUD-005)
```

## Key greps (each backs a claim in the reports)

```bash
grep -rn "ProfilesScreen(" escape_plan                    # only its own #Preview (AUD-020)
git show 87c0610^:escape_plan/Screens/BetaScreen.swift    # old Profiles/Delete/Duplicate/Export entry points
grep -rn "delete(homeID\|duplicate(homeID" escape_plan --include='*.swift'   # none in Screens/ (AUD-021)
grep -rn "\.analyze(\|\.explain(" escape_plan             # no UI call sites (AUD-022)
git log -S ".analyze(home" --oneline -- escape_plan       # dac8673 removed it
grep -rn "nearby sturdy building" backend escape_plan     # engine text vs DrillScreen.swift:830 (AUD-025)
grep -rn "timeout\|max_retries" backend/app/ai            # none (AUD-035)
grep -rn "recurrence_days" escape_plan                    # none (AUD-026)
grep -rn "needs_rehash" backend/app                       # definition only (AUD-011)
grep -n INFOPLIST_KEY_UIFileSharingEnabled escape_plan.xcodeproj/project.pbxproj   # Debug + Release (AUD-008)
grep -rn "uploads nothing" escape_planTests               # AccountPrivacyTests pins the claim (AUD-050)
for f in escape_plan/Fixtures/*.json; do cmp -s "$f" "schema/fixtures/$(basename "$f")" || echo DIFF; done   # none
git grep -lE 'sk-ant-api[0-9]'                            # none
```

## Not run (and why)

| Check | Why not |
|---|---|
| `scripts/demo-preflight.py` | needs the bearer token from `.env`; the repo's secrets guard blocked reading it |
| `pytest -m live`, live evals | would call Anthropic (credits reported exhausted; spending is the owner's decision) |
| `pytest -m mongo` | needs `MONGODB_URI` |
| Device checks (LiDAR, AR, haptics) | no physical device in this audit |
| Manual simulator walk-through of UI flows | project convention: UI is iterated live with Anish; audit relied on code + the automated UI tests |
