//  DrillInstructions.swift
//  escape_plan — S4.2 drill mode
//
//  Static instruction-card copy for the guided walkthrough. Every safety claim is
//  paraphrased from backend/corpus/ and carries an inline `[cite: source-id]` tag that must
//  resolve in backend/corpus/sources.json — a unit test walks `auditableBodies` and checks
//  every id against the real file. Purely navigational lines ("head to the stairs") carry no
//  citation because they make no safety claim. Tags render verbatim, per the AssistantScreen
//  precedent: grounding is the feature, not noise.

import Foundation

struct DrillCard: Equatable {
    var title: String
    var body: String
    /// Source ids parsed out of `body`, echoed as chips under the card.
    var citations: [String] { DrillInstructions.citationIDs(in: body) }
}

enum DrillInstructions {

    static func card(for step: DrillStep, profileName: String) -> DrillCard {
        switch step {
        case .start(let roomName):
            return DrillCard(
                title: "Start in \(roomName)",
                body: "This is \(profileName)'s starting point. Before opening a door, test it: "
                    + "if the door or handle is warm to the back of your hand, use your second "
                    + "way out. If there is smoke, get low and go — crawl beneath the smoke "
                    + "layer where the air is cleaner. [cite: nfpa-escape-planning]"
            )
        case .move(_, let destinationKind):
            return moveCard(toward: destinationKind)
        case .stairs:
            return DrillCard(
                title: "Take the stairs",
                body: "The route continues on the next floor. Follow the glowing markers down "
                    + "the stairs and keep moving."
            )
        case .meetingPoint:
            return DrillCard(
                title: "Meeting place",
                body: "Gather at your one outside meeting place a safe distance from the home — "
                    + "a neighbor's house, a mailbox, a tree — so everyone can confirm quickly "
                    + "that the whole household is out. Practice this plan twice a year, making "
                    + "the drill as realistic as possible. [cite: nfpa-escape-planning]"
            )
        }
    }

    private static func moveCard(toward kind: WaypointKind) -> DrillCard {
        switch kind {
        case .room, .path, .unknown:
            // "path" points are within-room curve points around furniture (v1.1) —
            // the guidance is the same as moving through the room. `.unknown` (a waypoint
            // kind newer than this build) lands here deliberately: "follow the highlighted
            // route" is true regardless of what the new kind turns out to mean, and the
            // cited claim is generic escape guidance, not a claim about this waypoint.
            return DrillCard(
                title: "Keep moving",
                body: "Follow the highlighted route into the next room. Close doors behind you "
                    + "as you leave to slow the spread of fire and smoke. [cite: usfa-escape-plans]"
            )
        case .opening:
            return DrillCard(
                title: "Through the doorway",
                body: "Head for the highlighted door or window on the route."
            )
        case .stair:
            return DrillCard(
                title: "To the stairs",
                body: "Make your way to the stairs shown on the route."
            )
        case .exterior:
            return DrillCard(
                title: "You're out",
                body: "Get out and stay out — never go back inside for people, pets, or "
                    + "possessions. [cite: nfpa-escape-planning]"
            )
        }
    }

    /// Every body string a card can produce, for the citation-resolution test.
    static var auditableBodies: [String] {
        var steps: [DrillStep] = [
            .start(roomName: "Bedroom"),
            .stairs(fromFloorID: "f1", toFloorID: "f0"),
            .meetingPoint,
        ]
        let anySegment = Route(waypoints: [], length_m: 0, uses_stairs: false,
                               uses_window: false, exit_id: "exit")
        for kind in [WaypointKind.room, .opening, .stair, .exterior] {
            steps.append(.move(segment: anySegment, destinationKind: kind))
        }
        return steps.map { card(for: $0, profileName: "Sam").body }
    }

    /// Parses inline `[cite: source-id]` tags, in order, deduplicated.
    static func citationIDs(in text: String) -> [String] {
        var ids: [String] = []
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: #"\[cite: ([a-z0-9-]+)\]"#,
                                     options: .regularExpression, range: searchRange) {
            let tag = text[range]
            let id = tag.dropFirst("[cite: ".count).dropLast(1)
            if !ids.contains(String(id)) { ids.append(String(id)) }
            searchRange = range.upperBound..<text.endIndex
        }
        return ids
    }
}
