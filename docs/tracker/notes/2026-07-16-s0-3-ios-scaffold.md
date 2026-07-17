# S0.3 — iOS app scaffold + model layer

- **Who:** P3 (Claude Code), at the user's direction (playbook lists P2 as owner — user asked
  P3 to run this session directly)
- **Date(s):** 2026-07-16
- **Status when I stopped:** Code complete, tests green, uncommitted on `s03-ios-scaffold`
  worktree. "Runs on a real device" acceptance box intentionally left open for a human.

## What happened

Replaced the stock Xcode "App with Core Data" template wholesale, per the S0.1 flag and the
playbook default (local JSON persistence, not Core Data):

- Deleted `Persistence.swift` and `escape_plan.xcdatamodeld`.
- `Models/` — Codable structs mirroring `schema/homemodel.schema.json` v1.0 field-for-field
  (`Geometry.swift`: `Point`/`Polygon`; `Enums.swift`; `HomeModel.swift`: `Room`, `Opening`,
  `Floor`, `Stairs`, `Profile`, `Meta`, `HomeModel`; `FixtureLoader.swift`).
- `escape_plan/Fixtures/` — bundled copies of the 3 project fixtures (bungalow, apartment,
  twostory).
- `Screens/` — `TabView` shell: Home (real content), Editor/Plan/Assistant/Settings
  (placeholders with `ContentUnavailableView`). Home loads `twostory.json` and lists room
  names grouped per floor.
- `Networking/APIClient.swift` — configurable base URL + bearer token via `UserDefaults`,
  edited from the Settings tab; `/health` check wired and used from Settings.
- `escape_planTests/HomeModelRoundTripTests.swift` — decode → encode → decode →
  `Equatable`-compare round trip on all 3 fixtures, plus structural/Point/Stairs-`from` spot
  checks.

Project stayed at the repo root (not `ios/`) — confirmed rather than revisited; moving it now
would still break the open Xcode session for no benefit before Phase 2.

Xcode project uses the modern `PBXFileSystemSynchronizedRootGroup` format (Xcode 16+), so
adding new files under `escape_plan/` and `escape_planTests/` required zero `.pbxproj`
surgery — Xcode auto-discovers them.

Build + test: `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17' build`
→ `** BUILD SUCCEEDED **`. Full `test` action reports `** TEST FAILED **`, but only because
of the *stock*, unmodified `escape_planUITests.testLaunchPerformance()` timing out (~525s,
`FBSOpenApplicationServiceErrorDomain … RequestDenied`) — a simulator app-foregrounding
limitation of this sandboxed dev environment, not a code regression. Scoped run
(`-only-testing:escape_planTests`) reports `** TEST SUCCEEDED **`, all 4 tests passing.

## Decisions / surprises

All promoted to `docs/decisions.md` (2026-07-16 rows) — summary:

- Swift field names mirror the JSON schema exactly (`room_id`, `width_m`, etc., not
  camelCase); `Stairs.from`/`.to` need no `CodingKeys` alias since `from` isn't reserved in
  Swift (unlike Python's `from_`).
- `Point` is a custom `Codable` type serializing as a bare `[x, y]` array, not `{x, y}`.
- Schema fields with `"default": []` get hand-written `decodeIfPresent(...) ?? []` so an
  omitted key still decodes — defensive beyond what the current fixtures need.
- Fixtures are bundled as real file copies (not a symlink into `schema/fixtures/`) — **known
  drift risk**, see Questions below.
- Round-trip test compares decoded `Equatable` structs, not literal JSON bytes (JSONEncoder
  doesn't guarantee matching whitespace/key order).

## Questions for teammates

- @P1 / @P2 — `escape_plan/Fixtures/*.json` are copies of `schema/fixtures/*.json`, not a
  symlink or build-time sync. If you change a fixture, the iOS copy goes stale silently. Worth
  a Run Script build phase to copy at build time, or accepting the drift risk until S2.4
  persistence changes how the app loads homes anyway? Didn't attempt a `.pbxproj` build-phase
  edit this session to keep risk low.
- @P2 — you're the playbook owner of S0.3; I ran it because the user asked for it directly.
  Please review the `Models/` field-naming choice (exact snake_case mirror vs. Swift
  convention + `CodingKeys`) before building the SceneKit renderer/editor on top of it in
  S1.3 — easy to change now, expensive after wall/opening rendering code depends on the names.

## Next steps

1. Human: build + run on a real device via Xcode (steps given directly to the user in this
   session — see chat), to close the last acceptance box.
2. Commit this worktree's changes on `s03-ios-scaffold` (not `main`).
3. S1.3 (3D dollhouse renderer, P2) and S1.4 (RoomPlan capture, P2) are now unblocked.
