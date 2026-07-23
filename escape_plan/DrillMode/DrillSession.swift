//  DrillSession.swift
//  escape_plan — S4.2 drill mode
//
//  Pure state machine for the guided walkthrough: turns a profile's primary `Route`
//  (server truth from /routes — never computed here) into an ordered list of drill steps,
//  and tracks where the user is. No UI, no SceneKit — testable as plain Foundation.
//
//  The `.move` steps carry a two-waypoint slice of the engine's route so the UI can reuse
//  `RouteOverlay.startTour` per segment. Those slices are camera paths over the fetched
//  route's own waypoints, not new routes: nothing here computes, extends, or invents a route.

import Foundation

enum DrillStep: Equatable {
    /// The drill starts in the profile's bedroom.
    case start(roomName: String)
    /// Fly the camera along `segment` (two consecutive route waypoints on one floor) and show
    /// the instruction for arriving at a waypoint of `destinationKind`.
    case move(segment: Route, destinationKind: WaypointKind)
    /// A floor crossing: two consecutive `stair` waypoints sharing node_id with different
    /// floor_ids. Zero-length in plan space, so there is no camera flight — card only.
    case stairs(fromFloorID: String, toFloorID: String)
    /// Terminal card: outside meeting place + "mark plan as practiced".
    case meetingPoint
}

struct DrillSession: Equatable {
    let profile: Profile
    let route: Route
    let steps: [DrillStep]
    private(set) var index: Int = 0

    /// nil when the route has fewer than two waypoints — nothing to walk through.
    init?(profile: Profile, route: Route, startRoomName: String) {
        guard route.waypoints.count >= 2 else { return nil }
        self.profile = profile
        self.route = route
        self.steps = Self.deriveSteps(from: route, startRoomName: startRoomName)
    }

    var currentStep: DrillStep { steps[index] }
    var isAtStart: Bool { index == 0 }
    var isAtEnd: Bool { index == steps.count - 1 }
    /// 1-based, for "Step 2 of 7" UI copy.
    var stepNumber: Int { index + 1 }
    var stepCount: Int { steps.count }

    mutating func advance() {
        guard !isAtEnd else { return }
        index += 1
    }

    mutating func back() {
        guard !isAtStart else { return }
        index -= 1
    }

    // MARK: - Step derivation

    private static func deriveSteps(from route: Route, startRoomName: String) -> [DrillStep] {
        var steps: [DrillStep] = [.start(roomName: startRoomName)]
        let waypoints = route.waypoints
        for i in 0..<(waypoints.count - 1) {
            let from = waypoints[i]
            let to = waypoints[i + 1]
            if from.kind == .stair, to.kind == .stair,
               from.node_id == to.node_id, from.floor_id != to.floor_id {
                steps.append(.stairs(fromFloorID: from.floor_id, toFloorID: to.floor_id))
            } else {
                // length_m is unused by the camera tour (it re-measures the path itself);
                // stairs/window flags and exit id are inherited so the slice stays honest
                // about the route it came from.
                let segment = Route(waypoints: [from, to],
                                    length_m: 0,
                                    uses_stairs: route.uses_stairs,
                                    uses_window: route.uses_window,
                                    exit_id: route.exit_id)
                steps.append(.move(segment: segment, destinationKind: to.kind))
            }
        }
        steps.append(.meetingPoint)
        return steps
    }
}
