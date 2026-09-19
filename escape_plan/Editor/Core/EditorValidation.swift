//  EditorValidation.swift — the client-side mirror of backend/app/models.py's invariants.
//
//  This is the gate every store mutation passes through. It is deliberately a *superset check*
//  of the JSON Schema: it enforces the structural rules JSON Schema cannot express (CCW,
//  self-intersection, cross-references, global id uniqueness), exactly as pydantic does.
//
//  Pure: no I/O. Same model -> same issues, in a stable order.

import Foundation

struct ValidationIssue: Equatable, Sendable, CustomStringConvertible {
    enum Kind: String, Sendable {
        case schema_version
        case idUniqueness
        case reservedId
        case polygonDegenerate
        case polygonSelfIntersecting
        case polygonOrientation
        case danglingReference
        case openingPlacement
        case openingDimensions
        case floorLevels
        case emptyCollection
        case provenance
        case emptyString
    }

    let kind: Kind
    /// Id of the offending entity, when there is one — for driving editor highlighting.
    let entityId: String?
    let message: String

    init(_ kind: Kind, entityId: String? = nil, _ message: String) {
        self.kind = kind
        self.entityId = entityId
        self.message = message
    }

    var description: String {
        if let entityId { return "[\(kind.rawValue)] \(entityId): \(message)" }
        return "[\(kind.rawValue)] \(message)"
    }
}

/// So the store's reducer can `throw` an issue for the cases validation can't reach on its own
/// (an action naming an id that doesn't exist leaves no bad entity behind to detect).
extension ValidationIssue: Error {}

enum EditorValidation {

    /// Every structural rule, checked in one pass. Empty result == the backend will accept it.
    static func validate(_ model: HomeModel) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if model.schema_version != HomeModel.currentSchemaVersion {
            issues.append(.init(.schema_version,
                                "schema_version must be \(HomeModel.currentSchemaVersion), got \(model.schema_version)"))
        }
        if model.name.isEmpty {
            issues.append(.init(.emptyString, "home name must not be empty"))
        }
        if model.floors.isEmpty {
            issues.append(.init(.emptyCollection, "a home must have at least one floor"))
        }

        issues += validateIdUniqueness(model)
        issues += validateFloorLevels(model)

        for floor in model.floors {
            issues += validateFloor(floor)
        }
        issues += validateStairs(model)
        issues += validateProfiles(model)

        return issues
    }

    static func isValid(_ model: HomeModel) -> Bool { validate(model).isEmpty }

    // MARK: - Ids

    /// Ids are unique across ALL entity kinds (S0.2 decision) so every id is a valid graph key.
    private static func validateIdUniqueness(_ model: HomeModel) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var seen = Set<String>()

        func check(_ id: String, _ what: String) {
            if id.isEmpty {
                issues.append(.init(.emptyString, "\(what) has an empty id"))
                return
            }
            if id == EXTERIOR_ID {
                issues.append(.init(.reservedId, entityId: id,
                                    "'\(EXTERIOR_ID)' is reserved and may not be used as a \(what) id"))
                return
            }
            if !seen.insert(id).inserted {
                issues.append(.init(.idUniqueness, entityId: id,
                                    "duplicate id (ids must be unique across all entity kinds)"))
            }
        }

        for floor in model.floors {
            check(floor.id, "floor")
            for room in floor.rooms { check(room.id, "room") }
            for opening in floor.openings { check(opening.id, "opening") }
            for object in floor.objects { check(object.id, "object") }
            // Safety points join the GLOBAL pass, not a pass of their own —
            // `backend/app/models.py` claims their ids alongside every other entity, so a
            // landmark sharing a room's id is a 422. Omitted here until 2026-09-16, which
            // meant the editor accepted homes the server would refuse and the user found out
            // at save time with no way to tell which id was the problem.
            for point in floor.safety_points { check(point.id, "safety point") }
        }
        for stair in model.stairs { check(stair.id, "stairs") }
        for profile in model.profiles { check(profile.id, "profile") }
        return issues
    }

    private static func validateFloorLevels(_ model: HomeModel) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var seen = Set<Int>()
        for floor in model.floors where !seen.insert(floor.level).inserted {
            issues.append(.init(.floorLevels, entityId: floor.id,
                                "level \(floor.level) is used by more than one floor"))
        }
        return issues
    }

    // MARK: - Floors, rooms, openings

    private static func validateFloor(_ floor: Floor) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if floor.name.isEmpty {
            issues.append(.init(.emptyString, entityId: floor.id, "floor name must not be empty"))
        }
        if floor.height_m <= 0 {
            issues.append(.init(.polygonDegenerate, entityId: floor.id,
                                "height_m must be > 0, got \(floor.height_m)"))
        }
        if floor.rooms.isEmpty {
            issues.append(.init(.emptyCollection, entityId: floor.id,
                                "a floor must have at least one room"))
        }

        for room in floor.rooms {
            issues += validateRoom(room)
        }
        for opening in floor.openings {
            issues += validateOpening(opening, on: floor)
        }
        issues += validateOpeningOverlaps(on: floor)
        return issues
    }

    /// Two openings on the same wall edge must not overlap in t (touching endpoints are fine).
    /// Same-edge only: an opening hosted on an adjacent room's coincident edge is a different
    /// wall_segment and can't collide parametrically.
    private static func validateOpeningOverlaps(on floor: Floor) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var byEdge: [String: [Opening]] = [:]
        for opening in floor.openings {
            let seg = opening.wall_segment
            byEdge["\(seg.room_id)#\(seg.edge_index)", default: []].append(opening)
        }
        for group in byEdge.values where group.count > 1 {
            let sorted = group.sorted { $0.wall_segment.t0 < $1.wall_segment.t0 }
            for (a, b) in zip(sorted, sorted.dropFirst())
            where a.wall_segment.t1 > b.wall_segment.t0 + Geometry.epsilon {
                issues.append(.init(.openingPlacement, entityId: b.id,
                                    "overlaps opening '\(a.id)' on the same wall (t \(a.wall_segment.t0)…\(a.wall_segment.t1) vs \(b.wall_segment.t0)…\(b.wall_segment.t1))"))
            }
        }
        return issues.sorted { $0.entityId ?? "" < $1.entityId ?? "" }
    }

    private static func validateRoom(_ room: Room) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if room.name.isEmpty {
            issues.append(.init(.emptyString, entityId: room.id, "room name must not be empty"))
        }
        if room.polygon.count < 3 {
            issues.append(.init(.polygonDegenerate, entityId: room.id,
                                "polygon needs at least 3 vertices, got \(room.polygon.count)"))
            return issues + validateProvenance(source: room.source,
                                               confidence: room.confidence, entityId: room.id)
        }
        if !Geometry.isSimple(room.polygon) {
            issues.append(.init(.polygonSelfIntersecting, entityId: room.id,
                                "polygon is self-intersecting or has duplicate/zero-length edges"))
        } else if !Geometry.isCounterClockwise(room.polygon) {
            // Only meaningful once we know the polygon is simple.
            issues.append(.init(.polygonOrientation, entityId: room.id,
                                "polygon must be counter-clockwise (signed area \(Geometry.signedArea(room.polygon)))"))
        }
        issues += validateProvenance(source: room.source, confidence: room.confidence,
                                     entityId: room.id)
        return issues
    }

    private static func validateOpening(_ opening: Opening, on floor: Floor) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let id = opening.id

        // --- room_ids ---
        if opening.room_ids.count != 2 {
            issues.append(.init(.openingPlacement, entityId: id,
                                "room_ids must have exactly 2 entries, got \(opening.room_ids.count)"))
        }
        if Set(opening.room_ids).count != opening.room_ids.count {
            issues.append(.init(.openingPlacement, entityId: id, "room_ids entries must be distinct"))
        }
        if opening.room_ids.allSatisfy({ $0 == EXTERIOR_ID }) && !opening.room_ids.isEmpty {
            issues.append(.init(.openingPlacement, entityId: id,
                                "an opening cannot connect EXTERIOR to EXTERIOR"))
        }
        for roomId in opening.room_ids where roomId != EXTERIOR_ID {
            if floor.room(roomId) == nil {
                issues.append(.init(.danglingReference, entityId: id,
                                    "room_ids references '\(roomId)', which is not a room on floor '\(floor.id)'"))
            }
        }

        // --- wall_segment ---
        let seg = opening.wall_segment
        if !opening.room_ids.contains(seg.room_id) {
            issues.append(.init(.openingPlacement, entityId: id,
                                "wall_segment.room_id '\(seg.room_id)' must be one of the opening's room_ids"))
        }
        if seg.room_id == EXTERIOR_ID {
            issues.append(.init(.openingPlacement, entityId: id,
                                "wall_segment.room_id must be a real room, never EXTERIOR"))
        } else if let host = floor.room(seg.room_id) {
            if seg.edge_index < 0 || seg.edge_index >= host.polygon.count {
                issues.append(.init(.openingPlacement, entityId: id,
                                    "edge_index \(seg.edge_index) is out of range for room '\(host.id)' (\(host.polygon.count) edges)"))
            }
        } else {
            issues.append(.init(.danglingReference, entityId: id,
                                "wall_segment.room_id '\(seg.room_id)' is not a room on floor '\(floor.id)'"))
        }
        if seg.t0 < 0 || seg.t1 > 1 {
            issues.append(.init(.openingPlacement, entityId: id,
                                "t0/t1 must lie in [0, 1], got \(seg.t0)…\(seg.t1)"))
        }
        if seg.t0 >= seg.t1 {
            issues.append(.init(.openingPlacement, entityId: id,
                                "t0 (\(seg.t0)) must be < t1 (\(seg.t1))"))
        }

        // --- dimensions ---
        if opening.width_m <= 0 {
            issues.append(.init(.openingDimensions, entityId: id, "width_m must be > 0"))
        }
        if opening.height_m <= 0 {
            issues.append(.init(.openingDimensions, entityId: id, "height_m must be > 0"))
        }
        if opening.sill_height_m < 0 {
            issues.append(.init(.openingDimensions, entityId: id, "sill_height_m must be >= 0"))
        }

        issues += validateProvenance(source: opening.source, confidence: opening.confidence,
                                     entityId: id)
        return issues
    }

    // MARK: - Stairs & profiles

    private static func validateStairs(_ model: HomeModel) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for stair in model.stairs {
            for (label, end) in [("from", stair.from), ("to", stair.to)] {
                guard let floor = model.floor(end.floor_id) else {
                    issues.append(.init(.danglingReference, entityId: stair.id,
                                        "\(label).floor_id '\(end.floor_id)' does not exist"))
                    continue
                }
                if floor.room(end.room_id) == nil {
                    issues.append(.init(.danglingReference, entityId: stair.id,
                                        "\(label).room_id '\(end.room_id)' is not a room on floor '\(end.floor_id)'"))
                }
            }
            if stair.from.floor_id == stair.to.floor_id {
                issues.append(.init(.danglingReference, entityId: stair.id,
                                    "stairs must connect two different floors"))
            }
            if stair.footprint.count < 3 || !Geometry.isSimple(stair.footprint) {
                issues.append(.init(.polygonDegenerate, entityId: stair.id,
                                    "footprint must be a simple polygon with at least 3 vertices"))
            }
            issues += validateProvenance(source: stair.source, confidence: stair.confidence,
                                         entityId: stair.id)
        }
        return issues
    }

    private static func validateProfiles(_ model: HomeModel) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for profile in model.profiles {
            if profile.name.isEmpty {
                issues.append(.init(.emptyString, entityId: profile.id,
                                    "profile name must not be empty"))
            }
            if model.locateRoom(profile.bedroom_room_id) == nil {
                issues.append(.init(.danglingReference, entityId: profile.id,
                                    "bedroom_room_id '\(profile.bedroom_room_id)' is not a room in this home"))
            }
            if Set(profile.tags).count != profile.tags.count {
                issues.append(.init(.idUniqueness, entityId: profile.id, "tags must be unique"))
            }
        }
        return issues
    }

    // MARK: - Provenance

    /// Scan-derived items MUST carry confidence — that's what drives the editor's
    /// "needs review" treatment (S2.2). Never silently dropped, never silently unflagged.
    private static func validateProvenance(source: Source, confidence: Double?,
                                           entityId: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if source == .scan && confidence == nil {
            issues.append(.init(.provenance, entityId: entityId,
                                "source 'scan' requires a confidence value"))
        }
        if let c = confidence, c < 0 || c > 1 {
            issues.append(.init(.provenance, entityId: entityId,
                                "confidence must lie in [0, 1], got \(c)"))
        }
        return issues
    }
}
