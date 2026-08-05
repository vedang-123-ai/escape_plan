//  RouteNarration.swift
//  escape_plan — Export module
//
//  Turns a route the ENGINE computed into ordered, plain-English steps.
//
//  PURE ON PURPOSE. Foundation only: no UIKit, no SwiftUI, no SceneKit, no I/O, no globals.
//  Same input → same output. That is not incidental tidiness — this type has two callers by
//  design:
//
//    1. the printable PDF's per-person summary (this module), and
//    2. the VoiceOver alternative for the 3D dollhouse — a blind user cannot read a glowing
//       line, so the scene's accessibility text IS this narration.
//
//  Anything that needs "describe this route in words" must come here rather than growing a
//  second, drifting copy. Keep it free of presentation concerns (fonts, colours, layout).
//
//  It never invents a route: every sentence is derived from waypoints the deterministic
//  Python engine returned, plus names looked up in the HomeModel. A route the engine did not
//  compute produces no steps at all — it produces the engine's own finding, verbatim.

import Foundation

/// Which of the two routes the engine computes for a room is being described.
enum RouteKind: String, Equatable, CaseIterable {
    case primary
    case secondary

    /// Wording used in print and in speech.
    var displayName: String {
        switch self {
        case .primary: return "Primary route"
        case .secondary: return "Backup route"
        }
    }

    /// How the route is drawn on the printed plan — spoken aloud so the greyscale
    /// encoding is explained to someone who cannot see it either.
    var strokeDescription: String {
        switch self {
        case .primary: return "solid line"
        case .secondary: return "dashed line"
        }
    }
}

/// One numbered instruction. `number` matches the marker printed on the plan drawing.
struct NarrationStep: Equatable, Identifiable {
    var number: Int
    var text: String

    var id: Int { number }

    /// "1. Leave the Bedroom through the door into the Hall."
    var numbered: String { "\(number). \(text)" }
}

/// A complete spoken/printed description of one room's route.
struct RouteNarrative: Equatable {
    var roomID: String
    var roomName: String
    var kind: RouteKind
    /// Ordered instructions. Empty only when the engine returned no route.
    var steps: [NarrationStep]
    /// "About 10.0 m · uses the stairs" — factual, straight off the engine's Route.
    var summary: String
    /// Factual caveats derived from the model (window sill height, floor changes).
    var notes: [String]

    /// One string for VoiceOver / a screen reader: heading, then the steps in order.
    var spokenText: String {
        var parts: [String] = ["\(kind.displayName) from the \(roomName).", summary + "."]
        parts.append(contentsOf: steps.map(\.text))
        parts.append(contentsOf: notes)
        return parts.joined(separator: " ")
    }
}

/// Ordered plain-English steps for engine-computed routes.
///
/// Entry points, in the order you probably want them:
///
///     RouteNarration.narrate(room:in:kind:meetingPoint:)   -> RouteNarrative?
///     RouteNarration.narrate(route:from:in:kind:meetingPoint:) -> RouteNarrative
///     RouteNarration.sentences(for:from:in:meetingPoint:)  -> [String]
///     RouteNarration.spokenDescription(room:in:meetingPoint:) -> String
///     RouteNarration.findingSentence(_:in:)                -> String
///     RouteNarration.summaryLine(for:)                     -> String
///
enum RouteNarration {

    // MARK: - Public API

    /// Narrates one of a room's two routes, or nil when the engine did not compute it.
    /// `meetingPoint` (the user's free-text answer, e.g. "the big oak across the street")
    /// becomes a final step when non-empty; it is never invented.
    static func narrate(room: RoomRoutePlan,
                        in home: HomeModel,
                        kind: RouteKind,
                        meetingPoint: String? = nil) -> RouteNarrative? {
        let route: Route?
        switch kind {
        case .primary: route = room.primary
        case .secondary: route = room.secondary
        }
        guard let route else { return nil }
        return narrate(route: route,
                       from: room.room_id,
                       fallbackRoomName: room.room_name,
                       in: home,
                       kind: kind,
                       meetingPoint: meetingPoint)
    }

    /// Narrates an engine `Route` starting in `roomID`.
    static func narrate(route: Route,
                        from roomID: String,
                        fallbackRoomName: String? = nil,
                        in home: HomeModel,
                        kind: RouteKind,
                        meetingPoint: String? = nil) -> RouteNarrative {
        let index = Index(home: home)
        let sentences = sentences(for: route, from: roomID, index: index, meetingPoint: meetingPoint)
        return RouteNarrative(
            roomID: roomID,
            roomName: index.roomName(roomID) ?? fallbackRoomName ?? roomID,
            kind: kind,
            steps: sentences.enumerated().map { NarrationStep(number: $0.offset + 1, text: $0.element) },
            summary: summaryLine(for: route),
            notes: notes(for: route, index: index)
        )
    }

    /// Just the sentences, unnumbered — for callers that do their own numbering.
    static func sentences(for route: Route,
                          from roomID: String,
                          in home: HomeModel,
                          meetingPoint: String? = nil) -> [String] {
        sentences(for: route, from: roomID, index: Index(home: home), meetingPoint: meetingPoint)
    }

    /// The whole room, spoken: primary route, then the backup, then any engine findings.
    /// This is the string the 3D scene should hand to VoiceOver when a room is selected.
    static func spokenDescription(room: RoomRoutePlan,
                                  in home: HomeModel,
                                  meetingPoint: String? = nil) -> String {
        var parts: [String] = []
        if let primary = narrate(room: room, in: home, kind: .primary, meetingPoint: meetingPoint) {
            parts.append(primary.spokenText)
        }
        if let secondary = narrate(room: room, in: home, kind: .secondary, meetingPoint: meetingPoint) {
            parts.append(secondary.spokenText)
        }
        let index = Index(home: home)
        parts.append(contentsOf: room.findings.map { findingSentence($0, index: index) })
        if parts.isEmpty {
            parts.append("The routing engine returned no route for the \(room.room_name).")
        }
        return parts.joined(separator: " ")
    }

    /// The engine's warning, in a sentence. The engine's own `detail` is quoted verbatim —
    /// this only supplies the surrounding grammar and resolves ids to names.
    static func findingSentence(_ finding: RouteFinding, in home: HomeModel) -> String {
        findingSentence(finding, index: Index(home: home))
    }

    /// "About 10.0 m · uses the stairs · leaves through a window"
    static func summaryLine(for route: Route) -> String {
        var parts = [String(format: "About %.1f m", route.length_m)]
        if route.uses_stairs { parts.append("uses the stairs") }
        if route.uses_window { parts.append("leaves through a window") }
        return parts.joined(separator: " · ")
    }

    /// Short label for a person: "Ada (child) — Bedroom 1".
    static func profileLine(_ profile: Profile, in home: HomeModel) -> String {
        let bedroom = Index(home: home).roomName(profile.bedroom_room_id) ?? profile.bedroom_room_id
        let tags = profile.tags.map(tagName).joined(separator: ", ")
        return tags.isEmpty ? "\(profile.name) — \(bedroom)" : "\(profile.name) (\(tags)) — \(bedroom)"
    }

    static func tagName(_ tag: ProfileTag) -> String {
        switch tag {
        case .child: return "child"
        case .elderly: return "elderly"
        case .mobility_limited: return "mobility limited"
        case .pet: return "pet"
        }
    }

    // MARK: - Step generation

    private static func sentences(for route: Route,
                                  from roomID: String,
                                  index: Index,
                                  meetingPoint: String?) -> [String] {
        var steps = events(in: route.waypoints, startingIn: roomID)
            .map { sentence(for: $0, index: index) }

        if let meetingPoint = meetingPoint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !meetingPoint.isEmpty {
            steps.append("Go to your meeting point: \(meetingPoint).")
        }
        return steps
    }

    // MARK: - Step events (the one walk both the words and the markers come from)

    /// One numbered instruction, before it is turned into either a sentence or a printed
    /// marker. Deriving both from this list is what guarantees "step 3" in the person's
    /// summary and the circled "3" on the drawing are the same moment in the route.
    enum StepEvent: Equatable {
        /// Passing through a door/window. `exitsOutside` and `nextRoomID` are read off the
        /// waypoint sequence, never guessed.
        case opening(at: Waypoint, fromRoomID: String?, exitsOutside: Bool, nextRoomID: String?)
        /// A floor crossing: two consecutive `stair` waypoints sharing `node_id`.
        case stairs(at: Waypoint, to: Waypoint, fromRoomID: String?)
        /// Reaching the exterior without an adjacent opening waypoint to fold it into.
        case outside(at: Waypoint)
        /// A `stair` waypoint with no partner — malformed, described but not invented on.
        case lonelyStair(at: Waypoint)

        /// The waypoint this step happens at — where its marker is drawn.
        var anchor: Waypoint {
            switch self {
            case .opening(let w, _, _, _): return w
            case .stairs(let w, _, _): return w
            case .outside(let w): return w
            case .lonelyStair(let w): return w
            }
        }
    }

    /// The numbered steps of a route, as waypoints. PURE — a function of the waypoint list
    /// alone, so the printed markers and the spoken steps always agree.
    ///
    /// Numbering starts at 1 and matches `narrate(...).steps`. A meeting-point step (if the
    /// user supplied one) is appended after these and has no anchor, by design: it is
    /// outside the building and off the drawing.
    static func stepAnchors(for route: Route, startingIn roomID: String? = nil)
        -> [(number: Int, waypoint: Waypoint)] {
        events(in: route.waypoints, startingIn: roomID)
            .enumerated()
            .map { (number: $0.offset + 1, waypoint: $0.element.anchor) }
    }

    /// The route's start waypoint — drawn as an unnumbered dot, since standing still is not
    /// an instruction. nil for an empty route.
    static func startWaypoint(of route: Route) -> Waypoint? {
        route.waypoints.first { $0.kind != .path }
    }

    static func events(in waypoints: [Waypoint], startingIn roomID: String? = nil) -> [StepEvent] {
        // `.path` waypoints are within-room curve points around furniture — they carry no
        // instruction of their own, so they never become a step.
        let nodes = waypoints.filter { $0.kind != .path }
        guard !nodes.isEmpty else { return [] }

        var events: [StepEvent] = []
        var currentRoomID: String? = roomID
        var i = 0
        while i < nodes.count {
            let node = nodes[i]
            let next = i + 1 < nodes.count ? nodes[i + 1] : nil
            switch node.kind {
            case .room:
                // Arriving in a room is not an instruction of its own — the step that moved
                // you here already named it. It only updates where "leave the X" starts from.
                currentRoomID = node.node_id
                i += 1

            case .opening:
                let exits = next?.kind == .exterior
                let nextRoom = next?.kind == .room ? next?.node_id : nil
                events.append(.opening(at: node, fromRoomID: currentRoomID,
                                       exitsOutside: exits, nextRoomID: nextRoom))
                if let nextRoom { currentRoomID = nextRoom }
                // The exterior node, when adjacent, belongs to this step.
                i += exits ? 2 : 1

            case .stair:
                if let next, next.kind == .stair, next.node_id == node.node_id {
                    events.append(.stairs(at: node, to: next, fromRoomID: currentRoomID))
                    currentRoomID = nil
                    i += 2
                } else {
                    events.append(.lonelyStair(at: node))
                    i += 1
                }

            case .exterior:
                events.append(.outside(at: node))
                i += 1

            case .path, .unknown:
                // `.unknown` is a waypoint kind newer than this build (see RoutePlan.swift).
                // It keeps its coordinates so the line still draws; inventing a sentence for
                // a kind we cannot name would be worse than saying nothing.
                i += 1
            }
        }
        return events
    }

    private static func sentence(for event: StepEvent, index: Index) -> String {
        switch event {
        case .opening(let waypoint, let fromRoomID, let exitsOutside, let nextRoomID):
            return openingSentence(openingID: waypoint.node_id,
                                   fromRoomID: fromRoomID,
                                   exitsOutside: exitsOutside,
                                   nextRoomID: nextRoomID,
                                   index: index)
        case .stairs(let waypoint, let to, _):
            return stairSentence(stairID: waypoint.node_id,
                                 fromFloorID: waypoint.floor_id,
                                 toFloorID: to.floor_id,
                                 index: index)
        case .outside:
            return "Get outside."
        case .lonelyStair:
            return "Head for the stairs."
        }
    }

    private static func openingSentence(openingID: String,
                                        fromRoomID: String?,
                                        exitsOutside: Bool,
                                        nextRoomID: String?,
                                        index: Index) -> String {
        let opening = index.opening(openingID)
        let isWindow = opening?.kind == .window
        let from = fromRoomID.flatMap { index.roomName($0) }
        let door = isWindow ? "window" : "door"

        // The opening's own room list is the fallback when the waypoint sequence doesn't
        // name the far side — it is data from the model, not a guess.
        let goesOutside = exitsOutside || (nextRoomID == nil && opening?.isExit == true)
        let destination = nextRoomID.flatMap { index.roomName($0) }
            ?? opening?.room_ids.first(where: { $0 != fromRoomID && $0 != EXTERIOR_ID })
                .flatMap { index.roomName($0) }

        if goesOutside {
            if isWindow {
                return from.map { "Climb out through the window in the \($0) to get outside." }
                    ?? "Climb out through the window to get outside."
            }
            return from.map { "Leave the \($0) through the door to the outside." }
                ?? "Go out through the exterior door."
        }
        if let destination {
            return from.map { "Leave the \($0) through the \(door) into the \(destination)." }
                ?? "Go through the \(door) into the \(destination)."
        }
        return from.map { "Leave the \($0) through the \(door)." } ?? "Go through the \(door)."
    }

    private static func stairSentence(stairID: String,
                                      fromFloorID: String,
                                      toFloorID: String,
                                      index: Index) -> String {
        let fromLevel = index.floorLevel(fromFloorID)
        let toLevel = index.floorLevel(toFloorID)
        let direction: String
        if let fromLevel, let toLevel {
            direction = toLevel < fromLevel ? "down" : (toLevel > fromLevel ? "up" : "across")
        } else {
            direction = "along"
        }
        let toName = index.floorName(toFloorID)
        if let toName {
            return "Take the stairs \(direction) to the \(toName)."
        }
        return "Take the stairs \(direction) to the next floor."
    }

    private static func notes(for route: Route, index: Index) -> [String] {
        var notes: [String] = []
        if route.uses_window, let exit = index.opening(route.exit_id), exit.kind == .window {
            notes.append(String(format:
                "This route leaves through a window with a sill %.2f m above the floor.",
                exit.sill_height_m))
        }
        return notes
    }

    private static func findingSentence(_ finding: RouteFinding, index: Index) -> String {
        let room = index.roomName(finding.room_id) ?? finding.room_id
        let blamed = finding.object_ids
            .compactMap { index.objectName($0) }
            .joined(separator: ", ")
        switch finding.kind {
        case .no_viable_route:
            return "No escape route could be computed from the \(room). \(finding.detail)"
        case .no_secondary_egress:
            return "The \(room) has no second way out. \(finding.detail)"
        case .blocked_opening:
            let suffix = blamed.isEmpty ? "" : " Blocked by: \(blamed)."
            return "A way out of the \(room) is blocked. \(finding.detail)\(suffix)"
        case .unknown:
            return "\(room): \(finding.detail)"
        }
    }

    // MARK: - Lookups

    /// Flattened id → name lookups over a HomeModel. Built once per narration call; a pure
    /// value with no caching, so it can never disagree with the model it was built from.
    struct Index {
        private let roomNames: [String: String]
        private let floorNames: [String: String]
        private let floorLevels: [String: Int]
        private let openings: [String: Opening]
        private let objectNames: [String: String]
        private let stairs: [String: Stairs]

        init(home: HomeModel) {
            var roomNames: [String: String] = [:]
            var floorNames: [String: String] = [:]
            var floorLevels: [String: Int] = [:]
            var openings: [String: Opening] = [:]
            var objectNames: [String: String] = [:]
            for floor in home.floors {
                floorNames[floor.id] = floor.name
                floorLevels[floor.id] = floor.level
                for room in floor.rooms { roomNames[room.id] = room.name }
                for opening in floor.openings { openings[opening.id] = opening }
                for object in floor.objects { objectNames[object.id] = object.category.rawValue }
            }
            self.roomNames = roomNames
            self.floorNames = floorNames
            self.floorLevels = floorLevels
            self.openings = openings
            self.objectNames = objectNames
            self.stairs = Dictionary(uniqueKeysWithValues: home.stairs.map { ($0.id, $0) })
        }

        func roomName(_ id: String) -> String? { roomNames[id] }
        func floorName(_ id: String) -> String? { floorNames[id] }
        func floorLevel(_ id: String) -> Int? { floorLevels[id] }
        func opening(_ id: String) -> Opening? { openings[id] }
        func objectName(_ id: String) -> String? { objectNames[id] }

        /// The room a flight of stairs lands in on `floorID`.
        func stairRoom(stairID: String, onFloor floorID: String) -> String? {
            guard let stair = stairs[stairID] else { return nil }
            if stair.from.floor_id == floorID { return stair.from.room_id }
            if stair.to.floor_id == floorID { return stair.to.room_id }
            return nil
        }
    }
}
