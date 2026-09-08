import Foundation

enum ResponderSnapshotExtractor {
    static func extract(from document: EscapePlanDocument) -> ResponderSnapshotJSON {
        let home = document.home
        let now = Date()
        
        // Safety Points
        let safetyPoints = home.floors.flatMap { floor in
            floor.safety_points.map { pt in
                ResponderSnapshotJSON.SafetyPointInfo(
                    kind: pt.kind.rawValue,
                    roomName: "Floor \(floor.level)",
                    floorLevel: floor.level
                )
            }
        }
        
        // Vulnerable occupants anonymously
        var vulnerableCounts: [String: (Int, Int, String)] = [:] // roomId: (count, level, roomName)
        for profile in home.profiles {
            if profile.tags.contains(.mobility_limited) || profile.tags.contains(.vision_impaired) {
                if let located = home.locateRoom(profile.bedroom_room_id),
                   let floor = home.floors.first(where: { $0.id == located.floorId }) {
                    let existingCount = vulnerableCounts[located.room.id]?.0 ?? 0
                    vulnerableCounts[located.room.id] = (existingCount + 1, floor.level, located.room.name)
                }
            }
        }
        
        let vulnerableList = vulnerableCounts.map {
            ResponderSnapshotJSON.VulnerableOccupant(count: $0.value.0, roomName: $0.value.2, floorLevel: $0.value.1)
        }.sorted { $0.roomName < $1.roomName }
        
        // Hazards
        var hazards: [ResponderSnapshotJSON.HazardFinding] = []
        if let plan = document.plan {
            for roomPlan in plan.rooms {
                if let located = home.locateRoom(roomPlan.room_id),
                   let floor = home.floors.first(where: { $0.id == located.floorId }) {
                    for finding in roomPlan.findings {
                        if finding.kind == .no_viable_route || finding.kind == .no_viable_safe_room {
                            hazards.append(ResponderSnapshotJSON.HazardFinding(
                                kind: finding.kind.rawValue,
                                detail: finding.detail,
                                roomName: located.room.name,
                                floorLevel: floor.level
                            ))
                        }
                    }
                }
            }
        }
        
        var safeRoomName: String? = nil
        if let srItem = document.scoreResponse?.checklist.first(where: { $0.category == .safe_room }) {
            if let component = srItem.component, let located = home.locateRoom(component) {
                safeRoomName = located.room.name
            } else {
                safeRoomName = srItem.title // Fallback
            }
        }
        
        return ResponderSnapshotJSON(
            generatedAt: now,
            lastScannedAt: home.meta.last_scanned,
            readinessScore: document.scoreResponse?.score,
            safeRoomName: safeRoomName,
            vulnerableOccupants: vulnerableList,
            safetyPoints: safetyPoints,
            hazards: hazards
        )
    }
}
