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
    case start(roomName: String)
    case dropCoverHold(coverObjectName: String?, noCoverFinding: String?)
    case aftershockEvacuate
    case move(segment: Route, destinationKind: WaypointKind)
    case stairs(fromFloorID: String, toFloorID: String)
    case drillComplete(peril: String)
}

struct DrillSession: Equatable {
    let profile: Profile
    let route: Route
    let peril: String
    let steps: [DrillStep]
    private(set) var index: Int = 0

    init?(profile: Profile, route: Route, startRoomName: String, peril: String = "fire", coverObjectName: String? = nil, noCoverFinding: String? = nil) {
        guard route.waypoints.count >= 2 else { return nil }
        self.profile = profile
        self.route = route
        self.peril = peril
        self.steps = Self.deriveSteps(from: route, startRoomName: startRoomName, peril: peril, coverObjectName: coverObjectName, noCoverFinding: noCoverFinding)
    }

    var currentStep: DrillStep { steps[index] }
    var isAtStart: Bool { index == 0 }
    var isAtEnd: Bool { index == steps.count - 1 }
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

    private static func deriveSteps(from route: Route, startRoomName: String, peril: String, coverObjectName: String?, noCoverFinding: String?) -> [DrillStep] {
        var steps: [DrillStep] = [.start(roomName: startRoomName)]
        
        if peril == "earthquake" {
            steps.append(.dropCoverHold(coverObjectName: coverObjectName, noCoverFinding: noCoverFinding))
            steps.append(.aftershockEvacuate)
        }
        
        let waypoints = route.waypoints
        for i in 0..<(waypoints.count - 1) {
            let from = waypoints[i]
            let to = waypoints[i + 1]
            if from.kind == .stair, to.kind == .stair,
               from.node_id == to.node_id, from.floor_id != to.floor_id {
                steps.append(.stairs(fromFloorID: from.floor_id, toFloorID: to.floor_id))
            } else {
                let segment = Route(waypoints: [from, to],
                                    length_m: 0,
                                    uses_stairs: route.uses_stairs,
                                    uses_window: route.uses_window,
                                    exit_id: route.exit_id)
                steps.append(.move(segment: segment, destinationKind: to.kind))
            }
        }
        steps.append(.drillComplete(peril: peril))
        return steps
    }
}
