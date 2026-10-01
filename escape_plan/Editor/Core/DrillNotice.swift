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

    /// Why the drill cannot walk `room`, or nil when it has a primary route to walk.
    ///
    /// A tornado room the engine could not get to shelter shows that finding and nothing else.
    /// Any other room without a primary route names the profile, then the engine's first
    /// finding verbatim.
    static func cannotStart(room: RoomRoutePlan, profileName: String,
                            peril: String?) -> DrillNotice? {
        if peril == "tornado",
           let finding = room.findings.first(where: { $0.kind == .no_viable_safe_room }) {
            return DrillNotice(finding: finding)
        }
        guard room.primary == nil else { return nil }
        let lead = "No primary route for \(profileName)."
        guard let finding = room.findings.first else { return DrillNotice(text: lead) }
        return DrillNotice(text: "\(lead) \(finding.detail)",
                           citations: finding.citation.map { [$0] } ?? [])
    }
}
