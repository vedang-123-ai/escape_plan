#!/usr/bin/env bash
#
# S2.4 acceptance: an exported home document validates against the contract.
#
# Runs the persistence tests (which write a real export to $EXPORT_ARTIFACT_DIR)
# and then runs the S0.2 validator CLI over the exported file. The validator is
# Python and can't run inside the iOS test host, so the check is split in two.
#
#   ./scripts/verify_export_validates.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="${EXPORT_ARTIFACT_DIR:-$REPO_ROOT/.build/s24-exports}"
HARNESS="${TMPDIR:-/tmp}/escape-plan-s24-harness"

rm -rf "$EXPORT_DIR"

# --- 1. Run the persistence tests ------------------------------------------
#
# Via SwiftPM against a generated package rather than `xcodebuild test`: the
# Persistence module is Foundation/SwiftUI only, and this runs on any Mac
# without an installed iOS simulator runtime. Once a simulator runtime is
# available, `xcodebuild test -scheme escape_plan -destination ...` runs the
# same test file inside the app target and is the check that counts.
rm -rf "$HARNESS"
mkdir -p "$HARNESS/Sources" "$HARNESS/Tests/escape_planTests"
ln -s "$REPO_ROOT/escape_plan/Persistence" "$HARNESS/Sources/escape_plan"
ln -s "$REPO_ROOT/escape_planTests/PersistenceTests.swift" \
      "$HARNESS/Tests/escape_planTests/PersistenceTests.swift"
cat > "$HARNESS/Package.swift" <<'PACKAGE'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "escape_plan",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "escape_plan"),
        .testTarget(name: "escape_planTests", dependencies: ["escape_plan"]),
    ]
)
PACKAGE

echo "==> Running persistence tests"
( cd "$HARNESS" \
  && ESCAPE_PLAN_REPO_ROOT="$REPO_ROOT" EXPORT_ARTIFACT_DIR="$EXPORT_DIR" swift test )

# --- 2. Validate the exported document against the schema -------------------
EXPORTED="$EXPORT_DIR/Bungalow.json"
if [[ ! -f "$EXPORTED" ]]; then
    echo "FAIL: tests did not produce an export at $EXPORTED" >&2
    exit 1
fi

echo "==> Validating $EXPORTED against schema/homemodel.schema.json"
( cd "$REPO_ROOT/backend" && python3 -m app.validate "$EXPORTED" )

echo "==> S2.4 export acceptance PASSED"
