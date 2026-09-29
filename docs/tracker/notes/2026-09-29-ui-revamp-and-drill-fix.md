# Retro — Linear revamp merge (`ui-revamp-1-foundation`) and the drill fix (`drill-3d-fallback`)

- **Who:** Anish (with Claude); retro written by S11.14
- **Date(s):** revamp merged 2026-09-25 (`6b5eea0`); drill fix committed 2026-09-26, merged 2026-09-29
- **Status when I stopped:** both on `origin/main`. This note exists because neither had one (AUD-048 item 6: "No note,
  no DONE").

## What happened

**Revamp.** `ui-revamp-1-foundation` (19 commits, `0247589` → `50157cf`) brought the dark-only Linear palette and
component kit, Home plus four tabs (Home, Tasks, House, Assistant, Settings), a dark 3D stage, the shared
`ReadinessStore` and `AppRouter`, and audit remediation Part B (`audit-ios-fixes`, B1-B11) merged into it before it went
to `main`. `87c0610` deleted `BetaScreen.swift` (audit item B9).

**Drill fix.** Since S9.2 (`bffb16c`) starting a drill opened the AR cover only, so the Simulator and non-LiDAR phones
had no drill and no drill was ever logged. `3dc9c8e` restores the 3D walkthrough as the default and makes AR an opt-in
"Walk it in AR" button on LiDAR devices. `147b5ef` lets two fixed-height buttons grow with Dynamic Type (minHeight 48).

## What was verified
- Revamp: CI full simulator run on `e64f343`, 987 tests, 971 passed / 8 failed / 8 skipped
  ([run 36180793666](https://github.com/vedang-123-ai/escape_plan/actions/runs/36180793666)); `ThemeContrastTests`,
  `AppRouterTests`, `OnboardingTests`, `BackendFailureTests`, `ConversationStoreTests` passed.
- Drill: walked 2026-09-26 in the iPhone 17 Pro simulator (Demo Home, Maya, fire): route drawn, timer running, Next
  advances step 1 → 2.
- Both together: local full run 2026-09-29 on `732c42c`, 987 tests, 972 passed / 7 failed / 8 skipped
  (`.build-s1114/TestResults.xcresult`); the 7 are the known AUD-036 set. Backend 893, EditorCore 614, type-check ok.

## What was NOT verified
- "Walk it in AR" has never been seen on a device.
- B1 (Assistant follows a home switch) never walked on a simulator; B2's green Score band not visually checked; B8's
  storage fallback never exercised.
- The revamp removed the only entry points to Profiles, delete and duplicate (with `BetaScreen.swift`). Nothing
  replaced them: AUD-020 (S11.20) and AUD-021 (S11.21).
- The revamp merge went to `main` without a session note or a recorded local run; the drill fix sat unpushed for three
  days, so every branch cut from `origin/main` in that time had no drill (AUD-034).

## Decisions / surprises
- Dark-only palette retired the "no new colour" rule; three guardrails replaced it (`docs/decisions.md`, 2026-09-25).
- 3D walkthrough is the drill; AR is opt-in (`docs/decisions.md`, 2026-09-26).

## Next steps
- S11.8 fixes the 7 iOS failures; S11.20 and S11.21 restore the removed entry points.
