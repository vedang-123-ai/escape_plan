# S2.4 — Persistence & documents

- **Who:** P3 (Claude Code)
- **Date(s):** 2026-07-16
- **Status when I stopped:** Module complete and acceptance-verified on macOS; **not yet wired
  to S2.1's `HomeModelStore`** (deliberate — see Integration points) and **not yet run on a
  simulator/device** (no iOS runtime installed on this machine). Branch `s24-persistence`.

## What happened

Built `escape_plan/Persistence/` as a self-contained module — no dependency on S2.1's
`HomeModel`, which was still being written in a parallel terminal against the same checkout.

- `HomeDocumentStore` — FileManager store at `<Documents>/Homes/<home_id>.homeplan.json`.
  save / load / list / delete / duplicate / export / import, atomic writes.
- `JSONValue` + `HomeDocument` — a saved home is stored as *exactly* the HomeModel JSON, no
  envelope. So the export is the stored file, and "the export validates against the schema"
  is structural rather than something a second serializer has to keep true.
- `SchemaMigrator` — `schema_version` checked on load. Newer than the build → refuse
  gracefully (file untouched, other homes still list). Older → migration registry (empty;
  1.0 is the first version — the stub is shape-only).
- `DeviceIdentity` — random UUID in UserDefaults. Not `identifierForVendor`. No accounts.
- `HomeLibrary` (ObservableObject) + `HomeListView` — minimal, unstyled; P2 restyles.

17 tests, all passing, driven by the real `schema/fixtures/` (bungalow/apartment/twostory)
read off the host filesystem — no bundled fixture copies to drift.

## Acceptance

Run `./scripts/verify_export_validates.sh` — tests + schema validation of a real export.

| Criterion | Status |
|---|---|
| Kill and relaunch → everything persists | Automated proxy passes (fresh store instance over the same dir reloads the document byte-for-byte, all 3 fixtures). **The literal on-device check is in the manual checklist** and needs S2.1 wiring + a device. |
| Two saved homes coexist | PASS — both list with correct name/floors/rooms; deleting one leaves the other loadable. |
| Export validates against the schema | PASS — `python3 -m app.validate` says OK on the exported `Bungalow.json`. |
| Duplicate gets a fresh id | PASS — new UUID in the summary *and* in the copy's body; original survives the copy's deletion. |
| Builds via xcodebuild CLI | PASS for compile: `xcodebuild -project escape_plan.xcodeproj -target escape_plan -sdk iphonesimulator26.5 CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED. **`xcodebuild test` is blocked** (below). |

## Decisions / surprises

Full rationale in `docs/decisions.md` (6 rows + the manual test checklist appended per the
playbook). The two that matter to other people:

- **Blocker — no iOS simulator runtime is installed on this Mac.** `xcrun simctl list devices`
  is empty and any destination fails with "iOS 26.5 is not installed. Please download and
  install the platform from Xcode ▸ Settings ▸ Components." So `xcodebuild test` cannot run
  here at all, for any lane. I verified the tests by building the module as a throwaway macOS
  SwiftPM package (`scripts/verify_export_validates.sh`) — it's Foundation/Combine/SwiftUI
  only, so it runs unmodified. **Someone should install a runtime and re-run
  `xcodebuild test`**; that's the check that counts, and the same test file runs there
  unchanged. Note the macOS harness did *miss* one real error (a missing `import Combine`)
  that the iOS SDK compile caught — the harness is a stand-in, not a replacement.
- **Storing the raw HomeModel JSON rather than a decoded struct** is what let this session
  finish without S2.1's `HomeModel`, and it also means a document written by a future build
  round-trips instead of quietly losing fields we don't model yet.

Surprise worth flagging: the S2.1 lane is writing into **this same working directory**
(`escape_plan/Models/`, `escape_plan/Editor/`, `tools/`), not a separate worktree. Nothing
broke, but two lanes sharing one checkout means an `xcodebuild` of the app target compiles
both lanes' in-flight code. Worth fixing before the next parallel session.

## Integration points

Everything below is marked `TODO(integration)` in the source.

- **S2.1 `HomeModelStore` → `HomeDocumentStore`.** The seam is two generic methods that
  already exist and are tested against a stub Codable model:
  `store.save(model: homeModel)` on autosave, `store.load(homeID:as: HomeModel.self)` on open.
  Nothing in persistence needs to change when `HomeModel` lands — it never names the type.
- **`HomeModelPersisting` protocol** (`HomeLibrary.swift`): `HomeModelStore` should conform
  and be set as `HomeLibrary.editor`, so a home deleted from the list closes the editor and
  clears its undo history. Currently unset → deleting the open home leaves the editor holding
  a home that no longer exists on disk.
- **`HomeListView`**: row tap is a no-op; S2.2 should open the editor on `home.id`.
- **`SchemaMigrator.currentVersion`** is asserted equal to the schema's `schema_version` const
  by a test — a schema bump will fail that test until a migration is registered. Intentional.
- The app still boots the stock Core Data template (`escape_plan/Persistence.swift`,
  `ContentView.swift`). Nothing wires `HomeListView` in yet — that's S2.2/S0.3 cleanup, and I
  left it alone rather than fight the other lane over the app entry point.

## Questions for teammates

- **@P2** — is any Mac in the team set up with an iOS simulator runtime? If not, that blocks
  every iOS acceptance criterion from here on, not just mine.
- **@P2** — do you want the home list to stay in `Persistence/` or move to the UI layer when
  you restyle it? It only needs `HomeLibrary`.
- **@P1** — persistence never sends the device id anywhere; S3.x owns that. Confirm the
  backend expects `escape_plan.device_id`'s random UUID and nothing else identifying.

## Next steps

1. Install an iOS simulator runtime, then run
   `xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan -destination 'platform=iOS Simulator,name=iPhone 16'`
   and confirm the 17 tests pass in the app target too.
2. Merge S2.1, then do the `HomeModelStore` ↔ `HomeDocumentStore` hookup (the four
   `TODO(integration)` sites above).
3. Walk the manual checklist in `docs/decisions.md` on a real device once the editor saves.
