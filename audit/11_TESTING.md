# 11 · Testing

Canonical home for AUD-036. Every count below comes from a run done in this audit on 2026-09-28, branch
`drill-3d-fallback` at `3dc9c8e`, on the audit Mac. No source was modified to make anything pass.

## Results

| Gate | Command | Result |
|---|---|---|
| Corpus | `python3 backend/corpus/validate.py` | **valid** — 36 sources, 13 corpus files, 2 threshold files, 44 prevention tips, 1 orphan exception |
| Backend | `backend/.venv/bin/python -m pytest backend/tests/ -m "not live"` | **893 passed, 1 skipped, 29 deselected**, 4 warnings, 29.7 s (CPython 3.13.5 — not the deployed 3.12, AUD-041) |
| EditorCore | `swift test --package-path tools/editorcore` | **614 passed, 0 failed** (XCTest); Swift Testing: 0 tests |
| iOS type-check | `scripts/typecheck-ios.sh` | **ok** — app 177 files (Debug + Release), tests 86, UI tests 10, against iOS 17.0 / iPhoneSimulator26.5 SDK |
| iOS app suite | `xcodebuild test … -destination 'platform=iOS Simulator,id=<iPhone 17 Pro>' -derivedDataPath .build-merge CODE_SIGNING_ALLOWED=NO -resultBundlePath <scratch>/ios.xcresult` | **987 total: 972 passed, 7 failed, 8 skipped** (from `xcrun xcresulttool get test-results summary`) |

Not run: `-m live` (needs a funded Anthropic key), `-m mongo` (needs the Atlas URI), `scripts/demo-preflight.py`
(needs the bearer token; the secrets guard blocks reading `.env`, correctly), device tests.

## The 7 iOS failures — three root causes

### [AUD-036] The iOS suite is red for three reasons, none of them a product bug

**Severity:** P2
**Location / cause:**

| Failing tests | Root cause | Product bug? |
|---|---|---|
| `KeychainTokenStoreTests.testDifferentServicesAreIsolated`, `.testKeychainSatisfiesTheTokenStoreContract`, `.testSavingTwiceReplacesRatherThanKeepingTheFirstToken` — `KeychainError(status: -34018)` | `errSecMissingEntitlement`: the test host is unsigned (`CODE_SIGNING_ALLOWED=NO`), so it has no keychain access group. Reproduced locally now, not just in CI | No — environment. Run once with ad-hoc signing (`CODE_SIGN_IDENTITY=-`) to prove the store itself works |
| `EvacuationMockTimelineTests.testGenericFactoryExercisesAllThreeFixturesWithoutInventingPaths` — apartment: 2 tracks, expected 1 | **Stale expectation.** `apartment.json` gained a second profile (Biscuit the cat) on 2026-09-16. BLOCKERS §3 says the test "passes in EditorCore" and asks what differs between runners — **it never runs in EditorCore**: the file is wrapped in `#if !SWIFT_PACKAGE` (`escape_planTests/EditorCore/EvacuationMockTimelineTests.swift:5-6`) and compiles empty there | No — update the expectation to 2 (Sam + Biscuit) after confirming a pet track is intended (the renderer has a pet gait, so it is) |
| `SignedOutPathUITests.testTheGateCanBeDismissedWithoutAnAccount`, `.testTheGateSaysWhatAnAccountWouldUpload` — "no way past the auth gate" | **Test isolation.** `launchSignedOut(showGate: true)` (`SignedOutPathUITests.swift:29-39`) only *omits* `-auth.gate.dismissed YES`; it never forces `NO`. The flag persists in the app's `UserDefaults` on the simulator, so after any earlier dismissal (a previous test in the same run tapping "Continue without an account", or manual use of the simulator) the gate never appears. The button exists (`AuthGateView.swift:96`) | No — pass `-auth.gate.dismissed NO` (and `-onboarding.completed YES`) explicitly |
| `SignedOutPathUITests.testSettingsCarriesThePrivacyDisclosureSignedOut` — `XCTAssertTrue failed` at line 132 | The "What does an account upload?" button exists in Settings (`SettingsScreen.swift:346-351` → `AuthFormComponents.swift:185-188`) but sits far down a long scroll view; the test waits for it without scrolling. **Medium confidence** — confirm with the result bundle's screenshot | Probably not |

**Category:** testing
**Why this matters:** A permanently red suite hides new regressions; the "the soft gate has become a wall" message is
alarming and wrong.
**Evidence:** `xcresulttool` summary above; code reading of each test and its target.
**Affected systems:** CI `ios-tests`, S11.8 gate.
**Potential fix direction:** As in the table. All four fixes are test-side.
**Dependencies / considerations:** Update BLOCKERS §0/§3 — the EditorCore hypothesis there is wrong (AUD-048).

## Coverage gaps that matter (behaviour with no test)

| Behaviour | Why a test would have caught something | Finding |
|---|---|---|
| Profiles screen is reachable from the tab UI | Regression shipped unnoticed | AUD-020 |
| A home can be deleted from the UI | Same | AUD-021 |
| After `/build`, the draft is not scored and the editor opens | Regression vs `87c0610^` | AUD-023 |
| House reloads after another screen writes the same home | Silent data loss | AUD-013 |
| `ReadinessStore` ignores a late response for a previous home | Wrong score shown | AUD-014 |
| `/score` HTTP path honours recurrence | Dead feature | AUD-026 |
| `/build` with `image/jpeg` / HEIC input, oversize image | Photo path broken | AUD-024 |
| Request size / geometry bounds | DoS | AUD-004 |
| `/auth/*` rate limits | DoS / brute force | AUD-005 |
| Sync: conflict pull while the home is open | Copies pile up | AUD-015 (fakes already exist: `InMemoryHomeRepository`) |
| Concurrent `POST /homes` with the same base revision | Lost update | AUD-016 (`tests/fake_mongo.py` exists) |
| Settings snapshot uses the active home | Wrong home shared | AUD-027 |
| Every drill `routesNotice` string is engine text or cited `DrillInstructions` | Client-authored guidance | AUD-025 |
| Privacy copy matches what is sent | Test pins the wrong claim | AUD-050 |

## Test quality notes

- The project's tests are unusually good at pinning contracts (route guard walk, fixture byte-equality, schema parity,
  citation resolution, eval graders with pass/fail probes). The gaps above are almost all **UI wiring and cross-screen
  state**, which is exactly what the Foundation-only EditorCore package cannot see.
- `AccountPrivacyTests` pins the phrase "uploads nothing" — a test that locks in a false claim (AUD-050).
- 3 × `PytestRemovedIn10Warning` in `tests/test_convert.py` (class-scoped fixture as instance method) will become errors
  under pytest 10.
- The `-m live` suite and evals have never run with the current code on a funded key (AUD-002).
