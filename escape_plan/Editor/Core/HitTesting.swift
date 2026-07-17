//  HitTesting.swift — "what did the user just tap?", in floor-local meters.
//
//  Deliberately pure and SceneKit-free. The SceneKit bridge's only job is to turn a touch into
//  a floor-local point; the decision of what that point SELECTS is made here, where it can be
//  tested without a device. Handle sizes are in meters and are converted from screen points by
//  the bridge, because a 44pt touch target covers a different number of meters at every zoom.

import Foundation

public enum HitTesting {

    /// Pick radii in meters, resolved by the bridge from the current camera zoom.
    public struct Tolerances: Equatable, Sendable {
        public var vertexRadiusM: Double
        public var wallRadiusM: Double

        public init(vertexRadiusM: Double = 0.3, wallRadiusM: Double = 0.2) {
            self.vertexRadiusM = vertexRadiusM
            self.wallRadiusM = wallRadiusM
        }

        public static let `default` = Tolerances()
    }

    /// Resolves a tap to a selection on ONE floor (per-floor edit isolation — you can never
    /// select geometry on a floor you aren't editing).
    ///
    /// Priority: vertex, then wall, then room interior. Corners beat walls because a corner
    /// always sits ON two walls — testing walls first would make vertices unselectable.
    /// Openings beat walls in turn, since a door is a smaller target sitting on a wall.
    public static func hitTest(_ point: Point2D, floor: Floor,
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
        // Last room wins: rooms drawn later sit on top, so overlapping footprints resolve the
        // way they look.
        for room in floor.rooms.reversed() where Geometry.contains(room.polygon, point) {
            return .room(roomId: room.id)
        }
        return .none
    }

    public static func nearestVertex(_ point: Point2D, floor: Floor,
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

    public static func nearestWall(_ point: Point2D, floor: Floor,
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
    public static func nearestOpening(_ point: Point2D, floor: Floor,
                                      within radius: Double) -> Selection? {
        var best: (Selection, Double)?
        for opening in floor.openings {
            let seg = opening.wallSegment
            guard let host = floor.room(seg.roomId),
                  let edge = Geometry.edge(host.polygon, seg.edgeIndex) else { continue }

            let (hit, t) = Geometry.closestPointOnSegment(point, edge.a, edge.b)
            let d = Geometry.distance(point, hit)
            guard d <= radius, t >= seg.t0, t <= seg.t1 else { continue }
            if d < (best?.1 ?? .infinity) {
                best = (.opening(openingId: opening.id), d)
            }
        }
        return best?.0
    }

    /// Scan-derived items the editor should badge for review (S2.2 renders the pulsing
    /// outline). Low-confidence items are flagged, never silently dropped — that rule is the
    /// reason `confidence` is required on scan items at all.
    public static let needsReviewThreshold = 0.5

    public static func needsReview(source: SourceKind, confidence: Double?) -> Bool {
        guard source == .scan else { return false }
        // A scan item with no confidence is a contract violation the validator catches; treat
        // it as needing review rather than trusting it.
        guard let c = confidence else { return true }
        return c < needsReviewThreshold
    }

    /// Every id on a floor that should carry the "needs review" treatment.
    public static func itemsNeedingReview(floor: Floor) -> [String] {
        var ids: [String] = []
        for room in floor.rooms where needsReview(source: room.source, confidence: room.confidence) {
            ids.append(room.id)
        }
        for o in floor.openings where needsReview(source: o.source, confidence: o.confidence) {
            ids.append(o.id)
        }
        return ids
    }
}
