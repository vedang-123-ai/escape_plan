// RoutePlan.swift
// Swift mirror of the S1.2 /routes contract (backend/app/routing/plan.py, request model in
// backend/app/main.py) — an API response, not the homemodel schema. Field names intentionally
// stay snake_case to match the backend exactly, like HomeModel.swift and ScoreModels.swift —
// see .claude/rules/languages/swift.md.
//
// The client never computes or approximates a route: the deterministic Python engine is the
// only router. This file only describes what the server sends back.
//
// Fields the backend defaults (`findings`, `bottlenecks`, the S3.4 penalty constraints) get
// lenient decoding so the committed docs/route-samples/*.routeplan.json — written before
// S3.4 added the penalty fields — still decode.

import Foundation

struct RoutePlan: Codable, Equatable {
    var home_id: String
    var home_name: String
    var constraints: RoutingConstraints
    var profile_id: String?
    var rooms: [RoomRoutePlan]
    var bottlenecks: [Bottleneck]

    private enum CodingKeys: String, CodingKey {
        case home_id, home_name, constraints, profile_id, rooms, bottlenecks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        home_id = try container.decode(String.self, forKey: .home_id)
        home_name = try container.decode(String.self, forKey: .home_name)
        constraints = try container.decode(RoutingConstraints.self, forKey: .constraints)
        profile_id = try container.decodeIfPresent(String.self, forKey: .profile_id)
        rooms = try container.decode([RoomRoutePlan].self, forKey: .rooms)
        bottlenecks = try container.decodeIfPresent([Bottleneck].self, forKey: .bottlenecks) ?? []
    }
}

struct RoutingConstraints: Codable, Equatable {
    var avoid_stairs: Bool
    var avoid_windows: Bool
    var max_sill_height_m: Double?
    var stair_penalty_m: Double?
    var window_penalty_m: Double?

    init(avoid_stairs: Bool = false,
         avoid_windows: Bool = false,
         max_sill_height_m: Double? = nil,
         stair_penalty_m: Double? = nil,
         window_penalty_m: Double? = nil) {
        self.avoid_stairs = avoid_stairs
        self.avoid_windows = avoid_windows
        self.max_sill_height_m = max_sill_height_m
        self.stair_penalty_m = stair_penalty_m
        self.window_penalty_m = window_penalty_m
    }
}

struct RoomRoutePlan: Codable, Equatable, Identifiable {
    var room_id: String
    var room_name: String
    var floor_id: String
    var primary: Route?
    var secondary: Route?
    var findings: [RouteFinding]

    var id: String { room_id }

    private enum CodingKeys: String, CodingKey {
        case room_id, room_name, floor_id, primary, secondary, findings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        room_id = try container.decode(String.self, forKey: .room_id)
        room_name = try container.decode(String.self, forKey: .room_name)
        floor_id = try container.decode(String.self, forKey: .floor_id)
        primary = try container.decodeIfPresent(Route.self, forKey: .primary)
        secondary = try container.decodeIfPresent(Route.self, forKey: .secondary)
        findings = try container.decodeIfPresent([RouteFinding].self, forKey: .findings) ?? []
    }
}

struct Route: Codable, Equatable {
    var waypoints: [Waypoint]
    var length_m: Double
    var uses_stairs: Bool
    var uses_window: Bool
    var exit_id: String
}

/// One point of a route, in floor-local plan meters (2D — height comes from the floor).
/// A floor crossing is two consecutive `stair` waypoints sharing node_id and x/y but with
/// different floor_id.
struct Waypoint: Codable, Equatable {
    var x: Double
    var y: Double
    var floor_id: String
    var node_id: String
    var kind: WaypointKind
}

enum WaypointKind: String, Codable {
    case room, opening, stair, exterior
    /// v1.1 revamp: an intermediate within-room point where the leg curves
    /// around an object; `node_id` is the opening the leg approaches.
    case path
}

/// The engine's warning payload — the ONLY source for the S2.3 warning badges. The client
/// renders these verbatim and never derives its own egress judgments.
struct RouteFinding: Codable, Equatable {
    var kind: FindingKind
    var room_id: String
    var detail: String

    enum FindingKind: String, Codable {
        case no_secondary_egress
        case no_viable_route
        /// v1.1 revamp: an object blocks a doorway (or narrows its approach
        /// below the egress clearance) from inside this room.
        case blocked_opening
    }
}

struct Bottleneck: Codable, Equatable {
    var opening_id: String
    var disconnected_room_ids: [String]
}

// MARK: - Request

/// POST /routes body. `constraints` and `profile_id` are mutually exclusive server-side
/// (both → 422), so nil values are omitted from the JSON entirely rather than sent as null.
struct RoutesRequest: Encodable {
    var home: HomeModel
    var constraints: RoutingConstraints?
    var profile_id: String?

    private enum CodingKeys: String, CodingKey {
        case home, constraints, profile_id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(home, forKey: .home)
        try container.encodeIfPresent(constraints, forKey: .constraints)
        try container.encodeIfPresent(profile_id, forKey: .profile_id)
    }
}
