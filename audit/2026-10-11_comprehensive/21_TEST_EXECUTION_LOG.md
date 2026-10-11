# 21 — Test Execution Log

All commands run 2026-10-11 from the repo root `/Users/anish/Documents/Congressional App Challenge/Escape-Plan` unless noted. All build products went to `/tmp` (not the repo). Raw logs copied to `evidence/`. Toolchain: Xcode 27.0 (27A266a), macOS 27.0.1. Labels follow the audit's verification vocabulary.

## Environment
| Check | Command | Result |
|---|---|---|
| Simulator runtimes at 00:18 | `xcrun simctl list runtimes` | **Empty**; all devices "unavailable, runtime profile not found" (iOS 26.5 profile missing) |
| Simulator runtimes at 00:43 | same | `iOS 27.0 (27.0 - 24A434)` present; devices incl. iPhone 17, iPhone 18 Pro available. The runtime appeared between these checks (cause not determined — likely finished installing). Agents 16 and 18 reported it correctly; Agents 3, 5, 7, 8, 9, 11, 12 reported it blocked, which was accurate when they ran. **Every report that says "runtime blocked" therefore predates the runtime and is a source-only analysis.** |
| Repo cleanliness | `git status --short` | `M docs/tracker/activity-log.md` (pre-existing before the audit) and `?? audit/2026-10-11_comprehensive/`. No other changes. |

## Runs
### R1 — iOS unit tests (Verified by automated test)
```
xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
  -only-testing:escape_planTests \
  -destination 'platform=iOS Simulator,id=59D89E8E-DB99-4075-BAC6-05178427D460' \
  -derivedDataPath /tmp/audit-dd-lead -resultBundlePath /tmp/audit-lead/unit1.xcresult CODE_SIGNING_ALLOWED=NO
```
- Exit 0, `** TEST SUCCEEDED **`, 47.7 s wall.
- XCTest console: `Executed 1029 tests, with 3 tests skipped and 0 failures`.
- `xcrun xcresulttool get test-results summary`: **passedTests 1150, failedTests 0, skippedTests 3**, device iPhone 17 / iOS 27.0. (1150 > 1029 because Swift Testing cases are counted in addition to XCTest.)
- Log contains 757 `warning:` lines (largely Swift concurrency / MainActor isolation diagnostics, see A14-06); runtime warnings in the result include QoS priority-inversion notices. The 5 `error:` string matches are source snippets accompanying warnings, not build errors.
- Raw: `evidence/unit1.log`.

### R2 — Backend tests (Verified by automated test)
```
cd backend && PYTHONDONTWRITEBYTECODE=1 .venv/bin/python -m pytest -p no:cacheprovider -q -m "not live"
```
- Exit 0, **1258 passed, 1 skipped, 31 deselected, 1 warning, 40.2 s**. Also independently reported by Agent 6 (same counts, 32.8 s). Raw: `evidence/backend.log`.

### R3 — EditorCore SwiftPM (Agent 7; Verified by automated test, not re-run by lead)
`/tmp` copy of `tools/editorcore`: **656 passed, 0 failed**. Agent 1 also cites 656.

### R4 — Release device build (Verified by build)
```
xcodebuild build -project escape_plan.xcodeproj -scheme escape_plan -destination 'generic/platform=iOS' \
  -configuration Release -derivedDataPath /tmp/audit-dd-lead-dev CODE_SIGNING_ALLOWED=NO
```
- Exit **65**, `** BUILD FAILED **`:
  `escape_plan/Capture/RoomCaptureController.swift:118:23: error: cannot assign to property: 'configuration' is a 'let' constant`.
- Reproduced independently by Agent 14 (`evidence/14_build_runs.md`). The simulator build of the same sources succeeds because the line is inside `#if canImport(RoomPlan) && !targetEnvironment(simulator)`. Raw: `evidence/device_build.log`.

### R5 — Simulator launch smoke (Verified at runtime — launch only)
Installed `Debug-iphonesimulator/escape_plan.app` (bundle id `cac.Escape-Plan`) on iPhone 17 / iOS 27.0, launched, waited ~12 s, screenshot → `evidence/screens/01_first_launch.png` shows a fresh-install onboarding screen: page dots (4), house icon, "Let's map your home", body copy about "cited prevention basics, a readiness checklist, and an escape route for every person who lives here", **Get started** and **I'll do this later**, dark theme. App was then relaunched (`simctl launch`), screenshot `02_relaunch.png` captured (not inspected in detail by the lead). Simulator shut down afterwards.
- Not exercised: any interaction past the first screen (no tap injection available through `simctl`; UI-test drivers not run).

### R6 — Bundle contents check (Verified by source/build artifact inspection)
`ls escape_plan.app` of the Debug simulator build contains `BackendConfig.local.json`, `CLAUDE.md`, `README.md`, demo-home JSONs and `prevention_tips.json`. `git check-ignore` confirms `BackendConfig.local.json` is gitignored (`.gitignore:21`) and `git ls-files` shows it untracked, yet it is copied into the app bundle (confirms A14-02 for Debug; Release inheritance per Agent 14, not separately re-checked by the lead because the Release device build fails).

## Not run
- `escape_planUITests` — not run by anyone (env-gated drivers / live-backend dependence / suspected bit-rot).
- Network-failure, denied-permission, invalid-input and relaunch-restoration runtime scenarios — **not performed**; covered by source inspection and unit tests only.
- Instruments / profiling — not run; all performance findings other than the backend `/score` timing (Agent 11, python benchmark) are inferred from code.
- Physical device, LiDAR scan — Blocked by environment (no device; also blocked by A14-01).
- Live Anthropic-backed endpoints — not exercised (documented 502 from exhausted credits; not re-verified).

## Subagent execution record
18 investigators were launched (17 + the skeptical reviewer). 17 completed with reports. The Testing agent failed three times (2× `pro`, 1× `flash`) with `RESOURCE_EXHAUSTED 429` before doing any work; its domain was done by the lead (`13_TESTING_QA.md`, narrower than the others). Total reports: 00–21 (all present).

