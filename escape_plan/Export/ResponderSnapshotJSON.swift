import Foundation

struct ResponderSnapshotJSON: Codable {
    var generatedAt: Date
    var lastScannedAt: Date?
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
