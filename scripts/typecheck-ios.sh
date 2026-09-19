#!/usr/bin/env bash
#
# typecheck-ios.sh — compile-check the whole iOS project without a simulator.
#
# Why this exists: the machine this project is usually worked on cannot run the iOS simulator,
# so `xcodebuild test` is unavailable and four bodies of Swift once sat unverified for a week
# (see docs/tracker/FIRST-PRIORITY.md). This resolves every type, member and protocol
# conformance in all three targets — strictly more than `swiftc -parse`, which is syntax only
# and proves nothing about whether the code compiles.
#
# WHAT IT DOES NOT DO, and do not let anyone claim otherwise:
#   * no SIL, no IRGen, no linking, no resource/asset compilation
#   * it does not run a single test
#   * it cannot see runtime behaviour, layout, or anything a device would show you
# It narrows the simulator run. It never replaces it.
#
# Usage:   scripts/typecheck-ios.sh [ios-version]      (default: the deployment target)
# Exit 0 = all three targets type-check.

set -uo pipefail
cd "$(dirname "$0")/.."

IOS_VERSION="${1:-$(grep -m1 -oE 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+' escape_plan.xcodeproj/project.pbxproj | grep -oE '[0-9.]+')}"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
PDEV="$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer"
PLUG="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing"
TARGET="arm64-apple-ios${IOS_VERSION}-simulator"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "Type-checking against iOS ${IOS_VERSION} (${SDK##*/})"
status=0

find escape_plan -name '*.swift' > "$OUT/app.txt"
# Both configurations: a release-only run never sees SettingsScreen's #if DEBUG developer
# section, and a DEBUG-only run never catches code that breaks when DEBUG is absent (the
# test-double / #Preview split). One without the other has missed a real break before.
for cond in -DDEBUG ""; do
  label="${cond:-release}"
  if xcrun swiftc -typecheck -sdk "$SDK" -target "$TARGET" -swift-version 5 \
       $cond @"$OUT/app.txt" > "$OUT/app.$label.log" 2>&1; then
    echo "  ok    escape_plan        ($(wc -l < "$OUT/app.txt" | tr -d ' ') files, $label)"
  else
    echo "  FAIL  escape_plan        ($label)"; grep -E 'error:' "$OUT/app.$label.log" | grep -v '^ ' | head -20; status=1
  fi
done

# The test targets need a testable module of the app to satisfy `@testable import escape_plan`.
if ! xcrun swiftc -emit-module -module-name escape_plan -enable-testing \
      -sdk "$SDK" -target "$TARGET" -swift-version 5 -DDEBUG \
      -emit-module-path "$OUT/escape_plan.swiftmodule" @"$OUT/app.txt" > "$OUT/mod.log" 2>&1; then
  echo "  FAIL  could not emit a testable module"; grep -E 'error:' "$OUT/mod.log" | head -10; exit 1
fi

# -I $PDEV/usr/lib is the XCTest SWIFT OVERLAY. Without it Swift falls back to XCTest's C
# headers, where XCTAssertEqual is a function-like macro, and you get a confusing pile of
# "cannot find 'XCTAssertEqual' in scope". -plugin-path is Swift Testing's @Test/#expect macros.
for target_name in escape_planTests escape_planUITests; do
  find "$target_name" -name '*.swift' > "$OUT/$target_name.txt"
  if xcrun swiftc -typecheck -module-name "$target_name" \
       -sdk "$SDK" -target "$TARGET" -swift-version 5 -DDEBUG \
       -I "$OUT" -I "$PDEV/usr/lib" \
       -F "$PDEV/Library/Frameworks" -F "$SDK/Developer/Library/Frameworks" \
       -plugin-path "$PLUG" @"$OUT/$target_name.txt" > "$OUT/$target_name.log" 2>&1; then
    echo "  ok    $target_name  ($(wc -l < "$OUT/$target_name.txt" | tr -d ' ') files)"
  else
    echo "  FAIL  $target_name"; grep -E 'error:' "$OUT/$target_name.log" | grep -v '^ ' | sort -u | head -20; status=1
  fi
done

exit $status
