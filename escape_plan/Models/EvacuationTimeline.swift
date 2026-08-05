// EvacuationTimeline.swift
// The contract between the deterministic engine and the evacuation animation.
//
// The animation is a *rendering of a computed result*, never a computation of its own. The
// engine decides who goes where and when a room becomes impassable; this file is the shape
// that decision travels in. The renderer interpolates between these numbers and invents none
// of them — the same division of labor that keeps the AI layer out of routing.
//
// Field names stay snake_case to match the backend exactly, like RoutePlan.swift and
// ScoreModels.swift — see .claude/rules/languages/swift.md.
//
// Coordinates follow the existing Waypoint convention: floor-local plan meters plus a
// floor_id. Height comes from DollhouseGeometry.floorBaseHeights(of:), exactly as
// RouteOverlay already lifts route waypoints into the scene. Nothing here is 3D, so this
// file stays pure Foundation and runs under `swift test --package-path tools/editorcore`.

import Foundation

/// One illustrative evacuation: every occupant's path through the home over time, alongside
/// the spread of the hazard they are moving away from.
///
/// `is_illustrative` is always true and is not decoration — the UI is required to show a
/// disclaimer whenever a timeline is on screen. This is a visualization of geometry and
/// assumed speeds, not a survivability prediction, and the app never implies otherwise.
struct EvacuationTimeline: Codable, Equatable {
    var home_id: String
    var profile_set_id: String?
    /// The room the hazard starts in. Always a real room id in this home.
    var origin_room_id: String
    var tracks: [OccupantTrack]
    var hazard: [HazardEvent]
    /// Wall-clock length of the whole animation, in seconds of modeled time.
    var duration_s: Double
    var is_illustrative: Bool
    /// ADDITIVE (lane B, 2026-08-05). The engine may attach the same warning payload it already
    /// attaches to a `/routes` plan — `RouteFinding` in RoutePlan.swift, identical shape, same
    /// verbatim-`detail` discipline. It is defaulted rather than optional for the reason
    /// `RouteFinding.object_ids` is: the server omits the key entirely when it has nothing to
    /// say, and an empty list is the honest reading of that. A build that predates the backend
    /// field, or a backend that predates this build, both still decode.
    var findings: [RouteFinding] = []

    private enum CodingKeys: String, CodingKey {
        case home_id, profile_set_id, origin_room_id, tracks, hazard, duration_s, is_illustrative
        case findings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        home_id = try c.decode(String.self, forKey: .home_id)
        profile_set_id = try c.decodeIfPresent(String.self, forKey: .profile_set_id)
        origin_room_id = try c.decode(String.self, forKey: .origin_room_id)
        tracks = try c.decode([OccupantTrack].self, forKey: .tracks)
        hazard = try c.decodeIfPresent([HazardEvent].self, forKey: .hazard) ?? []
        duration_s = try c.decode(Double.self, forKey: .duration_s)
        // Defaulting to true is the safe direction: a timeline that forgot to say it was
        // illustrative still gets the disclaimer.
        is_illustrative = try c.decodeIfPresent(Bool.self, forKey: .is_illustrative) ?? true
        findings = try c.decodeIfPresent([RouteFinding].self, forKey: .findings) ?? []
    }

    init(home_id: String,
         profile_set_id: String? = nil,
         origin_room_id: String,
         tracks: [OccupantTrack],
         hazard: [HazardEvent],
         duration_s: Double,
         is_illustrative: Bool = true,
         findings: [RouteFinding] = []) {
        self.home_id = home_id
        self.profile_set_id = profile_set_id
        self.origin_room_id = origin_room_id
        self.tracks = tracks
        self.hazard = hazard
        self.duration_s = duration_s
        self.is_illustrative = is_illustrative
        self.findings = findings
    }
}

/// One person's journey out, already solved. The renderer walks `steps` by time and does not
/// re-derive the path — `steps` is the engine's route, resampled with arrival times.
struct OccupantTrack: Codable, Equatable, Identifiable {
    var profile_id: String
    var profile_name: String
    /// Drives locomotion style, not routing. Routing constraints were already applied
    /// server-side via app/routing/profiles.py before these steps were produced.
    var gait: GaitKind
    var start_room_id: String
    var exit_id: String
    /// At least two steps, with strictly non-decreasing `t_s`.
    var steps: [TimedStep]
    var distance_m: Double
    /// When this occupant reaches the exterior. Equals `steps.last!.t_s`.
    var egress_time_s: Double
    var uses_stairs: Bool
    var uses_window: Bool
    /// True when the modeled hazard reaches a room on this path before the occupant clears
    /// it. The engine reports this honestly rather than quietly retiming the escape; the UI
    /// must surface it as a finding, never hide it to keep the animation comfortable.
    var overtaken_by_hazard: Bool

    var id: String { profile_id }

    private enum CodingKeys: String, CodingKey {
        case profile_id, profile_name, gait, start_room_id, exit_id, steps
        case distance_m, egress_time_s, uses_stairs, uses_window, overtaken_by_hazard
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile_id = try c.decode(String.self, forKey: .profile_id)
        profile_name = try c.decode(String.self, forKey: .profile_name)
        gait = try c.decodeIfPresent(GaitKind.self, forKey: .gait) ?? .adult
        start_room_id = try c.decode(String.self, forKey: .start_room_id)
        exit_id = try c.decode(String.self, forKey: .exit_id)
        steps = try c.decode([TimedStep].self, forKey: .steps)
        distance_m = try c.decode(Double.self, forKey: .distance_m)
        egress_time_s = try c.decode(Double.self, forKey: .egress_time_s)
        uses_stairs = try c.decodeIfPresent(Bool.self, forKey: .uses_stairs) ?? false
        uses_window = try c.decodeIfPresent(Bool.self, forKey: .uses_window) ?? false
        overtaken_by_hazard = try c.decodeIfPresent(Bool.self, forKey: .overtaken_by_hazard) ?? false
    }

    init(profile_id: String, profile_name: String, gait: GaitKind,
         start_room_id: String, exit_id: String, steps: [TimedStep],
         distance_m: Double, egress_time_s: Double,
         uses_stairs: Bool = false, uses_window: Bool = false,
         overtaken_by_hazard: Bool = false) {
        self.profile_id = profile_id
        self.profile_name = profile_name
        self.gait = gait
        self.start_room_id = start_room_id
        self.exit_id = exit_id
        self.steps = steps
        self.distance_m = distance_m
        self.egress_time_s = egress_time_s
        self.uses_stairs = uses_stairs
        self.uses_window = uses_window
        self.overtaken_by_hazard = overtaken_by_hazard
    }
}

/// A route waypoint with the time the occupant reaches it. Geometry matches `Waypoint`
/// in RoutePlan.swift so the same DollhouseGeometry lift applies.
struct TimedStep: Codable, Equatable {
    var x: Double
    var y: Double
    var floor_id: String
    var t_s: Double
    /// Mirrors `WaypointKind` so the renderer can decorate a stair crossing or a window
    /// climb-out differently from ordinary walking.
    var kind: String
}

/// How a figure moves, for animation only. Deliberately separate from the routing tag set:
/// two people can route identically and still move differently on screen.
///
/// Tolerant decoding for the same reason as `WaypointKind` — an unrecognized gait should
/// degrade to a walking figure, not fail the whole timeline.
enum GaitKind: String, Codable {
    case adult, child, elderly, wheelchair, pet
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GaitKind(rawValue: raw) ?? .unknown
    }
}

/// When the modeled hazard makes a room impassable. Rooms absent from this list stay clear
/// for the whole timeline.
struct HazardEvent: Codable, Equatable {
    var room_id: String
    var floor_id: String
    /// Seconds from ignition until this room is modeled as untenable. The origin room is 0.
    var untenable_at_s: Double
}
