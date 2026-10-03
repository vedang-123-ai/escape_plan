# Demo trim 1 — Hazard Hunt and re-scan review deleted, accounts switched off, banners fade

- **Who:** P1 (Anish's session, agent-run)
- **Date(s):** 2026-10-02
- **Status when I stopped:** trim 1 done and merged; trim 2 (drill becomes fire playback, AR and practice log deleted)
  is next on `trim-2-drill-playback`.

## What happened

Anish went through `docs/demo/feature-inventory.md` and decided the cuts in chat (decisions 2026-10-02). This branch
does the parts that do not touch the drill:

- **Hazard Hunt deleted:** `Screens/HazardHuntView.swift`, `Editor/Core/HazardHuntPlan.swift`, its 20 tests. The five
  `EditAction` cases it used stay (the House object inspector uses them). No score deduction is lost: its checklist
  items are `scoring=False` and the inspector sets the same flags.
- **Re-scan review deleted:** `Screens/DiffReviewSheet.swift`, the room picker and recheck state in `HomeScreen`,
  `HomeIntent.recheckRoom`, "Re-check a room with the camera" in `TaskComponents`, and the diff request types in
  `APIClient+Convert.swift`. `TaskDestination`: only `practice.drill_recent` still opens the drill.
- **Accounts + cloud sync switched off, code kept:** `RootView` always shows the app and signs out a stored login once;
  no sync badge, no sync after a delete or on leaving House; Settings swaps the account section for a Privacy section
  ("What leaves this iPhone?"). `Auth/`, `Sync/`, `HomeDocumentSyncRepository` and the backend routes are untouched.
- **House's error banners fade** after 8 s and have a close button (`BackendFailureBanner(autoHides:)`), except a
  Settings fix (wrong or missing token), an offline or saved-routes notice, and under VoiceOver. Anish asked for this
  the same day. The dock gets a "Try loading routes again" button so a faded routes failure is still recoverable.
- **Deleting a home** no longer writes a sync tombstone, and the confirmation always says "this iPhone".

**Evidence (2026-10-02).**
- `swift test --package-path tools/editorcore`: 662 tests, 0 failures (682 before; the 20 Hazard Hunt tests went).
- `bash scripts/typecheck-ios.sh`: all four targets ok.
- Full suite: `xcresulttool` 1063 total / 1051 passed / 1 failed / 11 skipped (`.build-trim1/full.xcresult`). The one
  failure was `ProfilesEntryUITests.testDrillEmptyStateOpensProfilesAndReloads`, "Test crashed with signal term";
  re-run alone, 2/2 passed (`.build-trim1/drill1.xcresult`). Count check: 1083 − 20 Hazard Hunt − 1 net from
  `SignedOutPathUITests` (6 → 5) + 1 banner test = 1063.
- After the review fixes: full suite `xcresulttool` **1064 total / 1053 passed / 0 failed / 11 skipped**
  (`.build-trim1/full2.xcresult`; +1 is `TaskDestinationTests`). After the wording change, AccountPrivacyTests,
  BackendFailureTests, TaskDestinationTests, SignedOutPathUITests, HomeDeleteUITests: 39 / 39 passed
  (`.build-trim1/final.xcresult`); EditorCore 662, 0 failures.
- Simulator walk (iPhone 17 Pro): launch goes straight to Home with no gate and no sync badge; Settings opens on the
  Privacy section with the new summary; House's routes panel no longer shows the Hazard Hunt card. The banner fade
  was not watched on screen (it needs a failing server); its rule is pinned by `BackendFailureTests.bannerAutoHide`.

## Decisions / surprises

- Three rows in `docs/decisions.md` (the cuts, accounts switched off rather than deleted, banners fade).
- The playbook drops S11.24, S11.28, S11.30, S11.32 and S11.43; S11.31 and S11.40 lose their prereqs.
- `OfflineCapabilityNote` still promises an offline drill and practice log. Left for trim 2, which rewrites both.

**Review (swift-scenekit-reviewer): 3 Must fix, 5 Should fix, nits.** The Musts were all the fading banner: once hidden
it never came back (its reset lived inside the hidden view), and on Home's score card and a failed scan the banner held
the only Retry. Fixed by making fading opt-in (`autoHides`, House only), moving the reset, timer and Settings sheet to
the outer view, never fading an offline or saved-routes notice, and adding a dock Retry in House. Should-fixes taken:
the delete confirmation's account promise (now always "this iPhone") and the sync-era tombstone warning (tombstones
unwired), a `TaskDestination` test, stale comments. Not taken: re-adding "practice-drill history" to the unshown
`AccountPrivacy.notSynced` list (trim 2 deletes the drill log).

## Questions for teammates

- None. Anish chose every cut in chat on 2026-10-02 and approved the wording, asking that the Privacy paragraph not
  mention accounts; it now opens "Your homes are saved on this iPhone."


## Next steps

- Trim 2 on `trim-2-drill-playback`: the drill becomes a fire-only playback (0.25×–2×) with a per-person panel; AR
  walk and practice log + reminders deleted.
- Owner: delete `MONGODB_URI` on Render so the unused account routes answer 503 (BLOCKERS, "Demo trim 1 findings").
