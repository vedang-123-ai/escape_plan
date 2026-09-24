import Foundation

enum ResponderSnapshotExtractor {
    /// A pure function of `document` and `consent` — no clock read of its own. `now` comes
    /// from `document.generatedAt`, which the exporter stamps once at write time, so calling
    /// this twice on the same inputs is byte-identical (RULES: "exports are pure functions").
    static func extract(from document: EscapePlanDocument,
                        consent: SnapshotConsentDecision) -> ResponderSnapshotJSON {
        let home = document.home
        let now = document.generatedAt
        
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
        
        // Vulnerable occupants — counted by room always; named only if the resident opted in
        // for THIS share (SnapshotConsentDecision.includeOccupantNames).
        var vulnerableCounts: [String: (count: Int, level: Int, roomName: String, names: [String])] = [:]
        for profile in home.profiles {
            if profile.tags.contains(.mobility_limited) || profile.tags.contains(.vision_impaired) {
                if let located = home.locateRoom(profile.bedroom_room_id),
                   let floor = home.floors.first(where: { $0.id == located.floorId }) {
                    var entry = vulnerableCounts[located.room.id]
                        ?? (count: 0, level: floor.level, roomName: located.room.name, names: [])
                    entry.count += 1
                    entry.names.append(profile.name)
                    vulnerableCounts[located.room.id] = entry
                }
            }
        }

        let vulnerableList = vulnerableCounts.map {
            ResponderSnapshotJSON.VulnerableOccupant(
                count: $0.value.count,
                roomName: $0.value.roomName,
                floorLevel: $0.value.level,
                names: consent.includeOccupantNames ? $0.value.names.sorted() : nil)
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
        
        var isStale = true
        if let lastScanned = home.meta.last_scanned {
            isStale = now.timeIntervalSince(lastScanned) > staleWindow
        }

        let hazardSummary = SnapshotHazardSummary.summarize(checklist: document.scoreResponse?.checklist ?? [])

        return ResponderSnapshotJSON(
            generatedAt: now,
            asOf: home.meta.last_scanned,
            isStale: isStale,
            consent: consent,
            readinessScore: document.scoreResponse?.score,
            safeRoomName: safeRoomName,
            vulnerableOccupants: vulnerableList,
            safetyPoints: safetyPoints,
            hazards: hazards,
            hazardSummary: hazardSummary
        )
    }

    /// A scan older than this is presented as stale. `EscapePlanPDF` reads this same constant
    /// so the printed page and the JSON can never disagree about what "stale" means.
    static let staleWindow: TimeInterval = 30 * 24 * 3600
}
