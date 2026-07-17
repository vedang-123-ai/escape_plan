//  HomeModel.swift — Codable mirror of schema/homemodel.schema.json v1.0
//
//  replace-with-S0.3: this is a MINIMAL, hand-written schema mirror written in the S2.1 lane
//  so the editor core has something to compile and test against. S0.3 (owner P2) owns the real
//  Models/ layer. When S0.3 lands, delete this file and point the editor core at S0.3's types.
//  The two must agree field-for-field — this file is derived directly from the JSON Schema and
//  round-trips every fixture in schema/fixtures/ (see HomeModelCodableTests).
//
//  Conventions locked by the schema (docs/schema-summary.md):
//    - all linear units are meters; polygons are floor-local 2D, CCW, non-self-intersecting
//    - edge i runs vertex i -> vertex (i+1) mod n
//    - "EXTERIOR" is a reserved pseudo-room id; room_ids: [room, EXTERIOR] marks an exit
//    - ids are unique across ALL entity kinds
//    - additionalProperties: false everywhere — never add a field here without a schema bump

import Foundation

/// The reserved pseudo-room id. An opening with this in `roomIds` is an exit to the outside.
public let EXTERIOR_ROOM_ID = "EXTERIOR"

// MARK: - Point

/// A 2D point in meters, floor-local. Encodes as the schema's `[x, y]` array, not an object.
public struct Point2D: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
        if !c.isAtEnd {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "point must have exactly 2 elements")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

// MARK: - Enums

public enum RoomType: String, Codable, Equatable, Sendable, CaseIterable {
    case bedroom, living, kitchen, hall, bath, garage, other
}

public enum SourceKind: String, Codable, Equatable, Sendable {
    case scan, manual
}

public enum OpeningKind: String, Codable, Equatable, Sendable {
    case door, window
}

public enum StairKind: String, Codable, Equatable, Sendable {
    case straight
    case L
    case U
}

public enum ProfileTag: String, Codable, Equatable, Sendable, CaseIterable {
    case child, elderly
    case mobilityLimited = "mobility_limited"
    case pet
}

// MARK: - Room

public struct Room: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var type: RoomType
    /// Footprint in meters, floor-local. CCW, non-self-intersecting, first vertex not repeated.
    public var polygon: [Point2D]
    public var source: SourceKind
    /// Required when `source == .scan` (pydantic-enforced, not schema-enforced).
    public var confidence: Double?

    public init(id: String, name: String, type: RoomType, polygon: [Point2D],
                source: SourceKind, confidence: Double? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.polygon = polygon
        self.source = source
        self.confidence = confidence
    }
}

// MARK: - Openings

/// Parametric placement of an opening on a wall: (room polygon edge, t-range).
/// Because placement is relative to the edge, dragging a wall moves its doors and windows.
public struct WallSegmentRef: Codable, Equatable, Sendable {
    public var roomId: String
    public var edgeIndex: Int
    public var t0: Double
    public var t1: Double

    public init(roomId: String, edgeIndex: Int, t0: Double, t1: Double) {
        self.roomId = roomId
        self.edgeIndex = edgeIndex
        self.t0 = t0
        self.t1 = t1
    }

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case edgeIndex = "edge_index"
        case t0, t1
    }
}

/// COMPUTED egress assessment written back by the S1.1 backend annotator.
/// The editor must round-trip this but must NEVER author or mutate it.
public struct Egress: Codable, Equatable, Sendable {
    public var viable: Bool
    public var reasons: [String]

    public init(viable: Bool, reasons: [String] = []) {
        self.viable = viable
        self.reasons = reasons
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viable = try c.decode(Bool.self, forKey: .viable)
        reasons = try c.decodeIfPresent([String].self, forKey: .reasons) ?? []
    }
}

public struct Opening: Codable, Equatable, Sendable {
    public var id: String
    public var kind: OpeningKind
    /// Exactly 2 entries: two rooms (interior adjacency), or one room + `EXTERIOR` (an exit).
    public var roomIds: [String]
    public var wallSegment: WallSegmentRef
    /// Clear width in meters. Authoritative for egress checks — the t-range is placement, not size.
    public var widthM: Double
    public var heightM: Double
    public var sillHeightM: Double
    public var egress: Egress?
    public var source: SourceKind
    public var confidence: Double?

    public init(id: String, kind: OpeningKind, roomIds: [String], wallSegment: WallSegmentRef,
                widthM: Double, heightM: Double, sillHeightM: Double,
                egress: Egress? = nil, source: SourceKind, confidence: Double? = nil) {
        self.id = id
        self.kind = kind
        self.roomIds = roomIds
        self.wallSegment = wallSegment
        self.widthM = widthM
        self.heightM = heightM
        self.sillHeightM = sillHeightM
        self.egress = egress
        self.source = source
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case id, kind
        case roomIds = "room_ids"
        case wallSegment = "wall_segment"
        case widthM = "width_m"
        case heightM = "height_m"
        case sillHeightM = "sill_height_m"
        case egress, source, confidence
    }

    /// True when this opening leads outside.
    public var isExit: Bool { roomIds.contains(EXTERIOR_ROOM_ID) }
}

// MARK: - Floor

public struct Floor: Codable, Equatable, Sendable {
    public var id: String
    /// 0 = ground, 1 = second story, -1 = basement. Unique across floors.
    public var level: Int
    public var name: String
    /// Floor-to-ceiling height; the extrusion height for this floor's room polygons.
    public var heightM: Double
    public var rooms: [Room]
    public var openings: [Opening]

    public init(id: String, level: Int, name: String, heightM: Double,
                rooms: [Room], openings: [Opening] = []) {
        self.id = id
        self.level = level
        self.name = name
        self.heightM = heightM
        self.rooms = rooms
        self.openings = openings
    }

    enum CodingKeys: String, CodingKey {
        case id, level, name
        case heightM = "height_m"
        case rooms, openings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        level = try c.decode(Int.self, forKey: .level)
        name = try c.decode(String.self, forKey: .name)
        heightM = try c.decode(Double.self, forKey: .heightM)
        rooms = try c.decode([Room].self, forKey: .rooms)
        openings = try c.decodeIfPresent([Opening].self, forKey: .openings) ?? []
    }

    public func room(_ id: String) -> Room? { rooms.first { $0.id == id } }
}

// MARK: - Stairs

public struct StairEnd: Codable, Equatable, Sendable {
    public var floorId: String
    public var roomId: String

    public init(floorId: String, roomId: String) {
        self.floorId = floorId
        self.roomId = roomId
    }

    enum CodingKeys: String, CodingKey {
        case floorId = "floor_id"
        case roomId = "room_id"
    }
}

public struct Stairs: Codable, Equatable, Sendable {
    public var id: String
    /// JSON key is `from` (a Swift keyword) — see CodingKeys. Lower endpoint by convention.
    public var fromEnd: StairEnd
    public var toEnd: StairEnd
    /// 2D footprint of the stair run, in the `from` floor's coordinate frame.
    public var footprint: [Point2D]
    public var kind: StairKind
    public var source: SourceKind
    public var confidence: Double?

    public init(id: String, fromEnd: StairEnd, toEnd: StairEnd, footprint: [Point2D],
                kind: StairKind, source: SourceKind, confidence: Double? = nil) {
        self.id = id
        self.fromEnd = fromEnd
        self.toEnd = toEnd
        self.footprint = footprint
        self.kind = kind
        self.source = source
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fromEnd = "from"
        case toEnd = "to"
        case footprint, kind, source, confidence
    }
}

// MARK: - Profile

public struct Profile: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var tags: [ProfileTag]
    public var bedroomRoomId: String

    public init(id: String, name: String, tags: [ProfileTag], bedroomRoomId: String) {
        self.id = id
        self.name = name
        self.tags = tags
        self.bedroomRoomId = bedroomRoomId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, tags
        case bedroomRoomId = "bedroom_room_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tags = try c.decodeIfPresent([ProfileTag].self, forKey: .tags) ?? []
        bedroomRoomId = try c.decode(String.self, forKey: .bedroomRoomId)
    }
}

// MARK: - Meta

public struct Meta: Codable, Equatable, Sendable {
    /// ISO 8601 timestamps, kept as strings so round-tripping never reformats them.
    public var created: String
    public var modified: String
    public var addressOptional: String?

    public init(created: String, modified: String, addressOptional: String? = nil) {
        self.created = created
        self.modified = modified
        self.addressOptional = addressOptional
    }

    enum CodingKeys: String, CodingKey {
        case created, modified
        case addressOptional = "address_optional"
    }
}

// MARK: - HomeModel

public struct HomeModel: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var homeId: String
    public var name: String
    public var floors: [Floor]
    public var stairs: [Stairs]
    public var profiles: [Profile]
    public var meta: Meta

    public init(schemaVersion: String = HomeModel.currentSchemaVersion,
                homeId: String, name: String, floors: [Floor],
                stairs: [Stairs] = [], profiles: [Profile] = [], meta: Meta) {
        self.schemaVersion = schemaVersion
        self.homeId = homeId
        self.name = name
        self.floors = floors
        self.stairs = stairs
        self.profiles = profiles
        self.meta = meta
    }

    public static let currentSchemaVersion = "1.0"

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case homeId = "home_id"
        case name, floors, stairs, profiles, meta
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        homeId = try c.decode(String.self, forKey: .homeId)
        name = try c.decode(String.self, forKey: .name)
        floors = try c.decode([Floor].self, forKey: .floors)
        stairs = try c.decodeIfPresent([Stairs].self, forKey: .stairs) ?? []
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        meta = try c.decode(Meta.self, forKey: .meta)
    }

    // MARK: Lookups

    public func floor(_ id: String) -> Floor? { floors.first { $0.id == id } }

    public func floorIndex(_ id: String) -> Int? { floors.firstIndex { $0.id == id } }

    /// Finds a room anywhere in the home, with the floor it lives on.
    public func locateRoom(_ roomId: String) -> (floorId: String, room: Room)? {
        for f in floors {
            if let r = f.room(roomId) { return (f.id, r) }
        }
        return nil
    }
}
