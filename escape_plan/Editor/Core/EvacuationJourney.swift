//  EvacuationJourney.swift — one person's way out of a fire simulation, in words.
//
//  NARRATION, NEVER ROUTING. Every fact here is read off the engine's `OccupantTrack` (its
//  start room, its exit, its time out, its `overtaken_by_hazard` flag) or off the points the
//  engine already placed in `steps`. The only thing computed client-side is which room each
//  of those points lies in, using the same point-in-polygon test the editor uses for a tap
//  (`Geometry.contains`, last room wins like `HitTesting`). No path is searched, shortened,
//  smoothed or re-timed: a track with no steps produces no rooms, not a guess.
//
//  Pure Foundation: compiled into the app and into `tools/editorcore` (Editor/Core is
//  symlinked there), so `EvacuationJourneyTests` runs in seconds with no simulator. No
//  SwiftUI, UIKit or SceneKit import belongs in this file.
//
//  Used by House's fire simulation dock ("Who does what", trim 2, 2026-10-03).

import Foundation

/// One occupant's simulated escape, as the lines House shows and VoiceOver reads.
struct EvacuationJourney: Equatable, Identifiable {
    /// The engine's `profile_id` (a synthesized `occupant.<room>` id when the home has no
    /// profiles).
    var id: String
    var personName: String
    var startRoomName: String
    /// The rooms the track enters after the start room, in order, consecutive repeats folded.
    var roomsPassed: [String]
    /// What the person leaves through, e.g. "the door in the Living Room".
    var exitDescription: String
    var leavesThroughWindow: Bool
    /// Seconds after ignition, straight from `OccupantTrack.egress_time_s`.
    var timeOut_s: Double
    /// The engine's `overtaken_by_hazard`, unchanged.
    var overtaken: Bool

    // MARK: Lines (the visible text; `spokenSummary` reads the same facts)

    var startLine: String { "Starts in \(startRoomName)" }

    var passesLine: String {
        roomsPassed.isEmpty
            ? "Goes straight to the way out"
            : "Goes through \(EvacuationJourneyNarrator.list(roomsPassed))"
    }

    var exitLine: String {
        leavesThroughWindow ? "Climbs out through \(exitDescription)" : "Leaves through \(exitDescription)"
    }

    var timeOutLine: String { "Outside at \(EvacuationPlaybackModel.timeLabel(timeOut_s))" }

    /// Same wording as `OvertakenFindingCard`: the engine's boolean said back, no advice.
    static let overtakenLine = "The modeled fire reaches a room on their way out before they clear it."

    /// One sentence group for VoiceOver, so a person is one swipe, not five.
    var spokenSummary: String {
        var parts = ["\(personName).", "\(startLine).", "\(passesLine).", "\(exitLine).",
                     "Outside after \(EvacuationPlaybackModel.spokenTimeLabel(timeOut_s))."]
        if overtaken { parts.append("Warning. \(Self.overtakenLine)") }
        return parts.joined(separator: " ")
    }
}

enum EvacuationJourneyNarrator {

    /// Every journey in the timeline, in the engine's order.
    static func journeys(for timeline: EvacuationTimeline, in home: HomeModel) -> [EvacuationJourney] {
        timeline.tracks.map { journey(for: $0, in: home) }
    }

    static func journey(for track: OccupantTrack, in home: HomeModel) -> EvacuationJourney {
        let startName = home.locateRoom(track.start_room_id)?.room.name ?? track.start_room_id
        var rooms = roomIDs(along: track.steps, in: home)
        // The walk begins in the start room; it is already named, so it is not "passed".
        while let first = rooms.first, first == track.start_room_id { rooms.removeFirst() }
        let names = rooms.map { home.locateRoom($0)?.room.name ?? $0 }
        let exit = exitDescription(exitID: track.exit_id, usesWindow: track.uses_window, in: home)
        return EvacuationJourney(
            id: track.id,
            personName: track.profile_name,
            startRoomName: startName,
            roomsPassed: names,
            exitDescription: exit.text,
            leavesThroughWindow: exit.isWindow,
            timeOut_s: track.egress_time_s,
            overtaken: track.overtaken_by_hazard)
    }

    /// The rooms the engine's step points lie in, in walking order, with consecutive repeats
    /// folded into one. A point on no room of its floor (the step outside an exterior door, or a
    /// floor id this home does not have) is skipped, never snapped to the nearest room.
    static func roomIDs(along steps: [TimedStep], in home: HomeModel) -> [String] {
        var result: [String] = []
        for step in steps {
            guard let floor = home.floor(step.floor_id) else { continue }
            let point = Point(step.x, step.y)
            // Last room wins, as in `HitTesting`: rooms drawn later sit on top.
            guard let room = floor.rooms.last(where: { Geometry.contains($0.polygon, point) }) else {
                continue
            }
            if result.last != room.id { result.append(room.id) }
        }
        return result
    }

    /// "the door in the Living Room" / "the window in the Bedroom", from the opening the engine
    /// named. Falls back to the track's own `uses_window` when the model has no such opening.
    static func exitDescription(exitID: String, usesWindow: Bool,
                                in home: HomeModel) -> (text: String, isWindow: Bool) {
        for floor in home.floors {
            guard let opening = floor.openings.first(where: { $0.id == exitID }) else { continue }
            let isWindow = opening.kind == .window
            let noun = isWindow ? "window" : "door"
            let roomName = opening.room_ids
                .first { $0 != EXTERIOR_ID }
                .flatMap { home.locateRoom($0)?.room.name }
            if let roomName { return ("the \(noun) in the \(roomName)", isWindow) }
            return ("a \(noun)", isWindow)
        }
        return (usesWindow ? "a window" : "an outside door", usesWindow)
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and \(names.last!)"
        }
    }
}
