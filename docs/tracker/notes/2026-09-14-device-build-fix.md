# Device build fix: single-room rescan did not compile for iPhone

- **Who:** Claude session with Yuki
- **Date(s):** 2026-09-14
- **Status when I stopped:** device build green (`generic/platform=iOS`, signed, team 94AD5J95YF);
  install to Yuki's iPhone 13 Pro blocked on Developer Mode being off on the phone.

## What happened
- Setting up a device retest of scan-to-save. `xcodebuild` for a real iPhone failed:
  `RoomCaptureController.swift:118: cannot assign to property: 'configuration' is a 'let' constant`.
- Cause: `startSingleRoomScan(roomID:)` (added in `4eb4041`, S7.8/S7.9) declared
  `RoomCaptureSession.Configuration` with `let` and then set `isCoachingEnabled`. It is a struct.
  The existing `startScanningRoom()` right above it uses `var`. Fixed to `var`.
- **Why nobody saw it:** all RoomPlan capture code sits behind
  `#if canImport(RoomPlan) && !targetEnvironment(simulator)`, so every simulator build and the
  whole unit suite compile the `#else` branch. Since 9/10, `main` could not produce a device build.
- Preflight (`scripts/demo-preflight.py`): backend PASS, deployed schema 2.1 PASS, only failure is
  the missing bearer token (already in BLOCKERS §1). That is also the most likely cause of the
  2026-09-08 report "scan builds but never saves": save requires a successful `/convert`, and an
  empty token gets 401.

## Decisions / surprises
- The simulator gate means device-only code has no compile coverage at all. A
  `generic/platform=iOS` build belongs in `/verify`; filed in TODO.

## Next steps
- Owner: enable Developer Mode on the phone, provide the bearer token (Settings → Access token in
  the app, or `BackendConfig.local.json` on the build Mac), then install and retest scan → save.
