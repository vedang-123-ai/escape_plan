---
name: device-acceptance
description: Drive an on-simulator/on-device acceptance pass for iOS sessions — boot, install, walk the click-by-click criteria, and only check a box for something actually observed. Use when the user wants to verify iOS acceptance criteria, "check it on the simulator/phone", or clear the device-blocked boxes on the tracker.
---

# device-acceptance

Many acceptance criteria are device-only: they require watching the app behave, not just passing a
unit test. This skill runs that pass honestly — the cardinal rule is **never check a box for
something you did not actually watch happen.**

## Setup

```bash
xcrun simctl list devices available | grep iPhone         # pick a booted-able device
xcodebuild build -project escape_plan.xcodeproj -scheme escape_plan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build-merge CODE_SIGNING_ALLOWED=NO
# then boot + install + launch:
xcrun simctl boot 'iPhone 17 Pro'; xcrun simctl bootstatus 'iPhone 17 Pro' -b
APP=$(find .build-merge/Build/Products -name 'escape_plan.app' -maxdepth 3 | head -1)
xcrun simctl install 'iPhone 17 Pro' "$APP"
xcrun simctl launch 'iPhone 17 Pro' cac.Escape-Plan
```
`scripts/s13-acceptance.sh` automates boot + test + per-fixture screenshots for the renderer.

## The pass

For the session under test, read its acceptance criteria in `docs/tracker/checklist.md` and walk
each on-screen. Current device-blocked items across the merged lanes:

- **S2.2 editor:** drag an opening along a wall; place stairs between two floors; undo/redo a drag.
- **S2.3 routes:** primary pulse + secondary dashed render; camera tour is smooth; warning badges
  appear on the apartment fixture (single-exit) — NOT the twostory kids' room (documented gap).
- **S3.4 profiles:** add Grandpa (mobility_limited) + Maya (child); Plan tab "Who" picker switches
  the rendered route / jumps to the profile's bedroom. This is the demo money shot.
- **S3.5 score:** breakdown screen is legible; toggling a checklist item updates the score.
- **S3.3 chat:** blocked on `ANTHROPIC_API_KEY` on Render, not on a device — a graceful error
  banner (not a spinner/crash) IS device-verifiable now; the cited Q&A is not, until the key lands.

Capture evidence (screenshot/recording via `xcrun simctl io … screenshot|recordVideo`) for the
handoff artifact.

## Reporting

For each criterion: OBSERVED (with the evidence file) → check the box; NOT OBSERVED → leave it
unchecked and say why. Update `docs/tracker/checklist.md` and `board.md` only for what you saw.
A criterion you couldn't reach (needs a real LiDAR phone, needs the API key) stays a documented
blocker, not a check.
