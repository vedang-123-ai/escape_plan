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

struct ResponderSnapshotJSON: Codable {
    var generatedAt: Date
    var lastScannedAt: Date?
    var isStale: Bool
    var readinessScore: Int?
    var safeRoomName: String?
    var vulnerableOccupants: [VulnerableOccupant]
    var safetyPoints: [SafetyPointInfo]
    var hazards: [HazardFinding]

    struct VulnerableOccupant: Codable {
        var count: Int
        var roomName: String
        var floorLevel: Int
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
