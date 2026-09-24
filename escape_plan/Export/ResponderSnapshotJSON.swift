import Foundation

/// What the resident explicitly agreed to for THIS share — captured fresh every time
/// `ConsentSheet` is accepted (S11.6: "consent is explicit, per share"). Never persisted
/// beyond the snapshot it produced.
struct SnapshotConsentDecision: Codable, Equatable {
    var acknowledgedAt: Date
    /// Off by default. Occupants are counted by room, never named, unless the resident
    /// explicitly opted in and the consent text said so — see `ConsentSheet`.
    var includeOccupantNames: Bool

    static func acknowledgedNow(includeOccupantNames: Bool = false) -> SnapshotConsentDecision {
        SnapshotConsentDecision(acknowledgedAt: Date(), includeOccupantNames: includeOccupantNames)
    }
}

/// A pure function of the HomeModel, the last cached score/route plan, and the consent
/// decision that authorized this specific share. Nothing here is invented, nothing is ever
/// transmitted automatically, and nothing computes a route — see CLAUDE.md and
/// `.claude/rules/vendors/anthropic.md`.
struct ResponderSnapshotJSON: Codable {
    var generatedAt: Date
    /// The home scan/edit this snapshot describes. `nil` when the home has no recorded scan
    /// date at all — `isStale` is then `true` and the staleness note still ships regardless.
    var asOf: Date?
    var isStale: Bool
    /// Fixed, always present, worded exactly as agreed in the S11.6 session file: layouts
    /// drift and this data is resident-entered, never verified by any department. This is a
    /// statement about the app's own limits, not a safety technique, so it carries no corpus
    /// citation (see `.claude/rules/paths/corpus.md`).
    var stalenessNote: String = ResponderSnapshotJSON.fixedStalenessNote
    /// Fixed, always present: this is a prevention/readiness artifact, never a tool for use
    /// mid-emergency. Restated here because the JSON can be read by software that never saw
    /// the app's own copy.
    var tacticalDisclaimer: String = ResponderSnapshotJSON.fixedTacticalDisclaimer
    var consent: SnapshotConsentDecision
    var readinessScore: Int?
    var safeRoomName: String?
    var vulnerableOccupants: [VulnerableOccupant]
    var safetyPoints: [SafetyPointInfo]
    var hazards: [HazardFinding]
    /// Counts by category + rule id from the engine's own findings, each with its citation.
    /// Deliberately not an aggregate score — see `SnapshotHazardSummary`.
    var hazardSummary: [SnapshotHazardSummary.Entry] = []

    enum CodingKeys: String, CodingKey {
        case generatedAt
        case asOf = "as_of"
        case isStale, stalenessNote, tacticalDisclaimer, consent
        case readinessScore, safeRoomName, vulnerableOccupants, safetyPoints, hazards, hazardSummary
    }

    /// Fixed strings, factored out as static so `EscapePlanPDF` can print the identical
    /// wording on every responder-snapshot page rather than a second, drifting copy.
    static let fixedStalenessNote =
        "Home layouts change after remodels. This snapshot is resident-maintained and " +
        "unverified — no department has checked it against the actual home."
    static let fixedTacticalDisclaimer =
        "This is a prevention and readiness snapshot, not a tool for use during an active " +
        "emergency. Responders should not rely on it for tactical decisions."

    struct VulnerableOccupant: Codable {
        var count: Int
        var roomName: String
        var floorLevel: Int
        /// Present only when `consent.includeOccupantNames` is true. `nil` — not an empty
        /// array — is the "resident did not opt in" state.
        var names: [String]?
    }

    struct SafetyPointInfo: Codable {
        var kind: String
        var roomName: String
        var floorLevel: Int
    }

    struct HazardFinding: Codable {
        var kind: String
        var detail: String
        var roomName: String
        var floorLevel: Int
    }
}
