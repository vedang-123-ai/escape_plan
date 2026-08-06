//  MockTimeline.swift
//  Renderer/Evacuation
//
//  DEBUG-ONLY scaffolding for developing the renderer before (or without) a live /evacuate
//  response. This file does not find an escape route. It accepts RoutePlan waypoints already
//  produced by the deterministic router and attaches illustrative demo timing to them.
//
//  Its hazard wave is equally explicit about being a mock: fixed diagram steps across authored
//  room connections, with no claim about flame, smoke, ventilation, door position, or real-world
//  tenability. Release UI must load EvacuationTimeline from the backend instead. The generic
//  HomeModel/RoutePlan inputs let the same helper exercise bungalow, apartment, twostory, and
//  newly authored fixtures without fixture IDs or hand-coded paths.

#if DEBUG

import Foundation

enum MockTimeline {

    struct Configuration {
        /// These values mirror the backend's animation defaults so switching from a mock to an
        /// endpoint response does not radically retime the renderer. They are not safety data.
        var roomDiagramStep_s: Double
        var stairDiagramStep_s: Double
        var stairTravelDistance_m: Double
        var stairSpeedFactor: Double
        var doorExitDuration_s: Double
        var windowExitDuration_s: Double

        init(roomDiagramStep_s: Double = 45,
             stairDiagramStep_s: Double = 30,
             stairTravelDistance_m: Double = 4,
             stairSpeedFactor: Double = 0.5,
             doorExitDuration_s: Double = 2,
             windowExitDuration_s: Double = 15) {
            self.roomDiagramStep_s = roomDiagramStep_s
            self.stairDiagramStep_s = stairDiagramStep_s
            self.stairTravelDistance_m = stairTravelDistance_m
            self.stairSpeedFactor = stairSpeedFactor
            self.doorExitDuration_s = doorExitDuration_s
            self.windowExitDuration_s = windowExitDuration_s
        }

        static let `default` = Configuration()
    }

    /// Optional explicit occupants for previews. Omit this to use the home's profiles, or —
    /// matching the backend's demo affordance — one adult per room when a fixture has none.
    struct OccupantSeed: Equatable {
        var id: String
        var name: String
        var startRoomID: String
        var gait: GaitKind

        init(id: String, name: String, startRoomID: String, gait: GaitKind = .adult) {
            self.id = id
            self.name = name
            self.startRoomID = startRoomID
            self.gait = gait
        }
    }

    struct Result {
        let timeline: EvacuationTimeline
        /// Missing route plans and malformed references are reported, never replaced by an
        /// invented straight line. A result may therefore honestly contain fewer tracks.
        let issues: [String]
    }

    enum BuildError: LocalizedError, Equatable {
        case homeHasNoRooms
        case unknownOriginRoom(String)

        var errorDescription: String? {
            switch self {
            case .homeHasNoRooms:
                return "A mock evacuation needs at least one authored room."
            case .unknownOriginRoom(let id):
                return "The mock hazard origin '\(id)' is not a room in this home."
            }
        }
    }

    /// Builds an illustrative timeline by timing existing primary-route waypoints.
    ///
    /// `routePlans` may contain an unscoped plan (`profile_id == nil`) for all occupants, or
    /// profile-specific plans. A profile-specific plan is never reused for a different profile.
    /// If `originRoomID` is omitted, previews prefer the first authored kitchen and then the
    /// first authored room; callers demonstrating a particular fire should always pass it.
    static func make(home: HomeModel,
                     routePlans: [RoutePlan],
                     originRoomID: String? = nil,
                     profileSetID: String? = nil,
                     occupants explicitOccupants: [OccupantSeed]? = nil,
                     configuration: Configuration = .default) throws -> Result {
        let roomRecords = home.floors.flatMap { floor in
            floor.rooms.map { (room: $0, floorID: floor.id) }
        }
        guard !roomRecords.isEmpty else { throw BuildError.homeHasNoRooms }

        let knownRoomIDs = Set(roomRecords.map { $0.room.id })
        let selectedOrigin = originRoomID
            ?? roomRecords.first(where: { $0.room.type == .kitchen })?.room.id
            ?? roomRecords[0].room.id
        guard knownRoomIDs.contains(selectedOrigin) else {
            throw BuildError.unknownOriginRoom(selectedOrigin)
        }

        var issues: [String] = []
        let compatiblePlans = routePlans.filter { plan in
            if plan.home_id == home.home_id { return true }
            issues.append("route plan for '\(plan.home_id)' was not used with home '\(home.home_id)'")
            return false
        }
        let defaultPlan = compatiblePlans.first(where: { $0.profile_id == nil })
        let occupants = explicitOccupants ?? occupantSeeds(for: home)
        let knownFloorIDs = Set(home.floors.map(\.id))

        var tracks: [OccupantTrack] = []
        tracks.reserveCapacity(occupants.count)
        for occupant in occupants {
            guard knownRoomIDs.contains(occupant.startRoomID) else {
                issues.append("mock occupant '\(occupant.name)' references unknown room '\(occupant.startRoomID)'")
                continue
            }
            let plan = compatiblePlans.first(where: { $0.profile_id == occupant.id }) ?? defaultPlan
            guard let plan else {
                issues.append("no unscoped or profile-specific route plan exists for '\(occupant.name)'")
                continue
            }
            guard let roomPlan = plan.rooms.first(where: { $0.room_id == occupant.startRoomID }),
                  let route = roomPlan.primary else {
                issues.append("the router supplied no primary route from '\(occupant.startRoomID)' for '\(occupant.name)'")
                continue
            }
            guard route.waypoints.count >= 2 else {
                issues.append("the primary route for '\(occupant.name)' has fewer than two waypoints")
                continue
            }
            if occupant.gait == .wheelchair && (route.uses_stairs || route.uses_window) {
                // Never turn an unscoped fixture plan into visual "proof" that a wheelchair
                // user can take stairs or climb through a window. The mock cannot re-route;
                // only a compatible profile-specific plan from the engine can add this track.
                issues.append("the supplied route for wheelchair occupant '\(occupant.name)' "
                              + "uses \(route.uses_stairs ? "stairs" : "a window"); no mock track was fabricated")
                continue
            }
            let unknownFloors = Set(route.waypoints.map(\.floor_id)).subtracting(knownFloorIDs)
            guard unknownFloors.isEmpty else {
                issues.append("the primary route for '\(occupant.name)' references unknown floor(s): "
                              + unknownFloors.sorted().joined(separator: ", "))
                continue
            }

            let timed = time(route: route, gait: occupant.gait, configuration: configuration)
            guard let egressTime = timed.steps.last?.t_s else { continue }
            tracks.append(OccupantTrack(
                profile_id: occupant.id,
                profile_name: occupant.name,
                gait: occupant.gait,
                start_room_id: occupant.startRoomID,
                exit_id: route.exit_id,
                steps: timed.steps,
                distance_m: rounded(timed.distance_m, places: 3),
                egress_time_s: egressTime,
                uses_stairs: route.uses_stairs,
                uses_window: route.uses_window,
                // A renderer mock cannot honestly re-run the backend's hazard-aware router.
                overtaken_by_hazard: false
            ))
        }

        let hazard = mockHazardEvents(
            home: home,
            originRoomID: selectedOrigin,
            configuration: configuration
        )
        let duration = max(
            tracks.map(\.egress_time_s).max() ?? 0,
            hazard.map(\.untenable_at_s).max() ?? 0
        )
        let timeline = EvacuationTimeline(
            home_id: home.home_id,
            profile_set_id: profileSetID,
            origin_room_id: selectedOrigin,
            tracks: tracks,
            hazard: hazard,
            duration_s: rounded(duration, places: 2),
            is_illustrative: true,
            findings: []
        )
        return Result(timeline: timeline, issues: issues)
    }

    /// Convenience for the common fixture case: one unscoped route sample such as
    /// docs/route-samples/{bungalow,apartment,twostory}.routeplan.json.
    static func make(home: HomeModel,
                     routePlan: RoutePlan,
                     originRoomID: String? = nil,
                     configuration: Configuration = .default) throws -> Result {
        try make(home: home, routePlans: [routePlan], originRoomID: originRoomID,
                 configuration: configuration)
    }

    // MARK: - Occupants and gait

    private static func occupantSeeds(for home: HomeModel) -> [OccupantSeed] {
        if !home.profiles.isEmpty {
            return home.profiles.map { profile in
                OccupantSeed(id: profile.id, name: profile.name,
                             startRoomID: profile.bedroom_room_id,
                             gait: gait(for: profile))
            }
        }

        // Fresh scans and bungalow.json have no profiles. One adult per room makes the mock
        // exercise overlaps and camera framing without writing anything back to HomeModel.
        return home.floors.flatMap { floor in
            floor.rooms.map { room in
                OccupantSeed(id: "occupant.\(room.id)", name: room.name,
                             startRoomID: room.id, gait: .adult)
            }
        }
    }

    private static func gait(for profile: Profile) -> GaitKind {
        // Strictest/most visually specific tag wins, matching the endpoint contract.
        if profile.tags.contains(.mobility_limited) { return .wheelchair }
        if profile.tags.contains(.pet) { return .pet }
        if profile.tags.contains(.child) { return .child }
        if profile.tags.contains(.elderly) { return .elderly }
        return .adult
    }

    private static func speed(for gait: GaitKind) -> Double {
        switch gait {
        case .adult, .unknown: return 1.20
        case .child: return 0.90
        case .elderly: return 0.75
        case .wheelchair: return 0.85
        case .pet: return 1.10
        }
    }

    // MARK: - Timing handed route geometry (never selecting a path)

    private static func time(route: Route, gait: GaitKind,
                             configuration: Configuration)
        -> (steps: [TimedStep], distance_m: Double) {
        let movementSpeed = max(speed(for: gait), 0.01)
        let stairDuration = max(configuration.stairTravelDistance_m, 0)
            / max(movementSpeed * configuration.stairSpeedFactor, 0.01)
        let exitDuration = route.uses_window
            ? max(configuration.windowExitDuration_s, 0)
            : max(configuration.doorExitDuration_s, 0)

        var elapsed = 0.0
        var distance = 0.0
        var result: [TimedStep] = []
        result.reserveCapacity(route.waypoints.count)

        for (index, waypoint) in route.waypoints.enumerated() {
            if index > 0 {
                let previous = route.waypoints[index - 1]
                if waypoint.kind == .exterior {
                    // The opening and exterior points intentionally share coordinates; this
                    // semantic segment is what makes a door crossing and window climb distinct.
                    elapsed += exitDuration
                } else if waypoint.floor_id != previous.floor_id {
                    elapsed += stairDuration
                    distance += max(configuration.stairTravelDistance_m, 0)
                } else {
                    let dx = waypoint.x - previous.x
                    let dy = waypoint.y - previous.y
                    let leg = (dx * dx + dy * dy).squareRoot()
                    if leg.isFinite {
                        distance += leg
                        elapsed += leg / movementSpeed
                    }
                }
            }
            result.append(TimedStep(
                x: rounded(waypoint.x, places: 4),
                y: rounded(waypoint.y, places: 4),
                floor_id: waypoint.floor_id,
                t_s: rounded(elapsed, places: 2),
                kind: timedStepKind(for: waypoint.kind)
            ))
        }
        return (result, distance)
    }

    private static func timedStepKind(for kind: WaypointKind) -> String {
        switch kind {
        case .room: return "room"
        case .opening: return "opening"
        case .stair: return "stair"
        case .exterior: return "exterior"
        case .path, .unknown:
            // Unknown display-only waypoint kinds retain their geometry and degrade to an
            // ordinary within-room path point instead of poisoning the whole mock timeline.
            return "path"
        }
    }

    // MARK: - Abstract hazard schedule

    private struct Neighbor {
        let roomID: String
        let delay_s: Double
    }

    private static func mockHazardEvents(home: HomeModel,
                                         originRoomID: String,
                                         configuration: Configuration) -> [HazardEvent] {
        let roomToFloor = Dictionary(uniqueKeysWithValues: home.floors.flatMap { floor in
            floor.rooms.map { ($0.id, floor.id) }
        })
        var adjacency: [String: [Neighbor]] = [:]

        func connect(_ a: String, _ b: String, delay: Double) {
            guard a != b, roomToFloor[a] != nil, roomToFloor[b] != nil else { return }
            adjacency[a, default: []].append(Neighbor(roomID: b, delay_s: max(delay, 0)))
            adjacency[b, default: []].append(Neighbor(roomID: a, delay_s: max(delay, 0)))
        }

        for floor in home.floors {
            for opening in floor.openings {
                let rooms = opening.room_ids.filter { $0 != EXTERIOR_ID && roomToFloor[$0] != nil }
                guard rooms.count >= 2 else { continue }
                for first in 0..<(rooms.count - 1) {
                    for second in (first + 1)..<rooms.count {
                        connect(rooms[first], rooms[second], delay: configuration.roomDiagramStep_s)
                    }
                }
            }
        }
        for stair in home.stairs {
            connect(stair.from.room_id, stair.to.room_id,
                    delay: configuration.stairDiagramStep_s)
        }

        // Tiny deterministic Dijkstra over room topology. This chooses no occupant path; it
        // merely orders a DEBUG-only area wash across connections authored in HomeModel.
        var arrival: [String: Double] = [originRoomID: 0]
        var visited = Set<String>()
        while let current = arrival
            .filter({ !visited.contains($0.key) })
            .min(by: { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value < rhs.value
            }) {
            visited.insert(current.key)
            let neighbors = (adjacency[current.key] ?? []).sorted {
                $0.roomID == $1.roomID ? $0.delay_s < $1.delay_s : $0.roomID < $1.roomID
            }
            for neighbor in neighbors {
                let candidate = current.value + neighbor.delay_s
                if candidate < arrival[neighbor.roomID, default: .infinity] {
                    arrival[neighbor.roomID] = candidate
                }
            }
        }

        return arrival.compactMap { roomID, seconds in
            guard let floorID = roomToFloor[roomID] else { return nil }
            return HazardEvent(room_id: roomID, floor_id: floorID,
                               untenable_at_s: rounded(seconds, places: 2))
        }.sorted {
            $0.untenable_at_s == $1.untenable_at_s
                ? $0.room_id < $1.room_id
                : $0.untenable_at_s < $1.untenable_at_s
        }
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        guard value.isFinite else { return 0 }
        let scale = pow(10.0, Double(max(0, places)))
        return (value * scale).rounded() / scale
    }
}

#endif
