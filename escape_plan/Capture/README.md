# Capture/ — RoomPlan scan module (S1.4)

Self-contained: scan UX, RoomPlan session handling, and the raw-scan exporter that
feeds `backend/app/convert/` (S1.5). Drops into the S0.3 app shell as a group — it
has no dependencies on the rest of the app.

Treat scan output as **draft input to the editor, never final** (playbook S1.4).

## Layout

| File | Role | Imports RoomPlan? |
|---|---|---|
| `Export/RawScanExport.swift` | The wire format (DTOs + encoding) | no |
| `Export/ScanExportBuilder.swift` | Source protocols + structure → DTO | no |
| `Export/ScanStore.swift` | Writes artifacts to the documents directory | no |
| `Export/RoomPlanScanSource.swift` | RoomPlan conformances — the whole blast radius | **yes** |
| `RoomCaptureController.swift` | Session lifecycle + scan state machine | yes |
| `Views/ScanFlowView.swift` | Instructions → scanning → review → failure | no |
| `Views/RoomCaptureViewRepresentable.swift` | UIKit `RoomCaptureView` bridge | yes |

Only two files touch RoomPlan's model types. Everything else is Foundation-only,
on purpose (see *Why the protocol seam* below).

## Integration points (for the S0.3 shell)

Present the flow and take the artifacts:

```swift
ScanFlowView(
    onFinished: { artifacts in
        // artifacts.rawJSON  → POST to /convert  → HomeModel → editor
        // artifacts.usdz     → optional 3D preview
    },
    onCancel: { /* dismiss */ }
)
```

- `ScanArtifacts.rawJSON` is the only artifact S1.5 consumes.
- The controller is `@MainActor @Observable`; the shell owns no scan state.
- Requires `NSCameraUsageDescription` (already set as an `INFOPLIST_KEY_*` build
  setting) and a LiDAR device. `RoomCaptureController.isSupported` is false on
  Simulator and on non-LiDAR hardware; the UI degrades to an explanatory screen
  rather than offering a scanner that cannot start.
- TODO(integration): wire `onFinished` to the shell's navigation and the
  `/convert` client once S0.3 and the API client land.

## On-disk layout

```
Documents/Scans/<yyyyMMdd-HHmmss>-<short-id>/
    raw.roomplan.json   ← converter input (our pinned format)
    apple-raw.json      ← Apple's own CapturedStructure encoding (diagnostic)
    scan.usdz           ← parametric USDZ
```

`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` are set so a scan
directory can be dragged off the device via Finder/Files — that is how real scans
reach `schema/fixtures/scans/`.

## The wire format

`backend/app/convert/README.md` is authoritative. The shape:

```json
{ "version": 2,
  "rooms": [ { "identifier": "…",
               "walls": [ { "identifier": "…",
                            "transform":  [16 floats, column-major],
                            "dimensions": [w, h, d],
                            "confidence": {"high": {}},
                            "category":   {"wall": {}},
                            "parentIdentifier": null,
                            "story": 0 } ],
               "doors": [], "windows": [], "openings": [],
               "sections": [ {"label": "livingRoom", "center": [x,y,z]} ] } ],
  "capture": { "mode": "mergedStructure", … } }
```

Three details are load-bearing and silently destructive if broken:

1. **`transform` is column-major** — translation at 12/13/14, local x-axis at
   0/1/2. Row-major would rotate every wall, and the converter cannot detect it
   (symptom: every room degrades to its bounding box).
2. **Identifiers pass through verbatim, lowercased** — the converter uuid5-hashes
   them, so mutating them breaks idempotency and shared-door pairing.
3. **`sections[].label` is the SDK's case name** (`livingRoom`), which the
   converter lowercases to `livingroom` for its room-type table.

`capture` is our own provenance block; the converter ignores unknown top-level
keys (`extra="ignore"`), so it rides along harmlessly.

### Why we don't just `JSONEncoder().encode(capturedStructure)`

Apple's synthesized Codable output for `CapturedStructure` is undocumented and
free to change between iOS releases; the converter is built against a pinned
shape. So we emit that shape explicitly, and write Apple's encoding beside it as
`apple-raw.json` for the S1.5 calibration diff.

### Why the protocol seam

`CapturedRoom` and `CapturedRoom.Surface` have **no public initializers**, so no
test can construct one. `ScanSurfaceConvertible` / `ScanRoomConvertible` /
`ScanStructureConvertible` let RoomPlan's types and synthetic test geometry feed
the same builder. That is what makes `tools/scan-export-roundtrip/run.sh` possible:
it compiles the Foundation-only files natively and pushes synthetic geometry
through the real Python converter — no device, no simulator runtime.

## Multi-room strategy

Continuous multi-room capture merged via the iOS 17+ `StructureBuilder` →
`CapturedStructure` API (the playbook's recommended path). Each room is one
run/stop cycle on a single `RoomCaptureSession`; stopping with
`pauseARSession: false` keeps ARKit tracking alive so rooms share a world origin.

**Fallback** (playbook-sanctioned): if `StructureBuilder` is unavailable or
throws, rooms are exported unmerged with `capture.mode = "sequentialRooms"` and a
`capture.fallbackReason`. Same wire format — S1.5 then has to pair shared doors
geometrically instead of by identifier. The fallback is visible in the review UI,
never silent.

## Verification

- `tools/scan-export-roundtrip/run.sh` — exporter → converter → valid HomeModel.
  **Runs anywhere; run it after touching anything in `Export/`.**
- `xcodebuild -project escape_plan.xcodeproj -target escape_plan -sdk iphonesimulator26.5 build`
- `escape_planTests/ScanExportTests.swift` — compiles; **not yet executed** (no
  simulator runtime on the S1.4 machine).
