# S11.22 — Sync makes at most one conflict copy, and never while the home is open

- **Who:** P1 (Anish's session, agent-run)
- **Date(s):** 2026-10-02
- **Status when I stopped:** AUD-015 fixed and both S11.21 hand-offs done; EditorCore, typecheck and the simulator
  sync/repository tests green; full suite green.

## What happened

**Reproduced first (MISSION 1).** `SyncConflictCopyTests.testTwoSyncsWithTheHomeOpenMakeAtMostOneConflictCopy`: a
remote-wins conflict, `InMemoryHomeRepository.openHomeID` set to the home, two syncs.

- Before (origin/main `ba25d95`, sync code unchanged, test double only):
  `XCTAssertLessThanOrEqual failed: ("2") is greater than ("1") - each sync with the home open made another "(this device)" copy`
- After: passes (0 copies while open).
- It first PASSED on the unfixed code: the test double gave every copy the fixed id `preserved-<home_id>`, so the second
  copy replaced the first. The real store mints a new id per copy; the double now does too
  (`preserved-<home_id>-<n>`). That is why the audit's finding was never caught by the existing conflict test.

**The fix.**
1. `SyncHomeRepository.checkCanWritePulledHome(_:)`: `SyncManager` asks it before making any copy. The open-home and
   undecodable-document guards moved there from `HomeDocumentSyncRepository.writePulledHome` (which calls it). A refused
   pull is a per-home failure carrying the existing `SyncFailure.editorHasTheHomeOpen` message; nothing is copied and
   no conflict is reported. The badge already shows that message when it is the only failure ("Partly synced", "1 home
   didn't sync. This home is open for editing, so the version from your other device is waiting. It'll sync once you
   close the editor."), so no UI change was needed (nuance 6).
2. `SyncState.preservedCopies` (original `home_id` → copy id + fingerprint of the copied version), decoded with
   `decodeIfPresent`, **`currentVersion` stays 3** (nuance 1). `SyncManager.preserveOnce`: the same version is copied at
   most once; a recorded copy that is no longer on disk (the user deleted it, S11.21) is treated as discarded, so it is
   neither brought back nor made again and the pull lands (nuance 3). Cleared on `remember`, `markDeleted`/`apply`,
   `scoped`, `forgettingAccount`. The remaining path that makes a copy and then fails is a disk error after the check.
3. **Tombstones written mid-sync (S11.21 hand-off a).** `SyncManager` snapshots the sidecar's tombstones BEFORE it reads
   the library (`deletionsAtStart`); `adoptDeletionsWrittenSinceStart` runs before each action and inside `persist`, so a
   tombstone written since the start is kept and the action for that home is skipped. An ownerless mid-run tombstone
   takes this run's own claim (a home first uploaded by this run), restricted to the token subject.
4. **`homeWasDeletedLocally` throws `DeletionNotRemembered` (hand-off b).** I took the minimal `HomeLibrary` exception
   (`try`), so the failure lands in `library.loadError` while `delete` still returns true (the file is gone), and the
   one-line `HomeScreen` change shows `loadError` after a successful delete. Nothing left for another session.
5. S11.21's stopgap removed from `HomeScreen.swift` (`ManageHomesSheet.syncIsRunning` and "Your homes are syncing. Try
   again when the sync finishes."), only after the mid-run tombstone tests passed.

**Reviewer (swift-scenekit-reviewer): 1 Must fix, 2 Should fix, 3 nits; all reproduced by the agent and fixed.**
- Must: a delete during `GET /homes` came back (the snapshot was taken after the list, so the tombstone read as stale
  and the home was pushed). Fixed by snapshotting before `loadAllHomes()`.
- Should: a delete during a home's first upload wrote an ownerless tombstone, so the account copy was never deleted.
  Fixed by the subject-restricted owner fill.
- Should: a home re-deleted after this run cleared its old tombstone was not skipped. The skip now compares by value.
- Each fix is pinned by a test in `SyncMidRunDeletionTests` that fails with that fix reverted (mutation-checked:
  M1 → `testAHomeDeletedDuringTheListIsNotUploadedOrBroughtBack`, M2 →
  `testAHomeDeletedDuringItsFirstUploadIsStillRemovedFromTheAccount`, M3 →
  `testAHomeDeletedAgainAfterItsOldTombstoneWasClearedIsNotUploaded`). The during-the-list test hooks
  `InMemoryHomeRepository.afterLoadAllHomes`; a load-count hook let mutation 1 through.

**Evidence (2026-10-02).**
- `swift test --package-path tools/editorcore`: 682 tests, 0 failures (was 676 at the start of the session's tests).
- `bash scripts/typecheck-ios.sh`: all four targets ok.
- Simulator, `-only-testing` HomeDocumentSyncRepositoryTests, HomeLibraryEditorSeamTests, SyncConflictCopyTests,
  SyncMidRunDeletionTests, SyncStateStoreTests: `xcresulttool` 47 total / 47 passed / 0 failed (`.build-s1122/r1.xcresult`,
  before the review fixes); after them, covered by the full suite below.
- Full suite: `xcresulttool` 1083 total / 1072 passed / 0 failed / 11 skipped (`.build-s1122/full.xcresult`, run after the review fixes; GestureFrameCostUITests passed). S11.21's stamp was 1065 / 1054 / 0 / 11; the 18 new tests account for the difference.

## Decisions / surprises

- No `SyncState` version bump (decisions.md 2026-10-02). A build from before S11.22 ignores the new key.
- A local home edited after its copy was made gets a second copy: that version is new work. Reachable only after a disk
  write failure.
- Owned-files exceptions: `Persistence/HomeLibrary.swift` (one `try` + doc), `Screens/HomeScreen.swift` (stopgap removal
  + showing `loadError` after a successful delete). `SyncDeletionTests.swift` was not touched; the mid-run tests are in
  `SyncManagerTests.swift`.
- No simulator walk: a sync needs a signed-in account and the live backend, and the live server was struggling today
  (end-of-project-fixes.md §1). Not in ACCEPTANCE.

## Questions for teammates

- None. Anish approved all three user-facing changes in chat on 2026-10-02 before the merge: the delete-failure message,
  the stopgap's removal, and the existing "open for editing" message now appearing where copies used to pile up.

## Next steps

- Anish then cut accounts + cloud sync from the demo app (decisions 2026-10-02, branch `trim-1-demo-cuts`): this code
  stays but is switched off. S11.23 (score race) follows the trim in lane D.
