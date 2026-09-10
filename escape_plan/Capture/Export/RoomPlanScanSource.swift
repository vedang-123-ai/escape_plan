//
//  RoomPlanScanSource.swift
//  Capture/Export — S1.4
//
//  The ONLY file in Capture/Export that imports RoomPlan. Everything else stays
//  Foundation-only so the export path can be executed off-device.
//
//  If Apple changes RoomPlan's model types, this file is the blast radius.
//

import Foundation

#if canImport(RoomPlan)
import RoomPlan
import simd

// MARK: - simd → wire

extension simd_float4x4 {
    /// Flatten column-major: columns 0…3 laid out end to end, so translation
    /// lands at indices 12/13/14. This ordering IS the converter contract
    /// (`backend/app/convert/README.md` § Coordinate conventions) — reversing it
    /// silently rotates every wall, which the converter cannot detect.
    var exportColumnMajorFloats: [Float] {
        [columns.0, columns.1, columns.2, columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }
}

// MARK: - Surface

@available(iOS 16.0, *)
extension CapturedRoom.Surface: ScanSurfaceConvertible {
    var exportIdentifier: UUID { identifier }
    var exportTransform: [Float] { transform.exportColumnMajorFloats }
    var exportDimensions: [Float] { [dimensions.x, dimensions.y, dimensions.z] }

    var exportConfidence: RawScanConfidence {
        switch confidence {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        @unknown default: return .medium
        }
    }

    var exportCategory: RawScanCategory {
        switch category {
        case .wall: return .wall
        case .door(let isOpen): return .door(isOpen: isOpen)
        case .window: return .window
        case .opening: return .opening
        default:
            // .floor (iOS 17) and any future case. The containing array is what
            // the converter actually keys off, so an unknown name is harmless.
            return .other(String(describing: category).components(separatedBy: "(").first
                          ?? "unknown")
        }
    }

    var exportParentIdentifier: UUID? { parentIdentifier }

    var exportStory: Int? {
        // `story` arrived in iOS 17. v1 assumes one story per scan session; the
        // value rides along so a future multi-floor pass has it.
        if #available(iOS 17.0, *) { return story }
        return nil
    }
}

// MARK: - Object

@available(iOS 16.0, *)
extension CapturedRoom.Object: ScanObjectConvertible {
    var exportIdentifier: UUID { identifier }
    var exportTransform: [Float] { transform.exportColumnMajorFloats }
    var exportDimensions: [Float] { [dimensions.x, dimensions.y, dimensions.z] }

    var exportConfidence: RawScanConfidence {
        switch confidence {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        @unknown default: return .medium
        }
    }

    var exportCategory: String {
        let raw = String(describing: category)
        return raw.components(separatedBy: "(").first ?? raw
    }
}

// MARK: - Room

@available(iOS 16.0, *)
extension CapturedRoom: ScanRoomConvertible {
    var exportIdentifier: UUID? {
        if #available(iOS 17.0, *) { return identifier }
        return nil
    }

    var exportWalls: [any ScanSurfaceConvertible] { walls }
    var exportDoors: [any ScanSurfaceConvertible] { doors }
    var exportWindows: [any ScanSurfaceConvertible] { windows }
    var exportOpenings: [any ScanSurfaceConvertible] { openings }
    var exportObjects: [any ScanObjectConvertible] { objects }

    var exportSections: [RawScanSection] {
        sections.map { section in
            // `String(describing:)` yields the SDK case name ("livingRoom"), which
            // the converter lowercases + strips to "livingroom" for its room-type
            // table. Enumerating the cases here would break on new SDK labels.
            RawScanSection(
                label: String(describing: section.label),
                center: [section.center.x, section.center.y, section.center.z]
            )
        }
    }
}

// MARK: - Structure

@available(iOS 17.0, *)
extension CapturedStructure: ScanStructureConvertible {
    var exportRooms: [any ScanRoomConvertible] { rooms }
}

/// Fallback container: unmerged per-room captures (StructureBuilder unavailable
/// or failed). The wire format is identical — only `capture.mode` differs — so
/// S1.5 merges them via the converter's geometric door-pairing path.
@available(iOS 16.0, *)
struct CapturedRoomCollection: ScanStructureConvertible {
    var rooms: [CapturedRoom]
    var exportRooms: [any ScanRoomConvertible] { rooms }
}

#endif
