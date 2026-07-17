//
//  main.swift
//  tools/scan-export-roundtrip — S1.4
//
//  Off-device verification harness for the scan exporter.
//
//  Why this exists: S1.4's acceptance is "the exporter round-trips a synthetic
//  CapturedStructure into JSON the converter accepts". That can't be checked the
//  obvious way here — `CapturedRoom` has no public initializer (so no test can
//  build one), and this machine has the iOS Simulator SDK but no simulator
//  *runtime*, so XCTest cannot execute at all. Instead this compiles the
//  RoomPlan-free half of the exporter natively, feeds it synthetic geometry
//  through the same `ScanStructureConvertible` seam RoomPlan conforms to, and
//  prints the JSON — which the Python converter then ingests for real.
//
//  Run: tools/scan-export-roundtrip/run.sh
//
//  The geometry mirrors schema/fixtures/scans/synthetic-bungalow.roomplan.json:
//  a 5m × 4m room, four walls, a front door (exterior) and an interior door, one
//  window. Coordinates are RoomPlan world space (y-up, meters).
//

import Foundation

// MARK: - Synthetic conformances

/// Stands in for `CapturedRoom.Surface` (which tests cannot construct).
struct FakeSurface: ScanSurfaceConvertible {
    var exportIdentifier: UUID
    var exportTransform: [Float]
    var exportDimensions: [Float]
    var exportConfidence: RawScanConfidence
    var exportCategory: RawScanCategory
    var exportParentIdentifier: UUID?
    var exportStory: Int?
}

struct FakeRoom: ScanRoomConvertible {
    var exportIdentifier: UUID?
    var walls: [FakeSurface] = []
    var doors: [FakeSurface] = []
    var windows: [FakeSurface] = []
    var openings: [FakeSurface] = []
    var exportSections: [RawScanSection] = []

    var exportWalls: [any ScanSurfaceConvertible] { walls }
    var exportDoors: [any ScanSurfaceConvertible] { doors }
    var exportWindows: [any ScanSurfaceConvertible] { windows }
    var exportOpenings: [any ScanSurfaceConvertible] { openings }
}

struct FakeStructure: ScanStructureConvertible {
    var rooms: [FakeRoom]
    var exportRooms: [any ScanRoomConvertible] { rooms }
}

// MARK: - Geometry helpers

/// Column-major simd_float4x4 for a surface whose local x-axis points along
/// `direction` in the floor plan, centered at (`x`, `y`, `z`).
func transform(x: Float, y: Float, z: Float, direction: (Float, Float)) -> [Float] {
    let (dx, dz) = direction
    // column 0 = local x-axis (along-wall), column 1 = up, column 2 = normal.
    return [
        dx, 0, dz, 0,
        0, 1, 0, 0,
        -dz, 0, dx, 0,
        x, y, z, 1,
    ]
}

/// Deterministic UUIDs so reruns byte-match (uuid5-style, but any stable source
/// works — the converter only requires stability, not a particular algorithm).
func stableUUID(_ seed: String) -> UUID {
    var bytes = Array(Data(seed.utf8))
    while bytes.count < 16 {
        bytes.append(UInt8(truncatingIfNeeded: bytes.count &* 37 &+ 11))
    }
    var truncated = Array(bytes.prefix(16))
    truncated[6] = (truncated[6] & 0x0F) | 0x50  // version 5
    truncated[8] = (truncated[8] & 0x3F) | 0x80  // RFC 4122 variant
    let hex = truncated.map { String(format: "%02x", $0) }.joined()
    let parts = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
                 hex.dropFirst(16).prefix(4), hex.dropFirst(20).prefix(12)]
    return UUID(uuidString: parts.joined(separator: "-"))!
}

func wall(_ name: String, x: Float, z: Float, width: Float,
          direction: (Float, Float)) -> FakeSurface {
    FakeSurface(
        exportIdentifier: stableUUID("wall-\(name)"),
        exportTransform: transform(x: x, y: 1.25, z: z, direction: direction),
        exportDimensions: [width, 2.5, 0],
        exportConfidence: .high,
        exportCategory: .wall,
        exportParentIdentifier: nil,
        exportStory: 0
    )
}

// MARK: - The synthetic bungalow

/// A 5m × 4m living room: origin at (0,0), extending to (5,4) in plan.
let livingRoom = FakeRoom(
    exportIdentifier: stableUUID("room-living"),
    walls: [
        wall("south", x: 2.5, z: 0.0, width: 5.0, direction: (1, 0)),
        wall("east", x: 5.0, z: 2.0, width: 4.0, direction: (0, 1)),
        wall("north", x: 2.5, z: 4.0, width: 5.0, direction: (1, 0)),
        wall("west", x: 0.0, z: 2.0, width: 4.0, direction: (0, 1)),
    ],
    doors: [
        // Front door on the south wall → unpaired → EXTERIOR exit.
        FakeSurface(
            exportIdentifier: stableUUID("door-front"),
            exportTransform: transform(x: 1.2, y: 1.0, z: 0.0, direction: (1, 0)),
            exportDimensions: [0.9, 2.0, 0],
            exportConfidence: .high,
            exportCategory: .door(isOpen: false),
            exportParentIdentifier: stableUUID("wall-south"),
            exportStory: 0
        ),
        // Interior door on the north wall → shared with the bedroom below.
        FakeSurface(
            exportIdentifier: stableUUID("door-shared"),
            exportTransform: transform(x: 3.5, y: 1.0, z: 4.0, direction: (1, 0)),
            exportDimensions: [0.9, 2.0, 0],
            exportConfidence: .high,
            exportCategory: .door(isOpen: true),
            exportParentIdentifier: stableUUID("wall-north"),
            exportStory: 0
        ),
    ],
    windows: [
        FakeSurface(
            exportIdentifier: stableUUID("window-living"),
            exportTransform: transform(x: 5.0, y: 1.4, z: 2.0, direction: (0, 1)),
            exportDimensions: [1.0, 1.2, 0],
            exportConfidence: .medium,
            exportCategory: .window,
            exportParentIdentifier: stableUUID("wall-east"),
            exportStory: 0
        )
    ],
    exportSections: [RawScanSection(label: "livingRoom", center: [2.5, 1.0, 2.0])]
)

/// A 5m × 3m bedroom north of the living room: plan (0,4) → (5,7).
let bedroom = FakeRoom(
    exportIdentifier: stableUUID("room-bed"),
    walls: [
        wall("bed-south", x: 2.5, z: 4.0, width: 5.0, direction: (1, 0)),
        wall("bed-east", x: 5.0, z: 5.5, width: 3.0, direction: (0, 1)),
        wall("bed-north", x: 2.5, z: 7.0, width: 5.0, direction: (1, 0)),
        wall("bed-west", x: 0.0, z: 5.5, width: 3.0, direction: (0, 1)),
    ],
    doors: [
        // Same identifier as the living room's interior door: this is what a
        // merged CapturedStructure is assumed to produce, and it exercises the
        // converter's identifier-based shared-door pairing.
        FakeSurface(
            exportIdentifier: stableUUID("door-shared"),
            exportTransform: transform(x: 3.5, y: 1.0, z: 4.0, direction: (1, 0)),
            exportDimensions: [0.9, 2.0, 0],
            exportConfidence: .high,
            exportCategory: .door(isOpen: true),
            exportParentIdentifier: stableUUID("wall-bed-south"),
            exportStory: 0
        )
    ],
    windows: [
        // Egress window — the bedroom's second way out.
        FakeSurface(
            exportIdentifier: stableUUID("window-bed"),
            exportTransform: transform(x: 2.5, y: 1.1, z: 7.0, direction: (1, 0)),
            exportDimensions: [1.2, 1.3, 0],
            exportConfidence: .high,
            exportCategory: .window,
            exportParentIdentifier: stableUUID("wall-bed-north"),
            exportStory: 0
        )
    ],
    exportSections: [RawScanSection(label: "bedroom", center: [2.5, 1.0, 5.5])]
)

// MARK: - Emit

let export = ScanExportBuilder.makeExport(
    from: FakeStructure(rooms: [livingRoom, bedroom]),
    mode: .mergedStructure,
    // Fixed clock: the harness must be byte-reproducible across runs.
    exportedAt: Date(timeIntervalSince1970: 1_763_000_000),
    appVersion: "0.1.0-s14",
    deviceModel: "synthetic"
)

let data = try export.encoded()
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
