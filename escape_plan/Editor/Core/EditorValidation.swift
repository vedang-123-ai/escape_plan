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
        case sizeBounds
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

/// Residential size bounds (S11.25, AUD-004) — the client-side mirror of the constants in
/// `backend/app/models.py`. **Change them in both places, or the editor starts producing 422s.**
///
/// There are TWO independent cost drivers, and bounding only one does not close AUD-004:
///
/// 1. **Grid cells.** The backend's router rasterizes each room's *bounding box* at 10 cm cells,
///    so cost is linear in bounding-box cells and NOT in room area: a 75 m² diagonal sliver
///    spanning 150 m × 150 m costs 2,250,000 cells, 300× more than its area justifies. An area
///    cap alone would not have closed AUD-004. ~26 µs per cell for the three plans `/score` runs.
///
/// 2. **Objects in one room** — the worse one. When a route is blocked, the server's culprit
///    attribution re-rasterizes the room per object, so cost grows ~O(n^1.7) in the objects one
///    room holds, almost regardless of its cell count. Measured 2026-09-30 in a 1,225-cell room,
///    one peril: 25 objects 0.90 s, 100 objects 9.03 s, 400 objects 134.17 s.
///
/// Budget: the COMBINED worst case a valid home can reach (245,000 cells, 200 rooms, 200 objects,
/// every route blocked) measures **21.82 s** for a 3-peril `/score` on a 2026 Mac. See
/// docs/decisions.md, 2026-09-30.
enum HomeSizeBounds {
    static let maxCoordM = 200.0
    static let maxPolygonVertices = 64
    static let maxRoomSpanM = 60.0
    static let maxRoomAreaM2 = 500.0
    static let maxRoomGridCells = 90_000
    static let maxTotalGridCells = 250_000
    static let maxFloors = 8
    /// Rooms across the whole home, not per floor.
    static let maxRooms = 200
    static let maxOpeningsPerFloor = 400
    /// Objects whose bounding circle overlaps ONE room's bounding box — the set the server
    /// rasterizes against, and the driver of the ~O(n^1.7) blocked-route analysis.
    static let maxObjectsPerRoom = 25
    static let maxObjectsPerFloor = 120
    /// Objects across the whole home. Largest committed fixture: 9.
    static let maxObjectsTotal = 200
    static let maxSafetyPointsPerFloor = 100
    static let maxStairs = 50
    static let maxProfiles = 50
    static let maxFloorHeightM = 20.0
    static let maxOpeningDimM = 20.0
    static let maxObjectSizeM = 50.0
    static let maxObjectHeightM = 20.0
    static let maxObjectElevationM = 100.0

    /// Mirror of `CELL_M` in `backend/app/routing/nav_grid.py` (and `_CELL_M` in models.py).
    static let cellM = 0.1

    /// Navigation-grid cells the backend's router would rasterize for this polygon.
    /// Mirrors `bbox_cell_count` in models.py and `build_room_grid`'s `cols * rows`.
    static func gridCellCount(_ polygon: [Point]) -> Int {
        guard !polygon.isEmpty else { return 0 }
        // `Int(_:)` TRAPS on NaN and on infinity, and a scan or a bad edit can put either in a
        // polygon, so a non-finite or absurd extent reports Int.max rather than crashing the
        // editor. Callers treat Int.max as "over every bound", which it is.
        let xs = polygon.map(\.x), ys = polygon.map(\.y)
        func axisCells(_ values: [Double]) -> Int {
            // Every value, not just the extent: `max()`/`min()` skip a non-leading NaN
            // (all its comparisons are false), so the extent can come back finite for a
            // polygon that contains one. Mirrors `axis_cells` in backend/app/models.py.
            guard values.allSatisfy(\.isFinite) else { return Int.max }
            let cells = ((values.max()! - values.min()!) / cellM).rounded(.up)
            guard cells.isFinite, cells < Double(Int.max / 2) else { return Int.max }
            return max(1, Int(cells))
        }
        let cols = axisCells(xs), rows = axisCells(ys)
        guard cols != Int.max, rows != Int.max,
              let product = cols.multipliedReportingOverflow(by: rows).overflow
                  ? nil : cols * rows
        else { return Int.max }
        return product
    }
}

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
        issues += validateSizeBounds(model)

        return issues
    }

    // MARK: - Size bounds (S11.25, AUD-004)

    /// The home-wide half of the bounds: the counts and the routing cost. Per-item bounds
    /// live with the item, next to its other rules.
    private static func validateSizeBounds(_ model: HomeModel) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if model.floors.count > HomeSizeBounds.maxFloors {
            issues.append(.init(.sizeBounds,
                                "this home has \(model.floors.count) floors; the maximum is \(HomeSizeBounds.maxFloors)"))
        }
        if model.stairs.count > HomeSizeBounds.maxStairs {
            issues.append(.init(.sizeBounds,
                                "this home has \(model.stairs.count) stairs; the maximum is \(HomeSizeBounds.maxStairs)"))
        }
        if model.profiles.count > HomeSizeBounds.maxProfiles {
            issues.append(.init(.sizeBounds,
                                "this home has \(model.profiles.count) people; the maximum is \(HomeSizeBounds.maxProfiles)"))
        }

        let objectCount = model.floors.reduce(0) { $0 + $1.objects.count }
        if objectCount > HomeSizeBounds.maxObjectsTotal {
            issues.append(.init(.sizeBounds,
                                "this home has \(objectCount) objects; the maximum is \(HomeSizeBounds.maxObjectsTotal). Escape Plan models the large furniture that affects a route, not every item in the house."))
        }

        let roomCount = model.floors.reduce(0) { $0 + $1.rooms.count }
        if roomCount > HomeSizeBounds.maxRooms {
            issues.append(.init(.sizeBounds,
                                "this home has \(roomCount) rooms across \(model.floors.count) floors; the maximum is \(HomeSizeBounds.maxRooms). Escape Plan models a single residence."))
        }

        // The binding bound. Routing cost is proportional to this number, so the backend
        // refuses anything larger rather than spend minutes on one request.
        // Saturating, because gridCellCount reports Int.max for a non-finite polygon.
        let totalCells = model.floors.reduce(0) { sum, floor in
            floor.rooms.reduce(sum) { running, room in
                let (next, overflow) = running.addingReportingOverflow(
                    HomeSizeBounds.gridCellCount(room.polygon))
                return overflow ? Int.max : next
            }
        }
        if totalCells > HomeSizeBounds.maxTotalGridCells {
            issues.append(.init(.sizeBounds,
                                "this home is too large to route: it needs \(totalCells) navigation cells and the maximum is \(HomeSizeBounds.maxTotalGridCells). Split it into separate homes, or straighten any long thin rooms."))
        }
        return issues
    }

    /// Coordinate range, vertex count, span and grid cost for one polygon.
    /// Mirrors `_validate_polygon_bounds` in `backend/app/models.py`.
    private static func validatePolygonBounds(_ polygon: [Point], entityId: String,
                                              what: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if polygon.count > HomeSizeBounds.maxPolygonVertices {
            issues.append(.init(.sizeBounds, entityId: entityId,
                                "\(what) has \(polygon.count) vertices; the maximum is \(HomeSizeBounds.maxPolygonVertices). Simplify the outline."))
        }
        for point in polygon {
            issues += validateCoordinate(point.x, axis: "x", entityId: entityId, what: what)
            issues += validateCoordinate(point.y, axis: "y", entityId: entityId, what: what)
        }
        // Span and cell count are meaningless once a coordinate is NaN or infinite, and
        // computing them would trap. pydantic's _check_coord raises at the same point.
        guard !polygon.isEmpty,
              polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return issues }

        let xs = polygon.map(\.x), ys = polygon.map(\.y)
        let width = xs.max()! - xs.min()!, depth = ys.max()! - ys.min()!
        if width > HomeSizeBounds.maxRoomSpanM || depth > HomeSizeBounds.maxRoomSpanM {
            issues.append(.init(.sizeBounds, entityId: entityId,
                                "\(what) spans \(String(format: "%.1f", width)) m × \(String(format: "%.1f", depth)) m; the maximum is \(Int(HomeSizeBounds.maxRoomSpanM)) m on a side."))
        }
        let cells = HomeSizeBounds.gridCellCount(polygon)
        if cells > HomeSizeBounds.maxRoomGridCells {
            issues.append(.init(.sizeBounds, entityId: entityId,
                                "\(what) needs \(cells) navigation cells and the maximum is \(HomeSizeBounds.maxRoomGridCells). A long thin room costs as much as the whole box it spans — split it or straighten it."))
        }
        return issues
    }

    /// Written as a positive range check, so a NaN or infinite coordinate is caught too.
    private static func validateCoordinate(_ value: Double, axis: String, entityId: String,
                                          what: String) -> [ValidationIssue] {
        if !value.isFinite {
            return [.init(.sizeBounds, entityId: entityId,
                          "\(what): \(axis) coordinate must be a finite number")]
        }
        if !(-HomeSizeBounds.maxCoordM...HomeSizeBounds.maxCoordM).contains(value) {
            return [.init(.sizeBounds, entityId: entityId,
                          "\(what): \(axis) coordinate \(value) is outside the supported range ±\(Int(HomeSizeBounds.maxCoordM)) m")]
        }
        return []
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

        if floor.height_m > HomeSizeBounds.maxFloorHeightM {
            issues.append(.init(.sizeBounds, entityId: floor.id,
                                "height_m \(floor.height_m) exceeds the maximum of \(Int(HomeSizeBounds.maxFloorHeightM)) m"))
        }
        if floor.openings.count > HomeSizeBounds.maxOpeningsPerFloor {
            issues.append(.init(.sizeBounds, entityId: floor.id,
                                "this floor has \(floor.openings.count) doors and windows; the maximum is \(HomeSizeBounds.maxOpeningsPerFloor)"))
        }
        if floor.objects.count > HomeSizeBounds.maxObjectsPerFloor {
            issues.append(.init(.sizeBounds, entityId: floor.id,
                                "this floor has \(floor.objects.count) objects; the maximum is \(HomeSizeBounds.maxObjectsPerFloor)"))
        }
        issues += validateObjectsPerRoom(on: floor)
        if floor.safety_points.count > HomeSizeBounds.maxSafetyPointsPerFloor {
            issues.append(.init(.sizeBounds, entityId: floor.id,
                                "this floor has \(floor.safety_points.count) landmarks; the maximum is \(HomeSizeBounds.maxSafetyPointsPerFloor)"))
        }

        for room in floor.rooms {
            issues += validateRoom(room)
        }
        for opening in floor.openings {
            issues += validateOpening(opening, on: floor)
        }
        for object in floor.objects {
            issues += validateObjectBounds(object)
        }
        for point in floor.safety_points {
            issues += validateCoordinate(point.position.x, axis: "x", entityId: point.id,
                                        what: "landmark position")
            issues += validateCoordinate(point.position.y, axis: "y", entityId: point.id,
                                        what: "landmark position")
        }
        issues += validateOpeningOverlaps(on: floor)
        return issues
    }

    /// Objects per ROOM, counted with the same bounding-box overlap test the server's
    /// `objects_intersecting` uses — that is the set it rasterizes against. Mirrors the
    /// per-room check in `Floor._check` in `backend/app/models.py`.
    private static func validateObjectsPerRoom(on floor: Floor) -> [ValidationIssue] {
        guard !floor.objects.isEmpty else { return [] }
        var issues: [ValidationIssue] = []
        for room in floor.rooms where !room.polygon.isEmpty {
            let xs = room.polygon.map(\.x), ys = room.polygon.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max(),
                  minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite
            else { continue }   // a non-finite polygon is already reported elsewhere
            var count = 0
            for object in floor.objects where object.size_m.count == 2 {
                let radius = (object.size_m[0] * object.size_m[0]
                              + object.size_m[1] * object.size_m[1]).squareRoot() / 2
                guard radius.isFinite, object.center.x.isFinite, object.center.y.isFinite
                else { continue }
                if object.center.x + radius >= minX, object.center.x - radius <= maxX,
                   object.center.y + radius >= minY, object.center.y - radius <= maxY {
                    count += 1
                }
            }
            if count > HomeSizeBounds.maxObjectsPerRoom {
                issues.append(.init(.sizeBounds, entityId: room.id,
                                    "\(count) objects overlap this room; the maximum is \(HomeSizeBounds.maxObjectsPerRoom). Working out which one blocks a route costs more than linearly in the objects a room holds, so more would make this home slow to route. Remove or merge some, or split the room."))
            }
        }
        return issues
    }

    /// Size bounds for one object. Mirrors `FloorObject._check` in `backend/app/models.py`.
    private static func validateObjectBounds(_ object: FloorObject) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        issues += validateCoordinate(object.center.x, axis: "x", entityId: object.id,
                                    what: "object centre")
        issues += validateCoordinate(object.center.y, axis: "y", entityId: object.id,
                                    what: "object centre")
        if object.size_m.contains(where: { $0 > HomeSizeBounds.maxObjectSizeM }) {
            issues.append(.init(.sizeBounds, entityId: object.id,
                                "object footprint exceeds the maximum of \(Int(HomeSizeBounds.maxObjectSizeM)) m on a side"))
        }
        if object.height_m > HomeSizeBounds.maxObjectHeightM {
            issues.append(.init(.sizeBounds, entityId: object.id,
                                "object height \(object.height_m) m exceeds the maximum of \(Int(HomeSizeBounds.maxObjectHeightM)) m"))
        }
        if object.elevation_m > HomeSizeBounds.maxObjectElevationM {
            issues.append(.init(.sizeBounds, entityId: object.id,
                                "object elevation \(object.elevation_m) m exceeds the maximum of \(Int(HomeSizeBounds.maxObjectElevationM)) m"))
        }
        if !object.rotation_deg.isFinite {
            issues.append(.init(.sizeBounds, entityId: object.id,
                                "object rotation must be a finite number"))
        }
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
        issues += validatePolygonBounds(room.polygon, entityId: room.id, what: "this room")
        let area = abs(Geometry.signedArea(room.polygon))
        if area > HomeSizeBounds.maxRoomAreaM2 {
            issues.append(.init(.sizeBounds, entityId: room.id,
                                "this room is \(String(format: "%.1f", area)) m²; the maximum for one room is \(Int(HomeSizeBounds.maxRoomAreaM2)) m²"))
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
        for (label, value) in [("width_m", opening.width_m), ("height_m", opening.height_m),
                               ("sill_height_m", opening.sill_height_m)]
        where value > HomeSizeBounds.maxOpeningDimM {
            issues.append(.init(.sizeBounds, entityId: id,
                                "\(label) \(value) exceeds the maximum of \(Int(HomeSizeBounds.maxOpeningDimM)) m"))
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
            issues += validatePolygonBounds(stair.footprint, entityId: stair.id,
                                            what: "this staircase footprint")
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
