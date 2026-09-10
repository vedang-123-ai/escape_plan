//
//  RawScanExport.swift
//  Capture/Export — S1.4
//
//  The on-the-wire raw scan format handed to the backend converter
//  (`backend/app/convert/`). This file is the Swift half of that contract; the
//  authoritative description lives in `backend/app/convert/README.md`.
//
//  Deliberately imports Foundation ONLY (no RoomPlan). The export format is
//  verified off-device by `tools/scan-export-roundtrip`, which compiles this
//  file natively — RoomPlan types would make that impossible.
//
//  Why we hand-roll this instead of `JSONEncoder().encode(capturedStructure)`:
//  Apple's synthesized Codable output for CapturedStructure is undocumented and
//  free to change between iOS releases. The converter is built against a pinned
//  shape, so we emit that shape explicitly. The Apple-encoded structure is still
//  written alongside as `apple-raw.json` for the S1.5 calibration diff.
//

import Foundation

/// Coding key that carries an arbitrary runtime string — needed because Swift
/// enums are encoded by RoomPlan as single-key objects (`{"high": {}}`).
struct RawScanDynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - Confidence

/// RoomPlan surface confidence. Encodes as `{"high": {}}` — Swift's JSONEncoder
/// representation of a case-less enum, which the converter's parser unwraps.
enum RawScanConfidence: String, Codable, Equatable, CaseIterable {
    case high
    case medium
    case low

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RawScanDynamicKey.self)
        // An empty nested container encodes the `{}` payload.
        _ = container.nestedContainer(keyedBy: RawScanDynamicKey.self,
                                      forKey: RawScanDynamicKey(rawValue))
    }

    init(from decoder: Decoder) throws {
        // Accept both `{"high": {}}` and the bare `"high"` form.
        if let single = try? decoder.singleValueContainer(),
           let bare = try? single.decode(String.self),
           let parsed = RawScanConfidence(rawValue: bare) {
            self = parsed
            return
        }
        let container = try decoder.container(keyedBy: RawScanDynamicKey.self)
        guard let key = container.allKeys.first,
              let parsed = RawScanConfidence(rawValue: key.stringValue) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "unrecognized confidence"))
        }
        self = parsed
    }
}

// MARK: - Category

/// RoomPlan surface category. Encodes the way Swift encodes an enum with
/// associated values: `{"door": {"isOpen": false}}`, `{"wall": {}}`.
///
/// The converter treats category as informational only (the containing array is
/// authoritative), but it round-trips faithfully so real exports stay diffable.
enum RawScanCategory: Codable, Equatable {
    case wall
    case door(isOpen: Bool)
    case window
    case opening
    case floor
    /// Forward-compatibility: an SDK category we don't model yet.
    case other(String)

    var name: String {
        switch self {
        case .wall: return "wall"
        case .door: return "door"
        case .window: return "window"
        case .opening: return "opening"
        case .floor: return "floor"
        case .other(let raw): return raw
        }
    }

    private enum DoorKeys: String, CodingKey { case isOpen }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RawScanDynamicKey.self)
        let key = RawScanDynamicKey(name)
        switch self {
        case .door(let isOpen):
            var nested = container.nestedContainer(keyedBy: DoorKeys.self, forKey: key)
            try nested.encode(isOpen, forKey: .isOpen)
        default:
            _ = container.nestedContainer(keyedBy: RawScanDynamicKey.self, forKey: key)
        }
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let bare = try? single.decode(String.self) {
            self = RawScanCategory(name: bare, isOpen: false)
            return
        }
        let container = try decoder.container(keyedBy: RawScanDynamicKey.self)
        guard let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "empty category object"))
        }
        var isOpen = false
        if key.stringValue == "door",
           let nested = try? container.nestedContainer(keyedBy: DoorKeys.self, forKey: key) {
            isOpen = (try? nested.decode(Bool.self, forKey: .isOpen)) ?? false
        }
        self = RawScanCategory(name: key.stringValue, isOpen: isOpen)
    }

    private init(name: String, isOpen: Bool) {
        switch name {
        case "wall": self = .wall
        case "door": self = .door(isOpen: isOpen)
        case "window": self = .window
        case "opening": self = .opening
        case "floor": self = .floor
        default: self = .other(name)
        }
    }
}

// MARK: - Surface

/// One wall / door / window / opening.
struct RawScanSurface: Codable, Equatable {
    /// Stable RoomPlan UUID. The converter derives every output id from this
    /// (uuid5), so conversion is idempotent — never regenerate it on export.
    var identifier: String
    /// 16 floats, **column-major** `simd_float4x4`: translation at 12/13/14,
    /// local x-axis (the along-surface direction) in 0/1/2.
    var transform: [Float]
    /// `[width, height, depth]` — width along local x, height along local y.
    var dimensions: [Float]
    var confidence: RawScanConfidence
    var category: RawScanCategory
    /// Doors/windows point at their containing wall.
    var parentIdentifier: String?
    var story: Int?
}

// MARK: - Section

/// A room label RoomPlan inferred (`livingRoom`, `bedroom`, …). The converter
/// lowercases and strips non-alphanumerics, so the SDK's camelCase case name
/// maps straight onto its `_SECTION_ROOM_TYPES` table.
struct RawScanSection: Codable, Equatable {
    var label: String
    var center: [Float]?
}

// MARK: - Object

/// One 3D object.
struct RawScanObject: Codable, Equatable {
    /// Stable RoomPlan UUID. The converter derives every output id from this
    /// (uuid5), so conversion is idempotent.
    var identifier: String
    /// 16 floats, **column-major** `simd_float4x4`.
    var transform: [Float]
    /// `[width, height, depth]`.
    var dimensions: [Float]
    var confidence: RawScanConfidence
    /// e.g. "sofa", "table"
    var category: String
}

// MARK: - Room / structure

/// One `CapturedRoom`.
struct RawScanRoom: Codable, Equatable {
    var identifier: String?
    var walls: [RawScanSurface]
    var doors: [RawScanSurface]
    var windows: [RawScanSurface]
    var openings: [RawScanSurface]
    var objects: [RawScanObject]
    var sections: [RawScanSection]

    init(identifier: String? = nil,
         walls: [RawScanSurface] = [],
         doors: [RawScanSurface] = [],
         windows: [RawScanSurface] = [],
         openings: [RawScanSurface] = [],
         objects: [RawScanObject] = [],
         sections: [RawScanSection] = []) {
        self.identifier = identifier
        self.walls = walls
        self.doors = doors
        self.windows = windows
        self.openings = openings
        self.objects = objects
        self.sections = sections
    }
}

/// How the rooms in an export were produced — the difference decides whether
/// S1.5 can trust cross-room door pairing by identifier.
enum RawScanCaptureMode: String, Codable {
    /// iOS 17+ `StructureBuilder` merged the rooms; shared doors should carry
    /// the same identifier in both rooms.
    case mergedStructure
    /// Fallback: unmerged per-room captures. Shared doors will have *different*
    /// identifiers, so the converter's geometric pairing path has to carry it.
    case sequentialRooms
}

/// Provenance for the calibration pass. The converter ignores unknown top-level
/// keys (`extra="ignore"`), so this rides along without affecting conversion.
struct RawScanCaptureMeta: Codable, Equatable {
    var mode: String
    var exportedAt: String
    var appVersion: String?
    var deviceModel: String?
    var roomCount: Int
    /// Set when the merged-structure path failed and we fell back.
    var fallbackReason: String?
}

/// The top-level document written to disk: `{"version": 3, "rooms": [...]}`.
struct RawScanExport: Codable, Equatable {
    /// Matches the `version` key on the committed synthetic fixtures.
    static let formatVersion = 3

    var version: Int
    var rooms: [RawScanRoom]
    var capture: RawScanCaptureMeta?

    init(rooms: [RawScanRoom], capture: RawScanCaptureMeta? = nil) {
        self.version = Self.formatVersion
        self.rooms = rooms
        self.capture = capture
    }
}

// MARK: - Encoding

extension RawScanExport {
    /// Canonical encoder: sorted keys + pretty printing so committed fixtures
    /// diff cleanly and byte-compare stably across runs.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    func encoded() throws -> Data {
        try Self.makeEncoder().encode(self)
    }
}
