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
    var peril: String? // "fire", "tornado", "earthquake"
    var constraints: RoutingConstraints
    var profile_id: String?
    var rooms: [RoomRoutePlan]
    var bottlenecks: [Bottleneck]

    private enum CodingKeys: String, CodingKey {
        case home_id, home_name, peril, constraints, profile_id, rooms, bottlenecks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        home_id = try container.decode(String.self, forKey: .home_id)
        home_name = try container.decode(String.self, forKey: .home_name)
        peril = try container.decodeIfPresent(String.self, forKey: .peril) ?? "fire"
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
    var cover_object_id: String?
    var findings: [RouteFinding]

    var id: String { room_id }

    private enum CodingKeys: String, CodingKey {
        case room_id, room_name, floor_id, primary, secondary, cover_object_id, findings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        room_id = try container.decode(String.self, forKey: .room_id)
        room_name = try container.decode(String.self, forKey: .room_name)
        floor_id = try container.decode(String.self, forKey: .floor_id)
        primary = try container.decodeIfPresent(Route.self, forKey: .primary)
        secondary = try container.decodeIfPresent(Route.self, forKey: .secondary)
        cover_object_id = try container.decodeIfPresent(String.self, forKey: .cover_object_id)
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

/// Tolerant for the same reason as `RouteFinding.FindingKind`: waypoints are nested inside
/// RoutePlan, so an unrecognized kind would fail the whole plan and render no routes.
/// `path` itself arrived mid-project in the v1.1 revamp — evidence that this list grows.
enum WaypointKind: String, Codable {
    case room, opening, stair, exterior
    /// v1.1 revamp: an intermediate within-room point where the leg curves
    /// around an object; `node_id` is the opening the leg approaches.
    case path
    /// Newer than this build. The waypoint keeps its coordinates, so the leg still
    /// draws — only kind-specific decoration is skipped.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WaypointKind(rawValue: raw) ?? .unknown
    }
}

/// The engine's warning payload — the ONLY source for the S2.3 warning badges. The client
/// renders these verbatim and never derives its own egress judgments.
struct RouteFinding: Codable, Equatable {
    var kind: FindingKind
    var room_id: String
    var detail: String
    /// Objects the server blamed for a `blocked_opening`, so the app can point at the
    /// thing to move. Defaulted rather than optional: the server omits it for every
    /// other finding kind, and an empty list is the honest reading of "nothing blamed".
    var object_ids: [String] = []
    var citation: String?

    private enum CodingKeys: String, CodingKey {
        case kind, room_id, detail, object_ids, citation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(FindingKind.self, forKey: .kind)
        room_id = try container.decode(String.self, forKey: .room_id)
        detail = try container.decode(String.self, forKey: .detail)
        object_ids = try container.decodeIfPresent([String].self, forKey: .object_ids) ?? []
        citation = try container.decodeIfPresent(String.self, forKey: .citation)
    }

    init(kind: FindingKind, room_id: String, detail: String, object_ids: [String] = [], citation: String? = nil) {
        self.kind = kind
        self.room_id = room_id
        self.detail = detail
        self.object_ids = object_ids
        self.citation = citation
    }

    /// Tolerant on purpose. This enum is nested inside RoutePlan, so a kind this build
    /// has never heard of would fail the WHOLE plan decode and the app would render no
    /// routes at all — a worse outcome than one unlabelled warning badge. This is
    /// exactly what let `narrows_route` be added server-side without stranding older
    /// builds: they render it as `.unknown` with the engine's own `detail` intact
    /// rather than dropping the whole plan. Precedent: ChecklistCategory,
    /// decisions.md 2026-08-02.
    enum FindingKind: String, Codable {
        case no_secondary_egress
        case no_viable_route
        case no_viable_safe_room
        case no_cover_in_room
        /// v1.1 revamp: an object blocks a doorway from inside this room — there is
        /// no path to it at all.
        case blocked_opening
        /// The doorway is still reachable, but the way to it squeezes below the width
        /// a door needs to be comfortable in the dark. Strictly milder than
        /// `blocked_opening`, and disjoint from it: the engine only emits this where
        /// the code-clearance path succeeded.
        case narrows_route
        /// A kind added server-side after this build shipped. `detail` is written by the
        /// engine and stays readable, so the badge degrades to "unlabelled", not "absent".
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = FindingKind(rawValue: raw) ?? .unknown
        }
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
    var peril: String?
    var constraints: RoutingConstraints?
    var profile_id: String?

    private enum CodingKeys: String, CodingKey {
        case home, peril, constraints, profile_id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(home, forKey: .home)
        try container.encodeIfPresent(peril, forKey: .peril)
        try container.encodeIfPresent(constraints, forKey: .constraints)
        try container.encodeIfPresent(profile_id, forKey: .profile_id)
    }
}
