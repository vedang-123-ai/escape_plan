import CoreGraphics
import Foundation
import SceneKit

/// Pure geometry helpers shared by the scene builder. No SceneKit node construction here and no
/// I/O — everything is a function of the HomeModel, so it can be unit-tested without a renderer.
///
/// Coordinate mapping, fixed once here: the schema's floor-local plan frame (x, y) in meters maps
/// to SceneKit as **x → x, y → −z**, with **+y up** for height. Plan-north is −z, which means a
/// camera looking down −z sees the plan the same way up as the JSON reads.
enum DollhouseGeometry {

    // MARK: - Frame mapping

    static func scenePoint(_ p: Point, y: Double) -> SCNVector3 {
        SCNVector3(Float(p.x), Float(y), Float(-p.y))
    }

    // MARK: - Polygon basics

    /// Edge `i` of a polygon runs vertex `i` → vertex `(i+1) % count`. This is the schema's
    /// convention and the meaning of `wall_segment.edge_index`.
    static func edge(_ polygon: [Point], _ index: Int) -> (a: Point, b: Point)? {
        guard polygon.count >= 3, index >= 0, index < polygon.count else { return nil }
        return (polygon[index], polygon[(index + 1) % polygon.count])
    }

    /// Point at normalized position `t` along an edge (0 = vertex i, 1 = vertex i+1).
    static func pointOnEdge(_ polygon: [Point], edgeIndex: Int, t: Double) -> Point? {
        guard let e = edge(polygon, edgeIndex) else { return nil }
        return Point(x: e.a.x + (e.b.x - e.a.x) * t,
                     y: e.a.y + (e.b.y - e.a.y) * t)
    }

    static func length(from a: Point, to b: Point) -> Double {
        (((b.x - a.x) * (b.x - a.x)) + ((b.y - a.y) * (b.y - a.y))).squareRoot()
    }

    /// Heading of the edge in the scene's XZ plane, as a rotation about +y.
    /// A box whose local +x runs along the edge gets this as its `eulerAngles.y`.
    static func sceneYaw(from a: Point, to b: Point) -> Double {
        // Plan +y maps to scene −z, so the scene-space direction is (dx, −dy).
        atan2(-(b.y - a.y), b.x - a.x)
    }

    /// Area-weighted centroid of a simple polygon (falls back to the vertex mean if the polygon
    /// is degenerate, so a bad footprint places a label imprecisely rather than at NaN).
    static func centroid(_ polygon: [Point]) -> Point {
        guard polygon.count >= 3 else { return vertexMean(polygon) }
        var doubleArea = 0.0
        var cx = 0.0
        var cy = 0.0
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[(i + 1) % polygon.count]
            let cross = a.x * b.y - b.x * a.y
            doubleArea += cross
            cx += (a.x + b.x) * cross
            cy += (a.y + b.y) * cross
        }
        guard abs(doubleArea) > 1e-9 else { return vertexMean(polygon) }
        let factor = 1.0 / (3.0 * doubleArea)
        return Point(x: cx * factor, y: cy * factor)
    }

    private static func vertexMean(_ polygon: [Point]) -> Point {
        guard !polygon.isEmpty else { return Point(x: 0, y: 0) }
        let sx = polygon.reduce(0) { $0 + $1.x }
        let sy = polygon.reduce(0) { $0 + $1.y }
        return Point(x: sx / Double(polygon.count), y: sy / Double(polygon.count))
    }

    static func path(for polygon: [Point]) -> CGPath? {
        guard polygon.count >= 3 else { return nil }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
        for p in polygon.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Bounds

    struct PlanBounds {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        var isEmpty: Bool { minX > maxX }
        var width: Double { isEmpty ? 0 : maxX - minX }
        var depth: Double { isEmpty ? 0 : maxY - minY }
        var center: Point { Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }

        mutating func extend(_ p: Point) {
            minX = Swift.min(minX, p.x)
            minY = Swift.min(minY, p.y)
            maxX = Swift.max(maxX, p.x)
            maxY = Swift.max(maxY, p.y)
        }
    }

    /// Plan-space extent of every room on every floor.
    static func bounds(of home: HomeModel) -> PlanBounds {
        var b = PlanBounds()
        for floor in home.floors {
            for room in floor.rooms {
                for p in room.polygon { b.extend(p) }
            }
        }
        return b
    }

    // MARK: - Floor stacking

    /// Base height (y) of each floor, keyed by floor id: floors stack by `level`, each sitting on
    /// the accumulated `height_m` of the floors beneath it. Gaps between non-contiguous levels
    /// (e.g. a basement with no ground floor authored) are not invented — floors simply stack in
    /// level order.
    static func floorBaseHeights(of home: HomeModel) -> [String: Double] {
        var result: [String: Double] = [:]
        var y = 0.0
        for floor in home.floorsByLevel {
            result[floor.id] = y
            y += floor.height_m
        }
        return result
    }

    // MARK: - Walls

    /// One wall of a room's footprint, ready to become a box.
    struct WallSpec {
        var a: Point
        var b: Point
        var length: Double
        var yaw: Double
        var midpoint: Point
    }

    /// Deduplicated walls for a floor. Adjacent rooms each own the shared wall in their own
    /// polygon; rendering both would put two coplanar transparent boxes in the same place and
    /// z-fight. Keying on the rounded, unordered endpoint pair collapses them to one.
    static func walls(for floor: Floor) -> [WallSpec] {
        var seen = Set<String>()
        var specs: [WallSpec] = []
        for room in floor.rooms {
            for i in 0..<room.polygon.count {
                guard let e = edge(room.polygon, i) else { continue }
                let key = wallKey(e.a, e.b)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let len = length(from: e.a, to: e.b)
                guard len > 1e-6 else { continue }
                specs.append(WallSpec(
                    a: e.a,
                    b: e.b,
                    length: len,
                    yaw: sceneYaw(from: e.a, to: e.b),
                    midpoint: Point(x: (e.a.x + e.b.x) / 2, y: (e.a.y + e.b.y) / 2)
                ))
            }
        }
        return specs
    }

    /// Order-independent key at 1 mm resolution, so room A's edge (p→q) and room B's edge (q→p)
    /// hash to the same wall.
    private static func wallKey(_ a: Point, _ b: Point) -> String {
        let ka = String(format: "%.3f,%.3f", a.x, a.y)
        let kb = String(format: "%.3f,%.3f", b.x, b.y)
        return ka < kb ? "\(ka)|\(kb)" : "\(kb)|\(ka)"
    }

    // MARK: - Openings

    /// Where an opening sits in the world, derived entirely from its parametric wall reference.
    struct OpeningPlacement {
        /// Center of the opening in plan coordinates.
        var center: Point
        /// Rotation about +y so the marker's local +x runs along the host wall.
        var yaw: Double
        /// Clear width in meters — from `width_m`, which is authoritative for size.
        var width: Double
        var height: Double
        /// Bottom of the opening above its floor.
        var sill: Double
    }

    /// Resolve `wall_segment` (room polygon edge + t-range) into a world placement.
    ///
    /// The t-range is *placement* and `width_m` is *size* (schema: "the t-range is placement, not
    /// size"), so the marker is centered on the midpoint of [t0, t1] and sized by `width_m`. It is
    /// clamped to the host edge so a marker can never overhang past a wall's ends.
    /// Returns nil when the reference dangles — a bad `room_id` or an out-of-range `edge_index`
    /// is a data error the caller should surface, not silently place at the origin.
    static func placement(for opening: Opening, on floor: Floor) -> OpeningPlacement? {
        guard let room = floor.rooms.first(where: { $0.id == opening.wall_segment.room_id }),
              let e = edge(room.polygon, opening.wall_segment.edge_index)
        else { return nil }

        let edgeLength = length(from: e.a, to: e.b)
        guard edgeLength > 1e-6 else { return nil }

        let tMid = (opening.wall_segment.t0 + opening.wall_segment.t1) / 2
        let width = min(opening.width_m, edgeLength)
        // Keep the marker inside the wall it belongs to.
        let halfSpanT = (width / edgeLength) / 2
        let tClamped = min(max(tMid, halfSpanT), 1 - halfSpanT)

        guard let center = pointOnEdge(room.polygon, edgeIndex: opening.wall_segment.edge_index, t: tClamped)
        else { return nil }

        return OpeningPlacement(
            center: center,
            yaw: sceneYaw(from: e.a, to: e.b),
            width: width,
            height: opening.height_m,
            sill: opening.sill_height_m
        )
    }
}
