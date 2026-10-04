# S11.41 — Home ids are validated on every write, and the library never lists a home it cannot open

- **Who:** agent session for Anish
- **Date(s):** 2026-10-04
- **Status when I stopped:** DONE. AUD-012 fixed; merged to `main`.

## What happened

- **Disk first.** `df` showed 1.9 GB free (under the 2 GB stop line). About 14 GB of it was stale, gitignored Xcode
  DerivedData folders from earlier sessions (`.build-lane-*`, `.build-orch-*`, `.build-s11xx` and so on, each holding
  `Build/` or `ModuleCache.noindex/`). I deleted those, kept `.build-merge` (the gate's) and every log and `.xcresult`.
  14 GB free after. They regenerate on the next build that uses them.
- **Validator:** `escape_plan/Sync/HomeID.swift` (Foundation only, symlinked into EditorCore). `HomeID.isValid` is ASCII
  `[A-Za-z0-9_-]{1,64}`; `HomeID.validate` throws `InvalidHomeID(homeID:)`. No `/`, no `.`, so no separators and no
  `.`/`..` segments. Its error type lives there too, because `PersistenceError.swift` is not owned.
- **Every id in use today passes** (grepped app code, `escape_planTests`, `tools/editorcore/Tests`, fixtures):
  lowercase UUIDs (fixtures, `FixtureSeeder`, `duplicate`, `importDocument`, `HomeDocument.reidentified` default);
  UPPER-case UUIDs (`HouseScreen.blankHome`, `HomeModelStore.newHome`); `TEST-DEMO-HOME-1234` (DEBUG UI-test seed);
  `9a5e6d34-2c3f-4a1b-8d70-empty-123` (twostory-empty fixture, not a UUID); `preserved-<uuid>-N` (sync test double,
  48 chars); test ids `home-1`, `existing-home`, `seed-test`, `home-alice`, `h_bounds`, `h`, `brand-new` and friends.
  `"a.b"` and `"../../x/y"` in `OfflineIntegrityTests` are route-cache keys, not store ids (that cache uses `fileSafe`).
- **`HomeDocumentStore`:** every read, write and delete goes through a private `checkedURL(for:)` that validates first:
  `load`, `save`, `delete`, `duplicate` (via load + its fresh id), `export` (via load), `importDocument`; `exists`
  returns false for an invalid id. `url(for:)` stays non-throwing (an unowned test, `HomeLibraryEditorSeamTests`,
  calls it) but percent-escapes an invalid id, so even that path is one file name inside the directory.
- **`list()` lists by file name**, which is what `load` opens. A file whose name is not a valid id, or whose embedded
  `home_id` differs from its name, is logged (`os.Logger`, category `HomeDocumentStore`) and skipped, and left on disk.
  The comparison ignores letter case (security-review finding, see below).
- **`HomeDocumentSyncRepository.checkCanWritePulledHome`** refuses an invalid pulled id first, with
  `HomeDocumentSyncRepository.pulledHomeIDRefused` (kind `.localWriteBlocked`, not retryable). `SyncManager` already
  turns a thrown `SyncFailure` into a per-home failure, and it asks this before any conflict copy is made, so a hostile
  id never produces a copy either. `store.save` checks again. Sync has been switched off since 2026-10-02 (no screen
  reaches it), so this path is not reachable in the app today; there is no live exploit claim here.
- **Debug builds still expose Documents in Files** (S11.40 changed Release only), so the renamed or hand-edited file case
  is still real where Anish runs the app.

## Evidence (all run by me, 2026-10-04)

- `swift test --package-path tools/editorcore`: **646 passed, 0 failed** (642 at the S11.40 stamp + 4 new `HomeIDTests`).
- `bash scripts/typecheck-ios.sh`: ok on all four targets. Also type-checked the app with `-default-isolation MainActor`:
  only the three pre-existing warnings (`escape_planApp.swift:55` `try?`, `HouseScreen.swift:1916`,
  `PlaybackCameraController.swift:324`), none in a touched file.
- Simulator, iPhone 17 Pro, iOS 26.5, `-only-testing:escape_planTests`, read with `xcresulttool` (scratchpad
  `full1.xcresult`): **1036 passed, 0 failed, 3 skipped**, against the S11.40 stamp of 1022 / 0 / 3: +14, exactly the
  new tests (8 in `PersistenceTests`, 2 in `HomeDocumentSyncRepositoryTests`, 4 `HomeIDTests` in the app build).
  First run, no flake re-run needed.
- **Mutation checks, every new test failed at least once against broken code:**
  - EditorCore: allow `.` and `/` → `testPathTraversalAndSeparatorsAreRejected` fails; length cap 65 →
    `testSixtyFourCharactersIsTheLongestAccepted` fails; drop `A-Z` → `testEveryIDFormatTheAppProducesIsValid` fails
    (UPPER UUIDs, `TEST-DEMO-HOME-1234`).
  - Simulator batch A (`mutA.xcresult`, 5 failed / 39 passed): `checkedURL` stops validating → the save, delete and
    load/exists traversal tests fail; `list()` compares case-sensitively → the case test fails; the pulled-id guard
    removed → `testAPulledHomeWithATraversalIDIsAPerHomeFailureAndWritesNothing` fails.
  - Simulator batch B (`mutB.xcresult`): `list()` drops the name/id check → `testAFileWhoseNameAndIDDisagreeIsNotListed`;
    drops the name-validity check → `testAFileWhoseNameIsNotAValidIDIsNotListed`; import reuses the file's id →
    `testImportOfAFileWithATraversalIDStoresItUnderAFreshValidID` (and the old `testImportedExportGetsAFreshID…`);
    `url(for:)` stops escaping → `testLoadAndExistsRefuseATraversalIDEvenWhenTheFileIsThere`.
  - `testEveryCurrentIDFormatSavesListsAndLoads` and `testAPulledHomeWithAnUpperCaseUUIDIsStillWritten` guard against
    the rule being too narrow; the EditorCore drop-`A-Z` mutation is their failing case at the rule level.
  - All mutations reverted from backups; `diff` confirmed.
- **ecc:security-reviewer:** no critical or high findings. Acted on: (1, medium) case-insensitive volumes: a pull of
  `ABC…` over `abc….homeplan.json` could leave the old name on the new contents and the strict check would hide the
  home. Now case-insensitive, with `testAFileWhoseNameDiffersOnlyInCaseIsListedAndOpens`. (2, medium) legacy ids that
  now fail: every producer was enumerated above and passes; a skipped file is logged and kept, not deleted. (3, low)
  `url(for:)` could be made private: it cannot escape now and an unowned test uses it, so it stays (decisions.md).
  (4) symlink/TOCTOU: no new exposure. (5) logging: only valid ids are logged. Other id-to-path use: only
  `ScoreCache.swift` (BLOCKERS line for its owner).
- **swift-scenekit-reviewer:** no must-fix. Isolation checked: `HomeID` is explicitly `nonisolated`; the store's
  static `Logger`/`CharacterSet` are Sendable; `pulledHomeIDRefused` is read only by a `@MainActor` test. Its own
  type-check run collided with my edits ("modified during the build"); I re-ran `typecheck-ios.sh` after the last edit:
  ok on all four targets. Should-fix items went to BLOCKERS (schema says `format: uuid`; `BuildFromPlanView` error
  text for an invalid draft id). Nit (log level `.error`) left as is: a hidden home is worth an error line.

## Decisions / surprises

- List-and-skip, not repair (decisions.md 2026-10-04).
- A mistake of mine: I applied a mutation to `HomeID.swift` for a moment while the full simulator run was compiling, and
  reverted it in the same command. The run showed it was not compiled in (the app's `HomeIDTests` passed, and the
  mutated rule fails them). After that, no source was touched while a build ran.

## Questions for teammates

- None blocking. Whoever owns `ScoreCache.swift`: same bug class, see BLOCKERS.

## Next steps

- Lane D continues in the README order; S11.42 is next unless its owner answers in BLOCKERS §1 are still missing.
