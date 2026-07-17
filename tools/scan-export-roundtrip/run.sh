#!/usr/bin/env bash
#
# tools/scan-export-roundtrip/run.sh — S1.4 exporter round-trip check.
#
# Compiles the RoomPlan-free half of the Capture/Export module natively (no
# simulator runtime needed), emits a synthetic scan export, and feeds it to the
# S1.5 Python converter. Passes only if the converter produces a HomeModel that
# clears both validators.
#
# Usage: tools/scan-export-roundtrip/run.sh [--write-fixture]
#   --write-fixture  also refresh schema/fixtures/scans/synthetic-exporter.roomplan.json
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

EXPORT_DIR="$REPO_ROOT/escape_plan/Capture/Export"
OUT_JSON="$BUILD_DIR/export.json"

echo "==> Compiling exporter natively (RoomPlan-free sources)"
# RoomPlanScanSource.swift is deliberately excluded: it imports RoomPlan, which
# has no macOS slice. Its conformances are covered by the iOS xcodebuild check.
swiftc -O \
  -o "$BUILD_DIR/scan-export-roundtrip" \
  "$EXPORT_DIR/RawScanExport.swift" \
  "$EXPORT_DIR/ScanExportBuilder.swift" \
  "$REPO_ROOT/tools/scan-export-roundtrip/main.swift"

echo "==> Emitting synthetic scan export"
"$BUILD_DIR/scan-export-roundtrip" > "$OUT_JSON"

echo "==> Checking determinism (same input must byte-match)"
"$BUILD_DIR/scan-export-roundtrip" > "$BUILD_DIR/export2.json"
if ! cmp -s "$OUT_JSON" "$BUILD_DIR/export2.json"; then
  echo "FAIL: exporter is not deterministic across runs" >&2
  exit 1
fi

echo "==> Converting through backend/app/convert (S1.5)"
cd "$REPO_ROOT/backend"
python3 - "$OUT_JSON" <<'PY'
import json, sys
from datetime import datetime, timezone

from app.convert import convert_scan

with open(sys.argv[1]) as handle:
    export = json.load(handle)

model = convert_scan(
    export,
    home_name="S1.4 exporter round-trip",
    timestamp=datetime(2026, 1, 1, tzinfo=timezone.utc),
)

floor = model.floors[0]
rooms = floor.rooms
exits = [o for o in floor.openings if "EXTERIOR" in o.room_ids]
interior = [o for o in floor.openings if "EXTERIOR" not in o.room_ids]

print(f"    rooms:     {len(rooms)} -> {[r.name for r in rooms]}")
print(f"    types:     {[r.type.value for r in rooms]}")
print(f"    openings:  {len(floor.openings)} ({len(exits)} exterior, {len(interior)} interior)")
print(f"    confidence:{[round(r.confidence, 3) if r.confidence else None for r in rooms]}")

# The scan is only useful if the converter recovered real structure from it.
assert len(rooms) == 2, f"expected 2 rooms, got {len(rooms)}"
assert {r.type.value for r in rooms} == {"living", "bedroom"}, \
    f"section labels did not map to room types: {[r.type.value for r in rooms]}"
assert interior, "the shared door did not pair into an interior opening"
assert exits, "no exterior exit was produced"

# Idempotency: the converter contract promises byte-identical output.
again = convert_scan(export, home_name="S1.4 exporter round-trip",
                     timestamp=datetime(2026, 1, 1, tzinfo=timezone.utc))
assert again.model_dump_json() == model.model_dump_json(), "conversion is not idempotent"

# exclude_none matters: `egress` is computed-only (absent until S1.1's annotator
# runs) and the schema types it as an object, so a serialized `"egress": null`
# is schema-invalid. See docs/tracker/notes/2026-07-16-S1.4-roomplan-capture.md
# — the /convert endpoint currently emits exactly that.
with open("/tmp/s14_roundtrip_home.json", "w") as handle:
    handle.write(model.model_dump_json(indent=2, exclude_none=True))
print("    OK: converter accepted the export")
PY

echo "==> Validating the resulting HomeModel (JSON Schema + pydantic)"
python3 -m app.validate /tmp/s14_roundtrip_home.json

if [[ "${1:-}" == "--write-fixture" ]]; then
  FIXTURE="$REPO_ROOT/schema/fixtures/scans/synthetic-exporter.roomplan.json"
  cp "$OUT_JSON" "$FIXTURE"
  echo "==> Wrote $FIXTURE"
fi

echo "PASS: exporter output round-trips into a valid HomeModel"
