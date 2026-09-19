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

For the session under test (S11.9 or S11.10 on the device, S11.8 on the simulator), read its acceptance criteria
in `docs/playbook/S11-<n>.md` and the device checklist in `docs/tracker/BLOCKERS.md` §2, and walk each item
on-screen. Never tick a box you did not observe. The golden path to walk as a judge would: onboarding, build or open
a home, routes render, switch profiles, drill, score, share snapshot.

Capture evidence (screenshot/recording via `xcrun simctl io … screenshot|recordVideo`) for the
handoff artifact.

## Reporting

For each criterion: OBSERVED (with the evidence file) → check the box; NOT OBSERVED → leave it
unchecked and say why. Update `docs/tracker/BLOCKERS.md` only for what you saw.
A criterion you couldn't reach (needs a real LiDAR phone, needs the API key) stays a documented
blocker, not a check.
