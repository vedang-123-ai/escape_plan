//  Geometry.swift — pure 2D polygon math for the editor core.
//
//  No I/O, no globals, no UIKit/SceneKit. Deterministic: same input -> same output.
//  Mirrors the geometry invariants enforced by backend/app/models.py so that a model the
//  editor accepts is a model the backend accepts.

import Foundation

enum Geometry {

    /// Distances below this are treated as zero. 1e-6 m = 1 micron: far below the 1 cm the
    /// editor's snapping works in, far above Double noise on meter-scale coordinates.
    static let epsilon = 1e-6

    // MARK: - Vectors

    static func add(_ a: Point, _ b: Point) -> Point {
        Point(a.x + b.x, a.y + b.y)
    }

    static func subtract(_ a: Point, _ b: Point) -> Point {
        Point(a.x - b.x, a.y - b.y)
    }

    static func scale(_ a: Point, _ k: Double) -> Point {
        Point(a.x * k, a.y * k)
    }

    static func dot(_ a: Point, _ b: Point) -> Double {
        a.x * b.x + a.y * b.y
    }

    /// z-component of the 3D cross product — sign gives orientation of the turn a->b.
    static func cross(_ a: Point, _ b: Point) -> Double {
        a.x * b.y - a.y * b.x
    }

    static func length(_ a: Point) -> Double {
        (a.x * a.x + a.y * a.y).squareRoot()
    }

    static func distance(_ a: Point, _ b: Point) -> Double {
        length(subtract(a, b))
    }

    // MARK: - Polygons

    /// Positive for counter-clockwise, negative for clockwise (shoelace formula).
    static func signedArea(_ polygon: [Point]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var sum = 0.0
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            sum += cross(a, b)
        }
        return sum / 2
    }

    static func area(_ polygon: [Point]) -> Double { abs(signedArea(polygon)) }

    static func isCounterClockwise(_ polygon: [Point]) -> Bool {
        signedArea(polygon) > epsilon
    }

    /// Reverses vertex order. Note this renumbers edges — any `wall_segment.edge_index`
    /// pointing into this polygon becomes wrong, so the editor never calls it on a room that
    /// already hosts openings (see `HomeModelStore`, which rejects rather than reorients).
    static func reversed(_ polygon: [Point]) -> [Point] {
        polygon.reversed()
    }

    /// Edge i of a polygon: vertex i -> vertex (i+1) mod n. This is THE schema convention.
    static func edge(_ polygon: [Point], _ index: Int) -> (a: Point, b: Point)? {
        guard polygon.count >= 3, index >= 0, index < polygon.count else { return nil }
        return (polygon[index], polygon[(index + 1) % polygon.count])
    }

    /// The point at normalized position `t` along edge `index` — how the schema's parametric
    /// opening placement resolves to a world position.
    static func pointOnEdge(_ polygon: [Point], edgeIndex: Int, t: Double) -> Point? {
        guard let e = edge(polygon, edgeIndex) else { return nil }
        return add(e.a, scale(subtract(e.b, e.a), t))
    }

    /// A polygon is simple when no edge crosses another and no vertex is duplicated.
    /// Adjacent edges are allowed to touch only at their shared vertex.
    static func isSimple(_ polygon: [Point]) -> Bool {
        let n = polygon.count
        guard n >= 3 else { return false }

        // Degenerate (zero-length) edges: a repeated vertex.
        for i in 0..<n where distance(polygon[i], polygon[(i + 1) % n]) < epsilon {
            return false
        }
        // Non-adjacent vertices coinciding pinches the polygon into a figure-8.
        for i in 0..<n {
            for j in (i + 1)..<n where distance(polygon[i], polygon[j]) < epsilon {
                return false
            }
        }
        for i in 0..<n {
            let a = (polygon[i], polygon[(i + 1) % n])
            for j in (i + 1)..<n {
                let adjacent = (j == i + 1) || (i == 0 && j == n - 1)
                let b = (polygon[j], polygon[(j + 1) % n])
                if adjacent {
                    // Sharing a vertex is fine; overlapping (collinear, doubling back) is not.
                    if segmentsOverlapCollinearly(a.0, a.1, b.0, b.1) { return false }
                } else if segmentsIntersect(a.0, a.1, b.0, b.1) {
                    return false
                }
            }
        }
        return true
    }

    /// Convenience: the full room-polygon contract from the schema.
    static func isValidRoomPolygon(_ polygon: [Point]) -> Bool {
        polygon.count >= 3 && isSimple(polygon) && isCounterClockwise(polygon)
    }

    static func translate(_ polygon: [Point], by delta: Point) -> [Point] {
        polygon.map { add($0, delta) }
    }

    static func centroid(_ polygon: [Point]) -> Point {
        guard !polygon.isEmpty else { return Point(0, 0) }
        let sx = polygon.reduce(0) { $0 + $1.x }
        let sy = polygon.reduce(0) { $0 + $1.y }
        return Point(sx / Double(polygon.count), sy / Double(polygon.count))
    }

    /// Axis-aligned CCW rectangle — the shape "add room" drops on the floor.
    static func rectangle(origin: Point, width: Double, height: Double) -> [Point] {
        [
            origin,
            Point(origin.x + width, origin.y),
            Point(origin.x + width, origin.y + height),
            Point(origin.x, origin.y + height),
        ]
    }

    // MARK: - Segments

    /// Sign of the turn p->q->r: +1 counter-clockwise, -1 clockwise, 0 collinear.
    static func orientation(_ p: Point, _ q: Point, _ r: Point) -> Int {
        let v = cross(subtract(q, p), subtract(r, p))
        if v > epsilon { return 1 }
        if v < -epsilon { return -1 }
        return 0
    }

    static func segmentsIntersect(_ p1: Point, _ p2: Point,
                                         _ q1: Point, _ q2: Point) -> Bool {
        let o1 = orientation(p1, p2, q1)
        let o2 = orientation(p1, p2, q2)
        let o3 = orientation(q1, q2, p1)
        let o4 = orientation(q1, q2, p2)

        if o1 != o2 && o3 != o4 { return true }

        // Collinear touching cases.
        if o1 == 0 && isOnSegment(p1, p2, q1) { return true }
        if o2 == 0 && isOnSegment(p1, p2, q2) { return true }
        if o3 == 0 && isOnSegment(q1, q2, p1) { return true }
        if o4 == 0 && isOnSegment(q1, q2, p2) { return true }
        return false
    }

    /// True when two collinear segments share more than a single point.
    static func segmentsOverlapCollinearly(_ p1: Point, _ p2: Point,
                                                  _ q1: Point, _ q2: Point) -> Bool {
        guard orientation(p1, p2, q1) == 0, orientation(p1, p2, q2) == 0 else { return false }
        let d = subtract(p2, p1)
        let len2 = dot(d, d)
        guard len2 > epsilon else { return false }
        // Project both q's onto the p-segment's parameter axis and test interval overlap.
        let tq1 = dot(subtract(q1, p1), d) / len2
        let tq2 = dot(subtract(q2, p1), d) / len2
        let lo = min(tq1, tq2)
        let hi = max(tq1, tq2)
        let overlap = min(hi, 1.0) - max(lo, 0.0)
        return overlap > epsilon
    }

    /// Assumes `r` is collinear with the segment.
    static func isOnSegment(_ p1: Point, _ p2: Point, _ r: Point) -> Bool {
        r.x >= min(p1.x, p2.x) - epsilon && r.x <= max(p1.x, p2.x) + epsilon
            && r.y >= min(p1.y, p2.y) - epsilon && r.y <= max(p1.y, p2.y) + epsilon
    }

    /// Nearest point on segment a-b to p, plus its normalized position `t` along the segment.
    static func closestPointOnSegment(_ p: Point, _ a: Point,
                                             _ b: Point) -> (point: Point, t: Double) {
        let d = subtract(b, a)
        let len2 = dot(d, d)
        guard len2 > epsilon else { return (a, 0) }
        let t = min(1, max(0, dot(subtract(p, a), d) / len2))
        return (add(a, scale(d, t)), t)
    }

    static func distanceToSegment(_ p: Point, _ a: Point, _ b: Point) -> Double {
        distance(p, closestPointOnSegment(p, a, b).point)
    }

    // MARK: - Containment

    /// Ray casting. Used for hit-testing a tap against a room footprint.
    static func contains(_ polygon: [Point], _ p: Point) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i]
            let b = polygon[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
