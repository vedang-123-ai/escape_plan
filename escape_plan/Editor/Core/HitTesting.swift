//  HitTesting.swift — "what did the user just tap?", in floor-local meters.
//
//  Deliberately pure and SceneKit-free. The SceneKit bridge's only job is to turn a touch into
//  a floor-local point; the decision of what that point SELECTS is made here, where it can be
//  tested without a device. Handle sizes are in meters and are converted from screen points by
//  the bridge, because a 44pt touch target covers a different number of meters at every zoom.

import Foundation

enum HitTesting {

    /// Pick radii in meters, resolved by the bridge from the current camera zoom.
    struct Tolerances: Equatable, Sendable {
        var vertexRadiusM: Double
        var wallRadiusM: Double

        init(vertexRadiusM: Double = 0.3, wallRadiusM: Double = 0.2) {
            self.vertexRadiusM = vertexRadiusM
            self.wallRadiusM = wallRadiusM
        }

        static let `default` = Tolerances()
    }

    /// Resolves a tap to a selection on ONE floor (per-floor edit isolation — you can never
    /// select geometry on a floor you aren't editing).
    ///
    /// Priority: vertex, then wall, then room interior. Corners beat walls because a corner
    /// always sits ON two walls — testing walls first would make vertices unselectable.
    /// Openings beat walls in turn, since a door is a smaller target sitting on a wall.
    static func hitTest(_ point: Point, floor: Floor,
                               tolerances: Tolerances = .default) -> Selection {
        if let v = nearestVertex(point, floor: floor, within: tolerances.vertexRadiusM) {
            return v
        }
        if let o = nearestOpening(point, floor: floor, within: tolerances.wallRadiusM) {
            return o
        }
        if let w = nearestWall(point, floor: floor, within: tolerances.wallRadiusM) {
            return w
        }
        // Objects sit on top of the room slab, so they win over the room interior.
        if let o = topObject(point, floor: floor) {
            return o
        }
        // Last room wins: rooms drawn later sit on top, so overlapping footprints resolve the
        // way they look.
        for room in floor.rooms.reversed() where Geometry.contains(room.polygon, point) {
            return .room(roomId: room.id)
        }
        return .none
    }

    /// Topmost (last-listed) object whose rotated footprint contains the point.
    static func topObject(_ point: Point, floor: Floor) -> Selection? {
        for object in floor.objects.reversed() where objectContains(object, point) {
            return .object(objectId: object.id)
        }
        return nil
    }

    /// Point-in-rotated-rect: transform the point into the object's local frame (translate to
    /// its center, rotate by −rotation), then it's an axis-aligned half-extent test.
    static func objectContains(_ object: FloorObject, _ point: Point) -> Bool {
        guard object.size_m.count == 2 else { return false }
        let angle = -object.rotation_deg * .pi / 180
        let dx = point.x - object.center.x
        let dy = point.y - object.center.y
        let localX = dx * cos(angle) - dy * sin(angle)
        let localY = dx * sin(angle) + dy * cos(angle)
        return abs(localX) <= object.size_m[0] / 2 + Geometry.epsilon
            && abs(localY) <= object.size_m[1] / 2 + Geometry.epsilon
    }

    static func nearestVertex(_ point: Point, floor: Floor,
                                     within radius: Double) -> Selection? {
        var best: (Selection, Double)?
        for room in floor.rooms {
            for (i, v) in room.polygon.enumerated() {
                let d = Geometry.distance(point, v)
                if d <= radius, d < (best?.1 ?? .infinity) {
                    best = (.vertex(roomId: room.id, vertexIndex: i), d)
                }
            }
        }
        return best?.0
    }

    static func nearestWall(_ point: Point, floor: Floor,
                                   within radius: Double) -> Selection? {
        var best: (Selection, Double)?
        for room in floor.rooms {
            let n = room.polygon.count
            guard n >= 3 else { continue }
            for i in 0..<n {
                let d = Geometry.distanceToSegment(point, room.polygon[i], room.polygon[(i + 1) % n])
                if d <= radius, d < (best?.1 ?? .infinity) {
                    best = (.wall(roomId: room.id, edgeIndex: i), d)
                }
            }
        }
        return best?.0
    }

    /// An opening is hit when the tap is close to the wall AND within the opening's t-range —
    /// which is exactly how the schema defines where it lives.
    static func nearestOpening(_ point: Point, floor: Floor,
                                      within radius: Double) -> Selection? {
        var best: (Selection, Double)?
        for opening in floor.openings {
            let seg = opening.wall_segment
            guard let host = floor.room(seg.room_id),
                  let edge = Geometry.edge(host.polygon, seg.edge_index) else { continue }

            let (hit, t) = Geometry.closestPointOnSegment(point, edge.a, edge.b)
            let d = Geometry.distance(point, hit)
            guard d <= radius, t >= seg.t0, t <= seg.t1 else { continue }
            if d < (best?.1 ?? .infinity) {
                best = (.opening(openingId: opening.id), d)
            }
        }
        return best?.0
    }

    /// Resolves a tap to a position ON a wall — the placement query behind the Add Door /
    /// Add Window tools. Same nearest-wall scan as `nearestWall`, but returns the parametric
    /// (roomId, edgeIndex, t) the `addOpening` action wants instead of a Selection.
    static func wallPoint(_ point: Point, floor: Floor,
                          within radius: Double) -> (roomId: String, edgeIndex: Int, t: Double)? {
        var best: ((roomId: String, edgeIndex: Int, t: Double), Double)?
        for room in floor.rooms {
            let n = room.polygon.count
            guard n >= 3 else { continue }
            for i in 0..<n {
                let (_, t) = Geometry.closestPointOnSegment(point, room.polygon[i],
                                                            room.polygon[(i + 1) % n])
                let d = Geometry.distanceToSegment(point, room.polygon[i], room.polygon[(i + 1) % n])
                if d <= radius, d < (best?.1 ?? .infinity) {
                    best = ((roomId: room.id, edgeIndex: i, t: t), d)
                }
            }
        }
        return best?.0
    }

    /// Scan-derived items the editor should badge for review (S2.2 renders the pulsing
    /// outline). Low-confidence items are flagged, never silently dropped — that rule is the
    /// reason `confidence` is required on scan items at all.
    static let needsReviewThreshold = 0.5

    static func needsReview(source: Source, confidence: Double?) -> Bool {
        switch source {
        case .manual:
            return false
        case .ai_plan:
            // An AI-drafted element ALWAYS needs review, whatever its confidence —
            // the review gate is the whole safety story of the plan-import feature.
            return true
        case .scan:
            // A scan item with no confidence is a contract violation the validator
            // catches; treat it as needing review rather than trusting it.
            guard let c = confidence else { return true }
            return c < needsReviewThreshold
        }
    }

    /// Every id on a floor that should carry the "needs review" treatment.
    static func itemsNeedingReview(floor: Floor) -> [String] {
        var ids: [String] = []
        for room in floor.rooms where needsReview(source: room.source, confidence: room.confidence) {
            ids.append(room.id)
        }
        for o in floor.openings where needsReview(source: o.source, confidence: o.confidence) {
            ids.append(o.id)
        }
        for o in floor.objects where needsReview(source: o.source, confidence: o.confidence) {
            ids.append(o.id)
        }
        return ids
    }
}
