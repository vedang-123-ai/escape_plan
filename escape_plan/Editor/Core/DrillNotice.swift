//
//  DrillNotice.swift
//  EditorCore
//
//  Every notice the drill shows when it cannot start a walk-through, built in one pure place.
//
//  WHY THIS EXISTS AS A SEPARATE FILE: these notices used to be string literals inside
//  `DrillScreen.start`, where no test reached them, and one of them wrote its own tornado
//  advice on top of the engine's finding (AUD-025): leave the house for another building,
//  with a raw `[cite: ...]` tag. The engine limits that advice to mobile and manufactured
//  homes; for a site-built house the corpus says the opposite.
//
//  THE RULE THIS FILE FOLLOWS: a notice is either the engine's finding, verbatim, with the
//  engine's own citation id carried alongside it, or plain status copy that makes no safety
//  judgment ("no plan came back", "the route is too short"). Nothing here writes advice.
//  `DrillNoticeTests` holds every fixed string to that rule.

import Foundation

/// A message the drill shows instead of a walk-through.
struct DrillNotice: Equatable {
    /// What the user reads. Never contains an inline `[cite: ...]` tag.
    let text: String
    /// Source ids the engine attached, shown as chips the way the drill shows every source.
    let citations: [String]

    init(text: String, citations: [String] = []) {
        self.text = text
        self.citations = citations
    }

    /// An engine finding exactly as the engine sent it.
    init(finding: RouteFinding) {
        self.init(text: finding.detail, citations: finding.citation.map { [$0] } ?? [])
    }

    /// The cached plan belongs to another home.
    static let differentHome = DrillNotice(
        text: "The saved plan is for a different home — try again online.")

    /// The engine sent no plan for the profile's bedroom.
    static func noPlan(profileName: String) -> DrillNotice {
        DrillNotice(text: "The engine returned no plan for \(profileName)'s bedroom.")
    }

    /// The primary route has fewer than two points to walk between.
    static func routeTooShort(profileName: String) -> DrillNotice {
        DrillNotice(text: "The route for \(profileName) is too short to walk through.")
    }

    /// What the drill does with `room`: walk its primary route, or show a notice instead.
    enum Start: Equatable {
        case walk(Route)
        case notice(DrillNotice)
    }

    /// A tornado room the engine could not get to shelter shows that finding and nothing else.
    /// Any other room without a primary route names the profile, then the engine finding that
    /// explains it, verbatim: no route at all first, then a blocked doorway, then whatever came first.
    static func start(room: RoomRoutePlan, profileName: String, peril: String?) -> Start {
        if peril == "tornado",
           let finding = room.findings.first(where: { $0.kind == .no_viable_safe_room }) {
            return .notice(DrillNotice(finding: finding))
        }
        if let primary = room.primary { return .walk(primary) }
        let lead = "No primary route for \(profileName)."
        let reason = room.findings.first(where: { $0.kind == .no_viable_route })
            ?? room.findings.first(where: { $0.kind == .blocked_opening })
            ?? room.findings.first
        guard let finding = reason else { return .notice(DrillNotice(text: lead)) }
        return .notice(DrillNotice(text: "\(lead) \(finding.detail)",
                                   citations: finding.citation.map { [$0] } ?? []))
    }
}
