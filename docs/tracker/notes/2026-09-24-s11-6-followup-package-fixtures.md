# S11.6 follow-up — package tests can load the app fixtures

- **Who:** agent run (orchestrated), branch `s11-6-followup-package-fixtures`
- **Date(s):** 2026-09-24
- **Status when I stopped:** fixtures load in `swift test`; the two S11.6 fixture tests run in the package; the two
  SceneKit fixture users stay gated because they genuinely need SceneKit.

## What happened

- `FixtureLoader` resolved its bundle with `Bundle(for:)`. In a SwiftPM test run that is the xctest bundle, so no
  package test had ever loaded a fixture.
- `tools/editorcore/Sources/EditorCore/Fixtures` is a new symlink to `escape_plan/Fixtures`, declared as
  `resources: [.process("Fixtures")]`. `.process` flattens the JSON into the bundle root, the same place the app's
  synchronized group puts it, so `url(forResource:withExtension:)` is the same call in both runners.
- `FixtureLoader.bundle` is `Bundle.module` under `#if SWIFT_PACKAGE`. The `#else` branch is the original code,
  unchanged. Still Foundation-only.
- Un-gated in the package: `ResponderSnapshotTests.testHazardSummaryMatchesEngineChecklistOnStockFixtures` and
  `testTwostoryFixtureAnonymity`. The PDF half of the second one is still `#if !SWIFT_PACKAGE`, because it needs
  `UIGraphicsPDFRenderer`.
- New shared `FixtureLoaderTests`: every `HomeFixture` loads and decodes, and the loader's bytes are compared with
  `schema/fixtures` read off the source tree. That second check is the known-answer part.
- **Red-before:** with the loader switch reverted and the resource rule kept, the four fixture tests fail in the
  package (7 assertion failures). With the switch restored they pass.
- **EditorCore: 598 → 602, 0 failures** (`swift test --package-path tools/editorcore`, 2026-09-24).
- `scripts/typecheck-ios.sh`: ok on all four targets (170 app files, 83 test files). Type-check only.
- App unit tests, iPhone 17 simulator (`-only-testing:escape_planTests`, `CODE_SIGNING_ALLOWED=NO`), two runs,
  identical: **943 passed / 4 failed / 0 skipped** (`s11-6f-run1.xcresult`, `s11-6f-run2.xcresult`, counts from
  `xcresulttool`). All 7 tests this branch touches pass. The 4 failures are in files it did not touch: 1 stale
  apartment track count in `EvacuationMockTimelineTests` and 3 `KeychainTokenStoreTests` `-34018`
  (missing entitlement). Both are logged in BLOCKERS under S11.6 follow-up.

## Decisions / surprises

- **The two "pre-existing FixtureLoader users" cannot be un-gated.** `EvacuationSceneLayerTests` and
  `EvacuationRenderingTests` build `DollhouseSceneBuilder`, `HazardLayer` and `PeopleLayer`, which are
  SceneKit/UIKit and live in `Renderer/`, not in the package. The gate is correct, not a fixture problem.
- The package resource is `escape_plan/Fixtures` (the app's bundled copies), not `schema/fixtures`. That keeps
  the package loading the same bytes as the app, and it avoids pulling `schema/fixtures/invalid/` and `scans/`
  into the bundle. `FixtureLoaderTests` fails if the copies drift from `schema/fixtures`. See `decisions.md`.
- No product defect surfaced. Both un-gated tests passed on their first package run.

## Questions for teammates

- ~13 app-target test files in `escape_planTests/` (outside `EditorCore/`) use `FixtureLoader`. Some may be
  Foundation-only now that fixtures load in the package (for example `HomeModelRoundTripTests`), but each needs
  its dependencies checked against what is symlinked. Not done here: they are outside this session's owned files.

## Next steps

- New package tests can call `FixtureLoader.load(.twostory)` directly. Don't gate them for fixture reasons any more.
