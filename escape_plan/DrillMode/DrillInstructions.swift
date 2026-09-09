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

    static func card(for step: DrillStep, profileName: String, peril: String = "fire") -> DrillCard {
        switch step {
        case .start(let roomName):
            if peril == "earthquake" {
                return DrillCard(
                    title: "Earthquake drill",
                    body: "Start in \(roomName). When the shaking starts, do not try to run. "
                        + "Drop to the ground before the earthquake throws you down. "
                        + "[cite: shakeout-guidance]"
                )
            } else if peril == "tornado" {
                return DrillCard(
                    title: "Tornado warning",
                    body: "Start in \(roomName). When a tornado warning is issued, you must seek shelter "
                        + "immediately in a designated safe room. [cite: redcross-tornado]"
                )
            } else {
                return DrillCard(
                    title: "Start in \(roomName)",
                    body: "This is \(profileName)'s starting point. Before opening a door, test it: "
                        + "if the door or handle is warm to the back of your hand, use your second "
                        + "way out. If there is smoke, get low and go — crawl beneath the smoke "
                        + "layer where the air is cleaner. [cite: nfpa-escape-planning]"
                )
            }
        case .move(_, let destinationKind):
            return moveCard(toward: destinationKind)
        case .stairs:
            return DrillCard(
                title: "Take the stairs",
                body: "The route continues on the next floor. Follow the glowing markers down "
                    + "the stairs and keep moving."
            )
        case .dropCoverHold(let coverObjectName, let noCoverFinding):
            if let name = coverObjectName {
                return DrillCard(
                    title: "Cover and Hold On",
                    body: "Cover your head and neck with your arms. Seek additional cover by "
                        + "getting under the \(name). Hold on to your shelter and move with "
                        + "it until the shaking stops. [cite: shakeout-guidance]"
                )
            } else {
                return DrillCard(
                    title: "No Cover",
                    body: noCoverFinding ?? "Drop to the ground and cover your head and neck with your arms. [cite: shakeout-guidance]"
                )
            }
        case .aftershockEvacuate:
            return DrillCard(
                title: "Evacuate",
                body: "When the shaking stops, evaluate your surroundings. Evacuate only if the "
                    + "building is damaged or if you are instructed to do so. Be cautious of "
                    + "aftershocks. [cite: fema-earthquake] [cite: usgs-earthquake]"
            )
        case .drillComplete(let peril):
            if peril == "tornado" {
                return DrillCard(
                    title: "Safe Room reached",
                    body: "You have reached your safe room. Wait until the severe weather threat "
                        + "has passed."
                )
            }
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

    // MARK: - Practice frequency (reminders)

    /// The ONLY frequency the app is allowed to put in front of the user, because it is the
    /// only one the corpus states. Two independent sources say it, and both are quoted here
    /// rather than merged into one number with one citation:
    ///
    ///   backend/corpus/escape-planning-nfpa.md  — "**Practice the plan twice a year**,
    ///       making the drill as realistic as possible. [cite: nfpa-escape-planning]"
    ///   backend/corpus/home-fire-escape-redcross.md — "Practice at least **twice a year**,
    ///       varying conditions (night drill, blocked primary exit). [cite: redcross-escape-plan]"
    ///
    /// Nothing rounds or reinterprets this: the reminder cadence the app recommends is
    /// exactly twice a year, and it is never shown without these chips.
    static let practiceFrequencyGuidance =
        "Practice the plan twice a year, making the drill as realistic as possible. "
        + "[cite: nfpa-escape-planning] The Red Cross says the same — practise at least twice "
        + "a year, varying the conditions, such as a night drill or a blocked primary exit. "
        + "[cite: redcross-escape-plan]"

    /// Shown beside the cadence picker. Deliberately carries NO citation because it makes no
    /// safety claim — it exists to keep the user's own choice from reading as advice.
    static let cadenceChoiceNote =
        "Only the twice-a-year reminder comes from published guidance. Any other interval is "
        + "your own choice, and the app makes no safety claim about it."

    /// The Red Cross drill loop, quoted for the timer. A benchmark, not a verdict — the app
    /// never tells a household they passed or failed it.
    static let drillTimerGoal =
        "In a Red Cross drill you sound the alarm, start a timer, and stop it when everyone "
        + "has reached the meeting place — the goal is under two minutes. "
        + "[cite: redcross-two-minutes]"

    /// Every body string a card can produce, for the citation-resolution test.
    static var auditableBodies: [String] {
        var steps: [DrillStep] = [
            .start(roomName: "Bedroom"),
            .dropCoverHold(coverObjectName: "table", noCoverFinding: "No cover in this room — drop to the ground and cover your head and neck with your arms. [cite: shakeout-guidance]"),
            .dropCoverHold(coverObjectName: nil, noCoverFinding: "No cover in this room — drop to the ground and cover your head and neck with your arms. [cite: shakeout-guidance]"),
            .aftershockEvacuate,
            .stairs(fromFloorID: "f1", toFloorID: "f0"),
            .drillComplete(peril: "fire"),
            .drillComplete(peril: "tornado"),
        ]
        let anySegment = Route(waypoints: [], length_m: 0, uses_stairs: false,
                               uses_window: false, exit_id: "exit")
        for kind in [WaypointKind.room, .opening, .stair, .exterior] {
            steps.append(.move(segment: anySegment, destinationKind: kind))
        }
        // Standalone copy is audited by the same test as the cards — a frequency shown
        // without a resolvable citation is exactly the failure this test exists to catch.
        return steps.map { card(for: $0, profileName: "Sam", peril: "fire").body }
            + [
                card(for: .start(roomName: "Bedroom"), profileName: "Sam", peril: "earthquake").body,
                card(for: .start(roomName: "Bedroom"), profileName: "Sam", peril: "tornado").body
              ]
            + [practiceFrequencyGuidance, cadenceChoiceNote, drillTimerGoal]
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
