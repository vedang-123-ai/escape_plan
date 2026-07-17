#!/bin/bash
# S1.3 acceptance run: boot a simulator, run the renderer tests, and screenshot every fixture.
#
# Waits for `xcodebuild -downloadPlatform iOS` to finish first — this machine had no iOS
# simulator runtime installed, so none of this can run until that 8.5 GB download lands.
# Screenshots land in scripts/../artifacts/s13/ for human review; the on-device 60fps check
# and the 30-sec recordings are NOT covered here (they need a physical phone).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/artifacts/s13"
BUNDLE_ID="cac.Escape-Plan"
mkdir -p "$OUT"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# 1. Wait for the platform download to finish.
while pgrep -f "downloadPlatform" > /dev/null; do sleep 60; done
log "download process gone; checking for a runtime"

RUNTIME=$(xcrun simctl list runtimes 2>/dev/null | grep -i "^iOS" | head -1 | sed -E 's/.*(com\.apple\.CoreSimulator\.SimRuntime\.[^ ]+).*/\1/')
if [ -z "$RUNTIME" ]; then
    log "FAIL: no iOS runtime installed after download. Acceptance cannot run."
    exit 1
fi
log "runtime: $RUNTIME"

DEVTYPE=$(xcrun simctl list devicetypes 2>/dev/null | grep -oE "com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-1[6-9][^)]*" | head -1)
[ -z "$DEVTYPE" ] && DEVTYPE=$(xcrun simctl list devicetypes 2>/dev/null | grep -oE "com\.apple\.CoreSimulator\.SimDeviceType\.iPhone[^)]*" | head -1)
log "device type: $DEVTYPE"

UDID=$(xcrun simctl create "s13-acceptance" "$DEVTYPE" "$RUNTIME" 2>&1 | tail -1)
log "device: $UDID"
xcrun simctl boot "$UDID" 2>&1 | tail -1
xcrun simctl bootstatus "$UDID" -b 2>&1 | tail -1

# 2. Run the renderer test suite.
log "running tests"
xcodebuild test -project "$REPO/escape_plan.xcodeproj" -scheme escape_plan \
    -destination "id=$UDID" -derivedDataPath "$REPO/.build-s13" \
    CODE_SIGNING_ALLOWED=NO > "$OUT/test-run.log" 2>&1
TEST_RC=$?
log "tests exit=$TEST_RC (full log: artifacts/s13/test-run.log)"
grep -E "Test Suite '(All tests|escape_planTests)'|Executed .* tests|error:|\*\* TEST" "$OUT/test-run.log" | tail -20

# 3. Screenshot each fixture. Launch args drive the demo controls, so no tapping is needed.
APP=$(find "$REPO/.build-s13/Build/Products" -name "escape_plan.app" -maxdepth 3 | head -1)
if [ -z "$APP" ]; then
    log "FAIL: no built .app found; skipping screenshots"
    exit 1
fi
log "installing $APP"
xcrun simctl install "$UDID" "$APP" 2>&1 | tail -1

shoot() {  # shoot <name> <launch args...>
    local name="$1"; shift
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1
    xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" > /dev/null 2>&1
    sleep 6   # let SceneKit render the first frames
    xcrun simctl io "$UDID" screenshot "$OUT/$name.png" > /dev/null 2>&1
    log "shot $name.png"
}

shoot bungalow            -fixture bungalow
shoot apartment           -fixture apartment
shoot twostory            -fixture twostory
shoot twostory-exploded   -fixture twostory -explode 1.0
shoot twostory-floor-hidden -fixture twostory -hideFloor f2

log "done. Screenshots in artifacts/s13/ — these still need a human eye for 'renders correctly and legibly'."
log "STILL BLOCKED-ON-HUMAN: on-device 60fps check + 30-sec recording per fixture."
