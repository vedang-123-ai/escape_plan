# S11.20 — Household profiles are reachable again

- **Who:** Anish (with Claude Code)
- **Date(s):** 2026-10-02
- **Status when I stopped:** DONE. AUD-020 fixed, placement chosen by Anish, House walk passed, merged to `main`.

## What happened

**Finding re-confirmed on origin/main (5e46008):** `grep -rn "ProfilesScreen(" escape_plan` found only the
`#Preview` (`ProfilesScreen.swift:240`).

**MISSION 1, placement (Anish's call, live in the simulator).** Both candidates were built and shown with screenshots:
(A) a "Household" row on Home under "Run a fire drill" / "Open 3D house"; (B) the same row at the top of Tasks'
"Family plan", below every task. Anish chose A. B was removed (`TasksScreen.swift` is unchanged on the branch).

- `HouseholdRow` (in `ProfilesScreen.swift`): "Household" + who lives there ("Add who lives here", up to three names,
  or "N people"), 52 pt min height, one VoiceOver button, `accessibilityIdentifier("household.row")`.
- Home pushes `ProfilesScreen(homeID:store: library.store)`. The screen's title is now "Household" to match the row.
- The drill's "No family profiles yet" state has an "Add family members" `DSPrimaryButton` that opens the screen as a
  sheet; on dismiss `reloadAfterProfiles()` clears `homeModel`/`built`/`overlay` and runs `load()` again (it runs
  once per push otherwise, so the drill kept saying "No family profiles yet").

**MISSION 2.** Leaving the screen after a saved change reloads readiness for the active home. First written as
`readiness.load(api:)` (the playbook nuance); the swift-scenekit-reviewer pointed out `load` does not cancel a
/score already in flight, so on a cold start the old household's score could land last (the AUD-014 race). Changed
to re-read the saved file and call `readiness.replaceActiveHome(saved, api:)`, whose `rescore` cancels the previous
request. ReadinessStore is unchanged (S11.23's file). House needs no wiring (S11.19). **Verified, not assumed**, in
the simulator, 2026-10-02:

1. Opened House on "New Home" (one person, "Ada 703"): person picker "Everyone / Ada 703".
2. Home tab → Household → + → "Grandma" → Save.
3. House tab → yellow line "This home was changed on another screen or device, so the newer version is shown. Undo
   history was cleared." and the "Escape routes" picker reads "Everyone / Ada 703 / Grandma".
4. Home tab → the Household row reads "Ada 703, Grandma" (it reads `ReadinessStore.activeHome`).

**MISSION 3, accessibility floors (ecc:a11y-architect, then fixed):** accent-coloured text buttons (Cancel, Save, the
drill sheet's Done) were ~3.6:1 on a sheet → `Theme.accentText`; tag toggles' "on" track 2.97:1 → `Theme.accentText`;
the empty state's bare "Add Profile" text button (~20 pt tall) → `DSPrimaryButton`; the name placeholder ~2.4:1 →
`prompt:` in `Theme.supporting`; tag chips truncated at accessibility sizes → the vertical fallback is one wrapping
text line; rows tappable only on their text → full-width `contentShape`; Delete swipe-only → VoiceOver custom action;
autosave failure now announced; a rejected save now alerts on the editor sheet (the old alert sat under the sheet).
Left open, with owners, in BLOCKERS: the screen still draws on system surfaces (no `dsPage`), `DSPrimaryButton`'s icon
is read by VoiceOver, Settings' toggles share the 2.97:1 track, VoiceOver behaviour never exercised on a device.

**MISSION 4, `ProfilesEntryUITests` (new), signed out, onboarding skipped by the same launch arguments as
`EntryPointUITests.launchPastOnboarding()`, each test on a blank home it builds ("Room 1" becomes the bedroom):**
- `testHomeHouseholdRowAddsAPersonTheDrillThenOffers`: Home → Household → add → back → Home's row label contains the
  name (proves the readiness reload) → Run a fire drill → "Practice with <name>" exists, "No family profiles yet" not.
- `testDrillEmptyStateOpensProfilesAndReloads`: Run a fire drill → "Add family members" → add → Done → the drill
  offers the person.
- **No backend needed:** "reaches the drill" is asserted as the drill's person picker (past the empty state), not a
  /routes result.
- First run 2/2 (`.build-s1120-ui.xcresult`).

**MISSION 5:** "Should a new scan or build ask 'Who lives here?'" logged on BLOCKERS for Anish; not built.

**Acceptance:**
- `scripts/typecheck-ios.sh`: ok ×4 (`.build-s1120-tc.log`).
- Full suite, 2026-10-02, first run: **1052 tests, 1041 passed, 0 failed, 11 skipped** (xcresulttool,
  `.build-s1120-full.xcresult`; S11.19 was 1050/1039/0/11, the +2 are `ProfilesEntryUITests`). AppRouterTests,
  ThemeContrastTests and ProfilesEntryUITests all Passed in it.
- swift-scenekit-reviewer: no must-fix; all three should-fixes taken (race-free reload, a test assertion on the
  reload, scoped test queries), plus the stale comments.
- ecc:a11y-architect: floor breaks fixed as above.
- AppRouter: no route was needed (Home and the drill push/present directly), so `AppRouter.swift` and
  `AppRouterTests.swift` are unchanged; AppRouterTests and ThemeContrastTests ran green in the full suite.

## Decisions / surprises
- Placement: Home (decisions.md 2026-10-02). Screen title "Profiles" → "Household".
- `replaceActiveHome` instead of `load` on dismiss (decisions.md).
- The Household row is hidden for an unreviewed AI draft, like the score and the drill card (AUD-023). Intentional.
- The simulator screenshot tool lags a frame behind taps and pushes; take a second screenshot before believing a
  blank or half-animated frame.

## Questions for teammates
- @Anish: should a fresh scan or manual build ask "Who lives here?" right away (BLOCKERS, S11.20 findings)?
- @S11.10: DrillScreen's empty state changed; merge origin/main before the device pass.

## Next steps
S11.21 (delete and duplicate homes; no blank home until the first edit). Each `ProfilesEntryUITests` run adds a blank
home to the simulator; S11.21's "no blank home until the first edit" will change what those tests leave behind.
