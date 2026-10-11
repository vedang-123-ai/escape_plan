# Fix brief (shared by all fix engineers)

You are fixing issues found by the 2026-10-11 audit of the "Escape Plan" iOS app (Congressional App Challenge, submit by 2026-10-24; fire / earthquake / severe-weather readiness; SwiftUI+SceneKit app + FastAPI backend).

## Sources of truth (read-only, in the MAIN checkout)
`/Users/anish/Documents/Congressional App Challenge/Escape-Plan/audit/2026-10-11_comprehensive/`
- `20_REMEDIATION_ROADMAP.md` (priorities), `19_CROSS_SYSTEM_FINDINGS.md` (lead re-verification; **severity adjustments and false positives are authoritative there**), and the domain report that contains each finding ID you own (e.g. `A07-02` → `07_DATA_PERSISTENCE_STATE.md`). Read the full finding text, including its Evidence and Recommended improvement.
- Findings were produced largely by source reading; **re-verify each one against the current code before changing anything.** If a finding is a false positive, already fixed, or intentional (documented in a code comment/decision log), do NOT change code — record it as "no change" with evidence in your result file.

## Your workspace
You work ONLY in your own git worktree `/tmp/ep-fix-<lane>` on branch `audit-fix/<lane>` (already created from `main` @ 7c9021c). Never `cd`-and-edit the main checkout, never touch other lanes' worktrees, never switch branches, never push, never force anything, never `git stash`/`reset --hard`/`clean`. Commit to YOUR branch with clear messages (small logical commits; `git add` specific files). Do not merge. The lead merges branches.
Because the worktree is a fresh checkout it lacks gitignored files: `escape_plan/BackendConfig.local.json` is intentionally absent (do not copy, read, print or create it; it contains a secret) and `backend/.venv` is absent — use the main checkout's interpreter: `"/Users/anish/Documents/Congressional App Challenge/Escape-Plan/backend/.venv/bin/python"` run from `/tmp/ep-fix-<lane>/backend` (e.g. `PYTHONDONTWRITEBYTECODE=1 <that python> -m pytest -p no:cacheprovider -q -m "not live"`; baseline 1258 passed/1 skipped).

## File ownership (HARD RULE)
Edit only files in your lane's OWNED list (given in your prompt). New files are fine inside your lane's area (e.g. new test files — prefer NEW test files over editing shared ones). If a correct fix needs a file owned by another lane, do not edit it: describe the needed change in your result file under "Requested cross-lane changes". Do not edit `docs/tracker/*`, `docs/decisions.md`, `audit/*`, `.claude/*`, or the Xcode `project.pbxproj` unless your lane owns it.

## Project rules to read first (short)
Repo `CLAUDE.md`, `escape_plan/CLAUDE.md`, `.claude/rules/languages/swift.md` (and `python.md`/`paths/corpus.md` if you touch those). Key points: no new colours outside `Theme.swift`; never re-enable `allowsCameraControl`; keep `CameraRigModel` free of SceneKit/UIKit; the AI never computes routes or invents safety guidance; every user-facing safety string needs a source in the corpus; **do not change fire-safety wording from memory — only with a source you actually fetched (USFA, NFPA, FEMA, Red Cross, CPSC, NIST, ready.gov, NWS, USGS) and cite it in the code/corpus the way the repo does; flag every safety-content change for fire-professional review in your result file.** Do not weaken disclaimers, 911-first behaviour, or consent flows. Minimal, targeted changes: no drive-by refactors, no feature additions beyond the finding, preserve existing comments/docstrings unrelated to your change.

## Testing rules
- Add or update tests proving each fix (test must fail without the fix where feasible). 
- Backend: run pytest as above. EditorCore: Foundation-only files are symlinked into `tools/editorcore`; if you change one, also run `swift test` there **from a /tmp copy** (`cp -R` without `.build`) — or run it in the worktree's `tools/editorcore` with `--scratch-path /tmp/ep-fix-<lane>-scratch`.
- iOS: create your OWN simulator so lanes don't collide: `xcrun simctl create ep-<lane> "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0` (check `xcrun simctl list devicetypes runtimes` if the identifiers differ), build/test with `xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan -only-testing:escape_planTests/<Suite> -destination 'platform=iOS Simulator,id=<your id>' -derivedDataPath /tmp/ep-fix-<lane>-dd CODE_SIGNING_ALLOWED=NO -resultBundlePath /tmp/ep-fix-<lane>-results.xcresult`. Targeted suites first; before finishing run the whole `escape_planTests` target once (baseline: 1150 passed, 0 failed, 3 skipped, ~50 s + build). Delete your simulator at the end (`xcrun simctl delete <id>`). Other lanes build concurrently, so builds may be slow; retry once on a flaky infrastructure failure (not on a real test failure). Also run `scripts/typecheck-ios.sh` if your change adds/moves files (read it first).
- Never claim a test passed unless you ran it; paste exact counts.

## Result file
When done, write `/tmp/ep-fix-<lane>/FIX_RESULT_<lane>.md` (do **not** commit it) containing: per finding ID — status (Fixed / No change: false positive / No change: intentional / Deferred: reason / Needs cross-lane change), files changed, what the fix does, tests added and exact test results, residual risk, and any safety-content changes needing expert review. Then reply with a ≤12-line summary (branch name, commits, test counts, deferred items).

