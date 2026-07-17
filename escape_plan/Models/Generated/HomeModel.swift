// HomeModel — Codable mirror of schema/homemodel.schema.json v1.0.
//
// TODO(integration): replace this whole directory wholesale with S0.3's model layer on merge.
// S0.3 is being built in a parallel worktree and is not on this branch; the renderer needs a
// model to decode fixtures into, so this is a deliberate throwaway stand-in. It mirrors the
// schema field-for-field but carries no validation (pydantic owns the geometric invariants)
// and no mutation/undo plumbing (S0.3's HomeModelStore owns that).
//
// Everything the renderer touches goes through these types, so swapping in S0.3's structs
// should be a delete-and-rebuild rather than a rewrite — as long as the field names match
// the schema, which is the contract both sides are written against.

import Foundation

// MARK: - Geometry primitives

/// A 2D point in meters, floor-local. Encoded as a bare `[x, y]` array by the schema.
struct Point: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

/// A simple closed polygon: ordered vertices, closing edge implicit, first vertex not repeated.
/// Edge `i` runs from vertex `i` to vertex `(i + 1) % count` — this is what `edge_index` indexes.
typealias Polygon = [Point]

// MARK: - Enums

enum Source: String, Codable {
    case scan
    case manual
}

enum RoomType: String, Codable {
    case bedroom, living, kitchen, hall, bath, garage, other
}

enum OpeningKind: String, Codable {
    case door, window
}

enum StairKind: String, Codable {
    case straight
    case l = "L"
    case u = "U"
}

enum ProfileTag: String, Codable {
    case child, elderly
    case mobilityLimited = "mobility_limited"
    case pet
}

// MARK: - Entities

struct Room: Codable, Identifiable {
    var id: String
    var name: String
    var type: RoomType
    var polygon: Polygon
    var source: Source
    var confidence: Double?
}

/// Parametric placement of an opening on a wall: (room polygon edge, t-range).
/// The renderer must derive world position from `roomID` + `edgeIndex` + `t0`/`t1` — never
/// from absolute coordinates — so that moving a wall carries its openings with it.
struct WallSegment: Codable {
    var roomID: String
    var edgeIndex: Int
    var t0: Double
    var t1: Double

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case edgeIndex = "edge_index"
        case t0, t1
    }
}

/// Computed-only egress assessment (written by the S1.1 annotator). Absent until it runs.
struct Egress: Codable {
    var viable: Bool
    var reasons: [String]

    enum CodingKeys: String, CodingKey {
        case viable, reasons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viable = try c.decode(Bool.self, forKey: .viable)
        reasons = try c.decodeIfPresent([String].self, forKey: .reasons) ?? []
    }
}

struct Opening: Codable, Identifiable {
    var id: String
    var kind: OpeningKind
    /// Exactly two entries. Two rooms = interior adjacency; room + `EXTERIOR` = an exit.
    var roomIDs: [String]
    var wallSegment: WallSegment
    var widthM: Double
    var heightM: Double
    var sillHeightM: Double
    var egress: Egress?
    var source: Source
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id, kind, egress, source, confidence
        case roomIDs = "room_ids"
        case wallSegment = "wall_segment"
        case widthM = "width_m"
        case heightM = "height_m"
        case sillHeightM = "sill_height_m"
    }

    /// `EXTERIOR` is the reserved pseudo-room id; an opening naming it leads outside.
    var isExit: Bool { roomIDs.contains(HomeModel.exteriorRoomID) }
}

struct Floor: Codable, Identifiable {
    var id: String
    /// 0 = ground, 1 = second story, -1 = basement. Unique across floors.
    var level: Int
    var name: String
    var heightM: Double
    var rooms: [Room]
    var openings: [Opening]

    enum CodingKeys: String, CodingKey {
        case id, level, name, rooms, openings
        case heightM = "height_m"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        level = try c.decode(Int.self, forKey: .level)
        name = try c.decode(String.self, forKey: .name)
        heightM = try c.decode(Double.self, forKey: .heightM)
        rooms = try c.decode([Room].self, forKey: .rooms)
        openings = try c.decodeIfPresent([Opening].self, forKey: .openings) ?? []
    }
}

struct StairEnd: Codable {
    var floorID: String
    var roomID: String

    enum CodingKeys: String, CodingKey {
        case floorID = "floor_id"
        case roomID = "room_id"
    }
}

struct Stairs: Codable, Identifiable {
    var id: String
    /// JSON key is `from` (pydantic calls it `from_`). Lower endpoint by convention.
    var from: StairEnd
    var to: StairEnd
    /// 2D footprint of the stair run, in the `from` floor's coordinate frame.
    var footprint: Polygon
    var kind: StairKind
    var source: Source
    var confidence: Double?
}

struct Profile: Codable, Identifiable {
    var id: String
    var name: String
    var tags: [ProfileTag]
    var bedroomRoomID: String

    enum CodingKeys: String, CodingKey {
        case id, name, tags
        case bedroomRoomID = "bedroom_room_id"
    }
}

struct Meta: Codable {
    var created: String
    var modified: String
    var addressOptional: String?

    enum CodingKeys: String, CodingKey {
        case created, modified
        case addressOptional = "address_optional"
    }
}

// MARK: - Root

struct HomeModel: Codable {
    /// Reserved pseudo-room id. Never a real room; marks the outside world.
    static let exteriorRoomID = "EXTERIOR"

    var schemaVersion: String
    var homeID: String
    var name: String
    var floors: [Floor]
    var stairs: [Stairs]
    var profiles: [Profile]
    var meta: Meta

    enum CodingKeys: String, CodingKey {
        case name, floors, stairs, profiles, meta
        case schemaVersion = "schema_version"
        case homeID = "home_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        homeID = try c.decode(String.self, forKey: .homeID)
        name = try c.decode(String.self, forKey: .name)
        floors = try c.decode([Floor].self, forKey: .floors)
        stairs = try c.decodeIfPresent([Stairs].self, forKey: .stairs) ?? []
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        meta = try c.decode(Meta.self, forKey: .meta)
    }

    /// Floors bottom-to-top. Level is the authoritative vertical ordering, not array order.
    var floorsByLevel: [Floor] { floors.sorted { $0.level < $1.level } }

    func room(withID id: String) -> Room? {
        for floor in floors {
            if let match = floor.rooms.first(where: { $0.id == id }) { return match }
        }
        return nil
    }
}
