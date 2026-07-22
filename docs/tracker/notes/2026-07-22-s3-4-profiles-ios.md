# S3.4 — Family profiles iOS CRUD (iOS half, minus live re-fetch)

- **Who:** P3
- **Date(s):** 2026-07-22
- **Status when I stopped:** Profile CRUD UI done and autosaving through the S2.4 store;
  live `/routes` re-fetch on profile switch deliberately NOT built (belongs to S2.3 —
  `TODO(integration)` in `ProfilesScreen.swift`).

## What happened

- New `EditAction` cases (append-only): `addProfile` / `updateProfile` / `deleteProfile`,
  with `undoLabel`s, reduced in `HomeModelStore` via a `profileIndex` helper. No new
  validation code — the existing post-reduce `EditorValidation.validate` already enforces
  every profile invariant (unique/non-EXTERIOR/non-empty ids, non-empty name, dangling
  `bedroom_room_id`, duplicate tags).
- New `Screens/ProfilesScreen.swift`: per-home list (name, tag chips, bedroom), empty state,
  add via toolbar `+`, edit via row tap, delete via swipe + confirmation dialog. Loads the
  home through `HomeDocumentStore`, mutates through `HomeModelStore.dispatch`, autosaves on
  every commit — same pattern as `EditorScreen`. Rejections surface in an alert.
- New `Screens/ProfileEditorView.swift`: create/edit sheet — name field (Save disabled when
  blank), one toggle per `ProfileTag` (`Set` makes duplicate tags impossible), bedroom
  picker over ALL rooms grouped by floor with bedroom-typed rooms hinted (`bed.double`).
- `HomeScreen`: leading-swipe "Profiles" + context-menu entry per home row →
  `ProfilesScreen` (merged alongside the S3.5 lane's "Score" entries landing concurrently).
- New `escape_planTests/EditorCore/ProfileActionsTests.swift` — 11 tests through
  `dispatch`: CRUD happy paths, rejection of empty name / dangling bedroom / duplicate id /
  EXTERIOR id / unknown profileId, rejected actions leave the model bit-for-bit unchanged,
  commit hook fires, and deleting a profile unblocks S2.1's "sleeps here" room-delete refusal.

## Verification

- `swift test --package-path tools/editorcore` — 100/100 pass (11 new).
- `xcodebuild -project escape_plan.xcodeproj -scheme escape_plan -destination
  'generic/platform=iOS Simulator' build` — BUILD SUCCEEDED.
- Not verified here (no simulator runtime on this machine): the manual flow — add Grandpa,
  relaunch, persists; room delete refused until profile deleted.

## Decisions / surprises

- **Profiles are edited per-home from the Homes list, not Settings** — they live inside the
  HomeModel document; Settings is app-global. (→ decisions.md)
- Bedroom picker shows all rooms (bedroom-typed suggested) instead of filtering to
  `.bedroom`, so homes without a typed bedroom aren't dead-ended. (→ decisions.md)
- `ProfileTag.displayName` lives in `ProfileEditorView.swift`, not `Enums.swift` — Models/
  stays a pure schema mirror.
- Surprise: another lane rewrote `HomeScreen` mid-session (S3.5 score entry points); the
  merge was clean — one shared leading swipe-action group and one shared context menu.

## Questions for teammates

- @P2: when S2.3 lands, the Plan screen needs the profile selector + `/routes profile_id`
  re-fetch (see TODO(integration) in ProfilesScreen.swift). Want the selector UI from me, or
  will you wire it with the route overlay?

## Next steps

- S2.3: route overlay + profile selector on PlanScreen, then live Grandpa-vs-Maya switch =
  the remaining S3.4 acceptance boxes (plus the handoff recording).
- On a machine with a simulator: run the manual persistence flow above.
