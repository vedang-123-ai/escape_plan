//  OpeningPlacement.swift — pure placement math for putting doors/windows on walls.
//
//  The editor never asks the user "interior or exterior?" — it derives that from geometry:
//  if another room's footprint shares the host wall along the opening's span, the opening
//  connects the two rooms; otherwise it faces EXTERIOR (which is exactly what makes a door an
//  exit in the schema, and an exterior window an egress-window candidate). Derivation happens
//  at CREATION time only: drags never rewrite `room_ids`, because scan-derived homes may
//  encode adjacency the geometry can't reproduce exactly (RoomPlan footprints don't share
//  wall lines the way snapped manual rooms do).
//
//  Pure Foundation, same rules as the rest of Editor/Core.

import Foundation

enum OpeningPlacement {

    /// Editor defaults per kind, in meters. These are editor conveniences (matching the
    /// hand-authored fixtures in schema/fixtures/), not safety guidance — egress viability is
    /// always the backend annotator's call.
    struct Defaults: Equatable, Sendable {
        let width_m: Double
        let height_m: Double
        let sill_height_m: Double
    }

    static func defaults(for kind: OpeningKind) -> Defaults {
        switch kind {
        case .door: return Defaults(width_m: 0.9, height_m: 2.0, sill_height_m: 0.0)
        case .window: return Defaults(width_m: 1.0, height_m: 1.2, sill_height_m: 0.8)
        }
    }

    /// t0/t1 for an opening of `width_m` centered as close to `centerT` as the edge allows —
    /// the span slides inward rather than hanging off a wall end. nil when the edge is too
    /// short to host the opening at all.
    static func span(centerT: Double, width_m: Double,
                     edgeLength: Double) -> (t0: Double, t1: Double)? {
        guard edgeLength > Geometry.epsilon, width_m > 0, width_m <= edgeLength else {
            return nil
        }
        let halfT = (width_m / 2) / edgeLength
        let clamped = min(1 - halfT, max(halfT, centerT))
        return (clamped - halfT, clamped + halfT)
    }

    /// The room (other than the host) whose footprint runs along the host wall for the span
    /// [t0, t1] — i.e. the room you'd step into through this opening. nil means that stretch
    /// of wall faces the exterior.
    ///
    /// Adjacency = collinear overlap (Geometry.segmentsOverlapCollinearly) between the
    /// opening's sub-segment and any edge of another room on the same floor. Exact
    /// collinearity is the right test for manually built rooms, whose shared walls coincide
    /// by construction (snapping); it is deliberately NOT a tolerance match — see header.
    static func adjacentRoom(on floor: Floor, hostRoomId: String, edgeIndex: Int,
                             t0: Double, t1: Double) -> Room? {
        guard let host = floor.room(hostRoomId),
              let a = Geometry.pointOnEdge(host.polygon, edgeIndex: edgeIndex, t: t0),
              let b = Geometry.pointOnEdge(host.polygon, edgeIndex: edgeIndex, t: t1) else {
            return nil
        }
        for room in floor.rooms where room.id != hostRoomId {
            let n = room.polygon.count
            guard n >= 3 else { continue }
            for i in 0..<n {
                let p = room.polygon[i]
                let q = room.polygon[(i + 1) % n]
                if Geometry.segmentsOverlapCollinearly(a, b, p, q) {
                    return room
                }
            }
        }
        return nil
    }
}
