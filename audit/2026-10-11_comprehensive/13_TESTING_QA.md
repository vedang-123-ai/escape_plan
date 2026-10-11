# 13 — Testing and QA

> **Authorship note.** Three subagent attempts at this domain (two `pro`, one `flash`) died immediately with `RESOURCE_EXHAUSTED (429)` and produced nothing. This report was written by the lead. It is narrower than the other domain reports: the lead ran the suites and read the agents' test-related findings, but did **not** read every test file line by line. Items marked *(reported by Agent N)* were not re-verified by the lead.

## 1. Executive summary
- The measured test baseline is **healthy**: iOS app unit-test target **1150 passed / 0 failed / 3 skipped** on an iOS 27.0 simulator; backend **1258 passed / 1 skipped / 31 deselected**; SwiftPM EditorCore **656 passed / 0 failed** (Agent 7, `/tmp` copy).
- Every one of those suites passes **while the physical-device build is broken** (A14-01) and while several HIGH behavioural defects exist (stale `ScoreCache`, duplicate-ID home copy, 502 bypassing the offline cache, chirality inversion). The suites are strong on pure logic and weak on integration seams, device-only code paths, and whole-app UI journeys.
- The UI-test target was **not run** by the lead (see §3). Agent 5 reports that onboarding-driving UI tests are bit-rotted.

## 2. Scope and files inspected
`escape_planTests/` (+`EditorCore/`), `escape_planUITests/` (file list only), `tools/editorcore` (via Agent 7), `backend/tests`, `docs/tracker/BLOCKERS.md` (count claims), `scripts/typecheck-ios.sh` (existence; via Agent 14: simulator-only target).

## 3. Methods and checks performed
| # | Check | Result | Label |
|---|---|---|---|
| 1 | `xcodebuild test -only-testing:escape_planTests`, iPhone 17, iOS 27.0 (24A434), `CODE_SIGNING_ALLOWED=NO`, derived data in `/tmp` | `** TEST SUCCEEDED **`, xcresult summary: 1150 passed, 0 failed, 3 skipped; 47.7 s wall; 757 `warning:` lines; the 5 `error:` string matches in the log are source-snippet lines belonging to warnings (parameter named `error`), not compile errors — lead checked | Verified by automated test |
| 2 | Backend `pytest -m "not live"` | 1258 passed, 1 skipped, 31 deselected, 1 warning, 40.2 s | Verified by automated test |
| 3 | EditorCore SwiftPM suite | 656 passed (Agent 7) | Verified by automated test |
| 4 | Release build `generic/platform=iOS` | **BUILD FAILED**, exit 65, `RoomCaptureController.swift:118:23 cannot assign to property: 'configuration' is a 'let' constant` | Verified (build) — reproduced independently by lead and Agent 14 |
| 5 | Simulator launch smoke (fresh install) + screenshot, relaunch + screenshot | App launched and showed the onboarding welcome screen ("Let's map your home", Get started / I'll do this later). Screenshots in `evidence/screens/` | Verified at runtime (launch only) |
| 6 | UI tests (`escape_planUITests`) | **Not run.** Several are env-gated recording/screenshot drivers; some need a live backend. Not attempted by the lead | Not verified |
| 7 | Tapping through the app | Not done: `simctl` has no tap/accessibility injection and the UI-test drivers were not run | Blocked by tooling |

Raw logs: `evidence/unit1.log`, `evidence/backend.log`, `evidence/device_build.log`, `evidence/launch.log`.

## 4. Findings

## [HIGH] A13-01 Test suites cannot detect device-only compile breaks
**Domain:** Testing/QA  **Location:** `scripts/typecheck-ios.sh`, `.github/workflows/gate.yml` (per Agent 14), `RoomCaptureController.swift:116-118`
**Observed behavior:** All local scripts and CI target the iOS Simulator. Code under `#if !targetEnvironment(simulator)` is never compiled.
**Evidence:** Simulator test run green (1150 passed) while `xcodebuild build -destination generic/platform=iOS` fails with the `let` constant error.
**Expected behavior:** At least one gate compiles the device slice.
**Root cause:** Gate design only covers the simulator SDK.
**Impact:** The LiDAR scan path — the app's headline feature — can break and ship unnoticed; here it blocks any archive/TestFlight build.
**Recommended improvement:** Add a `generic/platform=iOS` build (no signing) to the gate. Also evaluate whether the `RoomCaptureSession.Configuration` class→struct difference is an Xcode 27 SDK change (Agent 18).
**Dependencies:** A14-01.
**Verification status:** Verified (build run).  **Confidence:** High  **Effort:** Small

## [MEDIUM] A13-02 Bit-rotted UI tests (reported by Agent 5)
**Domain:** Testing/QA  **Location:** `GoldenPathRecordingUITests.swift`, `S44ScreenshotUITests.swift`
**Observed behavior:** Agent 5 reports they query onboarding buttons that no longer exist ("Take the tour", "Confirm & Continue"). Agent 18 describes it as `OnboardingFlowUITests` — the naming differs between agents.
**Evidence:** The current onboarding screen (runtime screenshot) shows "Get started" / "I'll do this later", consistent with the button names having changed.
**Expected behavior:** UI tests track the live onboarding.
**Root cause:** UI tests are mostly env-gated recording drivers, so they are not exercised by the default gate.
**Impact:** No automated end-to-end coverage of first launch. **Verification status:** Inferred from source + one runtime screenshot; the tests themselves were not run by the lead. **Confidence:** Medium  **Effort:** Small–Medium

## [MEDIUM] A13-03 Documented test counts are stale in the opposite direction
**Domain:** Testing/QA  **Location:** `docs/tracker/BLOCKERS.md` top stamp
**Observed behavior:** BLOCKERS cites iOS 1008 total (997 passed), backend 932, EditorCore 635. Measured today: iOS app target 1150 passed, backend 1258, EditorCore 656.
**Impact:** The tracker understates the suite; the repo's own rule says counts must come from `xcresulttool`. Low user impact, but submission documents quoting stale numbers would be inaccurate. (Different test scope — the lead ran `escape_planTests` only — so the figures are not strictly comparable.)
**Verification status:** Verified by automated test.  **Confidence:** Medium  **Effort:** Small

## [MEDIUM] A13-04 No tests for the seams where the HIGH defects live
**Domain:** Testing/QA
The specific tests that would have caught the consequential findings (not written; list only):
| Finding | Test that would catch it |
|---|---|
| A07-02 / A10-01 stale `ScoreCache` | Save score, edit home, assert cache invalidated or flagged stale; assert responder snapshot labels score age |
| A07-03 duplicate IDs | `HomeDocumentStore.duplicate` → assert no entity ID shared with the source home |
| A10-02 502 bypass | `APIClient` with stub returning 502/503 and a warm route cache → assert cached routes shown, labelled stale |
| A15-03 delete on 401 | Stub 401 on delete → assert user is told server erasure is unconfirmed |
| A08-01/02 mirroring | Round-trip a known asymmetric L-shaped room through `roomplan.py` and `PlanProjection`; assert handedness equals the 3D scene's |
| A17-02 overlap invariant | Property test: any model accepted by backend `validate` is accepted by `EditorValidation` |
| A17-03 score attribution | Score with a structural cap → assert the first listed deduction is the structural finding |
| A04-01 monthly alarm | Complete `alarm.test_monthly`, advance clock 31 days → assert it re-opens |
| A12-02 banner a11y | Accessibility audit of `BackendFailureBanner` exposing the action buttons |
| A14-01 | Device-slice compile in CI |
**Verification status:** Source-derived recommendations. **Confidence:** Medium  **Effort:** Medium

## [OBSERVATION] A13-05 Positive: large, fast, hermetic logic suites
Backend suite runs in ~40 s without live services; the iOS unit target runs in ~48 s including build; EditorCore needs no simulator. The deterministic routing/scoring core therefore has real regression protection.

## 5. Positive findings
- 1150 / 1258 / 656 passing counts, zero failures, reproducible on a clean derived-data path.
- 3 skips are explainable (keychain entitlement on unsigned host, per BLOCKERS) — not independently confirmed which 3.
- Hermetic design: live tests are marker-gated (`live`) and deselected by default.

## 6. Systemic issues and root causes
1. Gate coverage = simulator only → device-only code unguarded (A13-01).
2. Tests concentrate on pure logic; integration seams (cache↔edit, sync↔delete, client↔backend validation) are where HIGH findings cluster.
3. UI automation is largely recording/screenshot drivers, not assertions.

## 7. Unverified assumptions

- That UI tests are bit-rotted (Agent 5 claim, not run).
- Which tests are tautological — no systematic tautology review was performed by the lead.
- Flakiness: one run only; BLOCKERS claims ~1-in-3 environmental flake on red runs; not observed here.

## 8. Areas requiring further investigation
Run `escape_planUITests` (non-gated ones) on the iOS 27 simulator; line-by-line review for tautological assertions; check the 3 skipped tests by name; Instruments profiling now that a runtime exists.

## 9. Recommended priorities
1. Add device-slice build to the gate. 2. Run and repair UI tests for first launch. 3. Add the seam tests in A13-04 before fixing the underlying bugs. 4. Re-stamp BLOCKERS counts from `xcresulttool`.
