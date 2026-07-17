//
//  ScanExportBuilder.swift
//  Capture/Export — S1.4
//
//  Turns a captured structure into `RawScanExport`.
//
//  Foundation-only by design. RoomPlan's types are reached through the
//  protocols below, conformed in `RoomPlanScanSource.swift`. That seam is what
//  lets the exporter be compiled and executed on a Mac with no LiDAR device and
//  no simulator runtime (see `tools/scan-export-roundtrip`), and what lets tests
//  feed in synthetic geometry — `CapturedRoom` has no public initializer, so a
//  test could not otherwise construct one.
//

import Foundation

// MARK: - Source protocols

/// A wall/door/window/opening that can be exported.
protocol ScanSurfaceConvertible {
    var exportIdentifier: UUID { get }
    /// 16 floats, column-major.
    var exportTransform: [Float] { get }
    /// `[width, height, depth]`.
    var exportDimensions: [Float] { get }
    var exportConfidence: RawScanConfidence { get }
    var exportCategory: RawScanCategory { get }
    var exportParentIdentifier: UUID? { get }
    var exportStory: Int? { get }
}

/// One captured room.
protocol ScanRoomConvertible {
    var exportIdentifier: UUID? { get }
    var exportWalls: [any ScanSurfaceConvertible] { get }
    var exportDoors: [any ScanSurfaceConvertible] { get }
    var exportWindows: [any ScanSurfaceConvertible] { get }
    var exportOpenings: [any ScanSurfaceConvertible] { get }
    var exportSections: [RawScanSection] { get }
}

/// A merged structure, or a bag of unmerged rooms in the fallback path.
protocol ScanStructureConvertible {
    var exportRooms: [any ScanRoomConvertible] { get }
}

// MARK: - Builder

enum ScanExportBuilder {

    /// Build the export document. Pure: no I/O, no clock, no globals — the
    /// timestamp and device metadata are injected so output is reproducible.
    static func makeExport(from structure: any ScanStructureConvertible,
                           mode: RawScanCaptureMode,
                           exportedAt: Date,
                           appVersion: String? = nil,
                           deviceModel: String? = nil,
                           fallbackReason: String? = nil) -> RawScanExport {
        let rooms = structure.exportRooms.map(makeRoom(from:))
        let meta = RawScanCaptureMeta(
            mode: mode.rawValue,
            exportedAt: ISO8601DateFormatter.scanExport.string(from: exportedAt),
            appVersion: appVersion,
            deviceModel: deviceModel,
            roomCount: rooms.count,
            fallbackReason: fallbackReason
        )
        return RawScanExport(rooms: rooms, capture: meta)
    }

    static func makeRoom(from room: any ScanRoomConvertible) -> RawScanRoom {
        RawScanRoom(
            identifier: room.exportIdentifier?.uuidString.lowercased(),
            walls: room.exportWalls.map(makeSurface(from:)),
            doors: room.exportDoors.map(makeSurface(from:)),
            windows: room.exportWindows.map(makeSurface(from:)),
            openings: room.exportOpenings.map(makeSurface(from:)),
            sections: room.exportSections
        )
    }

    static func makeSurface(from surface: any ScanSurfaceConvertible) -> RawScanSurface {
        RawScanSurface(
            // Lowercased to match the converter fixtures; uuid5 hashing is
            // case-sensitive, so this must stay consistent forever.
            identifier: surface.exportIdentifier.uuidString.lowercased(),
            transform: surface.exportTransform,
            dimensions: surface.exportDimensions,
            confidence: surface.exportConfidence,
            category: surface.exportCategory,
            parentIdentifier: surface.exportParentIdentifier?.uuidString.lowercased(),
            story: surface.exportStory
        )
    }
}

extension ISO8601DateFormatter {
    static let scanExport: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
