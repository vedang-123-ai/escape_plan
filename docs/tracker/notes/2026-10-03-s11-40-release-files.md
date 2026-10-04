# S11.40 — Release builds keep app data out of the Files app; raw scans are cleaned up

- **Who:** P1 (Anish, with Claude)
- **Date(s):** 2026-10-03
- **Status when I stopped:** DONE. AUD-008 fixed for Release builds. One device check owed (BLOCKERS §2, item 2.10).

## What happened

- `project.pbxproj`: `INFOPLIST_KEY_UIFileSharingEnabled` and `INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace`
  removed from the app's Release block only. `xcodebuild -target escape_plan -showBuildSettings -configuration
  Release | grep -i -E "FileSharing|OpeningDocumentsInPlace"` prints nothing; Debug prints both `= YES`.
- New `escape_plan/Capture/Export/ScanCleanup.swift`:
  - `ScanRetention.keepsRawScans()`. Debug: UserDefaults `debug.keepRawScans`, and absent means keep. Release: always false.
  - `ScanStore.discardImportedScan(at:keepRawScans:)`. Runs after the converted home is saved.
  - `ScanStore.sweepStaleScans(now:maxAge:keepRawScans:)`. Runs at launch, with a 7-day window, and reads each scan's
    age from the `yyyyMMdd-HHmmss` stamp in its directory name.
  - Both delete only real directories, directly inside `Scans/`, named `yyyyMMdd-HHmmss-<8 hex>`. Never a symlink,
    never the Scans folder, never anything outside it.
- `ScanStore` gained `rootOverride` (stands in for Documents), so tests run in a temp folder and never touch the
  simulator's real Documents. It is `nonisolated` now; `writeRawJSON` is `@MainActor`.
- Call sites: `HomeScreen.importScan` calls the discard as the last step of the success path, after
  `library.store.save` and after `lastScanArtifacts = nil`. `escape_planApp.init` has one line for the launch sweep,
  logged as an owned-files exception. Both run in detached utility tasks, off the main thread.
- `Capture/README.md` updated: file sharing is Debug-only, when scans are deleted, and how to try the Release
  behaviour in Debug.

**Evidence (2026-10-03, iPhone 17 Pro simulator, iOS 26.5, xcresulttool):**
- Full `-only-testing:escape_planTests`: **1022 passed, 0 failed, 3 skipped** (scratchpad `full1.xcresult`). The S11.33
  stamp was 1013 / 0 / 3, so +9: exactly the new `ScanCleanupTests`.
- In that bundle, `ScanExportTests` passed 7 of 7 and `ScanCleanupTests` passed 9 of 9.
- `scripts/typecheck-ios.sh`: ok on all four targets.
- The touched files also type-check clean with `-default-isolation MainActor`. The only warning is a pre-existing
  `try?` at `escape_planApp.swift:55`.
- `scripts/demo-preflight.py`: every check passes except `/explain` (the known missing server key).

**Mutation check.** Each mutation broke the code once and re-ran `ScanCleanupTests` on the simulator:

| Mutation | Caught by |
|---|---|
| M1 discard ignores the keep flag | testDiscardKeepsTheScanWhenRawScansAreKept |
| M2 discard skips the Scans/ fence | testDiscardRefusesAnythingThat…, testSymlinkNamedLikeAScanIsNeverDeleted |
| M3 sweep ignores the 7-day window | testSweepRemovesOnlyScanDirectoriesOlderThanTheWindow |
| M4 sweep treats a future stamp as stale | same |
| M5 sweep ignores the keep flag | testSweepKeepsEverythingWhenRawScansAreKept |
| M6 Debug default flips to delete | testDebugKeepsRawScansUnlessTheSwitchIsOff |
| M7 name pattern loosened (a-z, not hex) | testSweepRemovesOnly… |
| M8 sweep deletes plain files | testSweepRemovesOnly… |
| M9 sweep creates Scans/ | testSweepWithNoScansFolderDoesNotCreateOne |
| M10 stamp read as UTC, not local | testExportDateIsReadFromTheDirectoryNameStamp (+ sweep test) |
| M11 symlink check dropped, alone | **survived** |
| M12 discard stops resolving symlinks, alone | **survived** |
| M13 both symlink guards dropped | testSymlinkNamedLikeAScanIsNeverDeleted, testSweepRemovesOnly… |

M11 and M12 back each other up: a symlink's `isDirectory` is false, so either guard alone still rejects it. That is
deliberate defence in depth, and M13 proves the test catches the pair. The first mutation run (before the reviewer
fixes) was cut short when the disk filled (see Surprises); every mutation was re-run cleanly afterwards.

## Decisions / surprises

All decisions are in `docs/decisions.md` (2026-10-03, S11.40 rows, at the top):
- No move to Application Support. When it would become necessary is written there.
- No delete on Dismiss: the 7-day sweep collects a failed conversion's scan instead, because it is the only copy.
- Age comes from the name stamp, not the file creation date.
- Debug keeps scans via a UserDefaults key, with no Settings toggle (Settings is not owned here).
- One line in `escape_planApp.swift`.
- `writeRawJSON` is `@MainActor`.

Surprises:
- **The re-check flow is gone** (cut 2026-10-02), so the playbook's "after a re-check completes" half had nothing
  to hook. `recheckRoomID` in `RoomCaptureController.swift` is dead code, left for S11.47.
- **The disk filled up mid-session.** The Mac had about 0.5 GB free out of 460 GB. A mutation run died with "No space
  left on device", leaving `ScanCleanup.swift` mutated, and it was restored from a backup. I cleared Xcode's
  DerivedData cache (`~/Library/Developer/Xcode/DerivedData`, 1 GB, rebuilds itself automatically) to keep going.
  What fills the disk is outside this repo: about 21 GB in `~/Library/Caches` and 18 GB of simulators. **Anish: free
  some space before the next session.**
- **The reviewers:**
  - ecc:security-reviewer: no CRITICAL, HIGH or MEDIUM findings. Its two LOWs are recorded: the 7-day loss of a failed
    scan (a decision) and the time-zone skew (accepted, commented).
  - swift-scenekit-reviewer: one should-fix and four nits, all acted on:
    - The should-fix: a MainActor warning that `typecheck-ios.sh` cannot see.
    - The discard moved to the end of the success path.
    - The Debug test is `#if DEBUG`-safe.
    - A symlink test was added.
    - The time-zone comment was added.

## Questions for teammates

- None blocking. If anyone needs to keep raw scans on a physical device in Debug with the switch flipped, whoever owns
  `SettingsScreen.swift` adds a toggle (BLOCKERS, S11.40 findings).

## Next steps

- **The demo build is not affected.** Anish films from Xcode, which is a Debug build. File sharing stays on there and
  raw scans are kept. Only an Archive/TestFlight (Release) build hides Documents and deletes scans.
- On the device pass, do BLOCKERS §2 item 2.10 (scan → import → the scan folder is gone in Release; still there in
  Debug).
- The next Lane D session is S11.41 (home ids validated on every write). Its prereqs, S11.21 and S11.40, are now done.
