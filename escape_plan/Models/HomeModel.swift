// HomeModel.swift
// Swift mirror of schema/homemodel.schema.json v2.0 (the project's one contract).
// Field names, enums, and optionality intentionally match the JSON schema / backend/app/models.py
// exactly rather than adopting Swift naming conventions — see .claude/rules/languages/swift.md.
//
// Fields the schema marks `"default": []` (HomeModel.stairs/profiles, Floor.openings,
// Profile.tags) get custom decoding so a document that omits the key still decodes; every
// committed fixture includes the key explicitly today, but this keeps the mirror honest about
// the schema's actual optionality.

import Foundation

/// Reserved pseudo-room id: an opening with room_ids [room, "EXTERIOR"] is an exit.
let EXTERIOR_ID = "EXTERIOR"

struct WallSegmentRef: Codable, Equatable {
    var room_id: String
    var edge_index: Int
    var t0: Double
    var t1: Double
}

struct EgressAssessment: Codable, Equatable {
    var viable: Bool
    var reasons: [String]

    private enum CodingKeys: String, CodingKey { case viable, reasons }

    init(viable: Bool, reasons: [String] = []) {
        self.viable = viable
        self.reasons = reasons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viable = try container.decode(Bool.self, forKey: .viable)
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
    }
}

struct Room: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var type: RoomType
    var polygon: Polygon
    var source: Source
    var confidence: Double?
}

struct Opening: Codable, Equatable, Identifiable {
    var id: String
    var kind: OpeningKind
    var room_ids: [String]
    var wall_segment: WallSegmentRef
    var width_m: Double
    var height_m: Double
    var sill_height_m: Double
    var egress: EgressAssessment?
    var source: Source
    var confidence: Double?

    var isExit: Bool { room_ids.contains(EXTERIOR_ID) }
}

/// A large object as a rotated box primitive (v1.1). Rendered as a prism; treated as an
/// obstacle by within-room routing. No room_id on purpose — containment is derived
/// geometrically, so moving a room can never dangle an object reference.
struct FloorObject: Codable, Equatable, Identifiable {
    var id: String
    var category: ObjectCategory
    var center: Point
    /// Footprint [width, depth] in meters, before rotation.
    var size_m: [Double]
    var height_m: Double
    /// CCW rotation of the footprint about its center, degrees, floor-local frame.
    var rotation_deg: Double
    /// v2.0: anchored/strapped against shaking. Routing MUST ignore this — an obstacle is an
    /// obstacle whether or not it is bolted down.
    var secured: Bool
    var source: Source
    var confidence: Double?

    private enum CodingKeys: String, CodingKey {
        case id, category, center, size_m, height_m, rotation_deg, secured, source, confidence
    }

    init(id: String, category: ObjectCategory, center: Point, size_m: [Double],
         height_m: Double, rotation_deg: Double = 0, secured: Bool = false,
         source: Source, confidence: Double? = nil) {
        self.id = id
        self.category = category
        self.center = center
        self.size_m = size_m
        self.height_m = height_m
        self.rotation_deg = rotation_deg
        self.secured = secured
        self.source = source
        self.confidence = confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(ObjectCategory.self, forKey: .category)
        center = try container.decode(Point.self, forKey: .center)
        size_m = try container.decode([Double].self, forKey: .size_m)
        height_m = try container.decode(Double.self, forKey: .height_m)
        rotation_deg = try container.decodeIfPresent(Double.self, forKey: .rotation_deg) ?? 0
        secured = try container.decodeIfPresent(Bool.self, forKey: .secured) ?? false
        source = try container.decode(Source.self, forKey: .source)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
    }
}

/// A located utility shutoff or electrical panel (v2.0). A landmark, never an obstacle:
/// the routing engine does not see these. No room_id, for the same reason FloorObject has
/// none — containment is derived geometrically.
struct SafetyPoint: Codable, Equatable, Identifiable {
    var id: String
    var kind: SafetyPointKind
    var position: Point
    var source: Source
    var confidence: Double?
}

struct Floor: Codable, Equatable, Identifiable {
    var id: String
    var level: Int
    var name: String
    var height_m: Double
    var rooms: [Room]
    var openings: [Opening]
    var objects: [FloorObject]
    /// v2.0: utility shutoffs and the electrical panel on this floor.
    var safety_points: [SafetyPoint]

    private enum CodingKeys: String, CodingKey {
        case id, level, name, height_m, rooms, openings, objects, safety_points
    }

    init(id: String, level: Int, name: String, height_m: Double, rooms: [Room],
         openings: [Opening] = [], objects: [FloorObject] = [],
         safety_points: [SafetyPoint] = []) {
        self.id = id
        self.level = level
        self.name = name
        self.height_m = height_m
        self.rooms = rooms
        self.openings = openings
        self.objects = objects
        self.safety_points = safety_points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        level = try container.decode(Int.self, forKey: .level)
        name = try container.decode(String.self, forKey: .name)
        height_m = try container.decode(Double.self, forKey: .height_m)
        rooms = try container.decode([Room].self, forKey: .rooms)
        openings = try container.decodeIfPresent([Opening].self, forKey: .openings) ?? []
        objects = try container.decodeIfPresent([FloorObject].self, forKey: .objects) ?? []
        safety_points = try container.decodeIfPresent([SafetyPoint].self, forKey: .safety_points) ?? []
    }
}

struct StairEnd: Codable, Equatable {
    var floor_id: String
    var room_id: String
}

struct Stairs: Codable, Equatable, Identifiable {
    var id: String
    var from: StairEnd
    var to: StairEnd
    var footprint: Polygon
    var kind: StairKind
    var source: Source
    var confidence: Double?
}

struct Profile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var tags: [ProfileTag]
    var bedroom_room_id: String

    private enum CodingKeys: String, CodingKey {
        case id, name, tags, bedroom_room_id
    }

    init(id: String, name: String, tags: [ProfileTag] = [], bedroom_room_id: String) {
        self.id = id
        self.name = name
        self.tags = tags
        self.bedroom_room_id = bedroom_room_id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tags = try container.decodeIfPresent([ProfileTag].self, forKey: .tags) ?? []
        bedroom_room_id = try container.decode(String.self, forKey: .bedroom_room_id)
    }
}

/// Facts about the household as a unit, gathered by the S6.5 interview (v2.0).
/// Every field is optional because every interview question is skippable, and a skipped
/// question must produce the unconstrained default rather than a half-written record.
/// `tenure == nil` means "not answered" — it does not mean "own".
struct Household: Codable, Equatable {
    var tenure: Tenure?
    var existing_equipment: [EquipmentItem]

    private enum CodingKeys: String, CodingKey { case tenure, existing_equipment }

    init(tenure: Tenure? = nil, existing_equipment: [EquipmentItem] = []) {
        self.tenure = tenure
        self.existing_equipment = existing_equipment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tenure = try container.decodeIfPresent(Tenure.self, forKey: .tenure)
        existing_equipment =
            try container.decodeIfPresent([EquipmentItem].self, forKey: .existing_equipment) ?? []
    }
}

struct Meta: Codable, Equatable {
    var created: Date
    var modified: Date
    var address_optional: String?
    /// v2.0. nil = never scanned (hand-built), which is a DIFFERENT state from a stale scan
    /// and gets different treatment. Drives the rescan nudge; never reduces the score.
    var last_scanned: Date?

    init(created: Date, modified: Date, address_optional: String? = nil,
         last_scanned: Date? = nil) {
        self.created = created
        self.modified = modified
        self.address_optional = address_optional
        self.last_scanned = last_scanned
    }
}

struct HomeModel: Codable, Equatable, Identifiable {
    var schema_version: String
    var home_id: String
    var name: String
    var floors: [Floor]
    var stairs: [Stairs]
    var profiles: [Profile]
    var household: Household?
    var meta: Meta

    var id: String { home_id }

    private enum CodingKeys: String, CodingKey {
        case schema_version, home_id, name, floors, stairs, profiles, household, meta
    }

    init(
        schema_version: String,
        home_id: String,
        name: String,
        floors: [Floor],
        stairs: [Stairs] = [],
        profiles: [Profile] = [],
        household: Household? = nil,
        meta: Meta
    ) {
        self.schema_version = schema_version
        self.home_id = home_id
        self.name = name
        self.floors = floors
        self.stairs = stairs
        self.profiles = profiles
        self.household = household
        self.meta = meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema_version = try container.decode(String.self, forKey: .schema_version)
        home_id = try container.decode(String.self, forKey: .home_id)
        name = try container.decode(String.self, forKey: .name)
        floors = try container.decode([Floor].self, forKey: .floors)
        stairs = try container.decodeIfPresent([Stairs].self, forKey: .stairs) ?? []
        profiles = try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        household = try container.decodeIfPresent(Household.self, forKey: .household)
        meta = try container.decode(Meta.self, forKey: .meta)
    }
}

// MARK: - Shared coder configuration

extension HomeModel {
    /// ISO-8601. Accepts fractional seconds as well as whole ones.
    ///
    /// Every committed fixture uses whole seconds, but pydantic round-trips microseconds
    /// happily, so a backend-produced timestamp can carry them. `.iso8601` alone REJECTS
    /// those, which would surface as a decode failure on device and nowhere else. Latent
    /// until v2.0 added `meta.last_scanned` — a datetime the backend can write — so it is
    /// fixed here rather than left as a trap for whoever hits it first.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = whole.date(from: raw) ?? withFraction.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Not an ISO-8601 date-time: \(raw)")
            )
        }
        return decoder
    }

    static func encoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }
}
