import Foundation
import SceneKit

/// Pure geometry for the S2.3 route overlay, in the `DollhouseGeometry` mold: no node
/// construction, no I/O — functions of a `Route`, so everything unit-tests without a renderer.
///
/// Routes arrive as 2D floor-local waypoints. This module splits them into per-floor runs
/// (floor-LOCAL scene coordinates, so nodes parented under `"floor:<id>"` inherit base height,
/// explode lift, and floor visibility for free), smooths them, and turns polylines into tube
/// meshes with arc-length UVs — the `u` coordinate is what makes the pulse shader directional.
enum RouteGeometry {

    /// Height above the slab top at which route tubes float.
    static let routeLiftM = 0.22

    /// One drawable stretch of a route confined to a single floor.
    struct FloorRun {
        let floorID: String
        var points: [SCNVector3]
        /// This run begins where a stair crossing landed (route continues from another floor).
        var startsAtStair: Bool
        /// This run ends at a stair crossing (route continues on another floor).
        var endsAtStair: Bool
    }

    // MARK: - Waypoints → per-floor runs

    /// Split a route at floor crossings. Consecutive waypoints on different floors mark a
    /// crossing: the earlier run closes (`endsAtStair`) and the next opens (`startsAtStair`).
    /// Runs on floors the dollhouse doesn't have are dropped and reported, mirroring the
    /// builder's BuildIssue philosophy — bad data is surfaced, not swallowed.
    static func floorRuns(for route: Route,
                          knownFloorIDs: Set<String>) -> (runs: [FloorRun], droppedFloorIDs: [String]) {
        var runs: [FloorRun] = []
        var current: FloorRun?

        for waypoint in route.waypoints {
            let p = DollhouseGeometry.scenePoint(Point(x: waypoint.x, y: waypoint.y), y: routeLiftM)
            if current?.floorID == waypoint.floor_id {
                current?.points.append(p)
            } else {
                if var finished = current {
                    finished.endsAtStair = true
                    runs.append(finished)
                }
                current = FloorRun(floorID: waypoint.floor_id, points: [p],
                                   startsAtStair: current != nil, endsAtStair: false)
            }
        }
        if let finished = current { runs.append(finished) }

        var kept: [FloorRun] = []
        var dropped: Set<String> = []
        for var run in runs {
            guard knownFloorIDs.contains(run.floorID) else {
                dropped.insert(run.floorID)
                continue
            }
            run.points = dedupe(run.points)
            kept.append(run)
        }
        return (kept, dropped.sorted())
    }

    /// Drop consecutive points closer than ~0.1 mm (the exterior waypoint duplicates its
    /// opening's coordinates; Catmull-Rom misbehaves on zero-length segments).
    static func dedupe(_ points: [SCNVector3], epsilon: Float = 1e-4) -> [SCNVector3] {
        var out: [SCNVector3] = []
        for p in points {
            if let last = out.last, simd_distance(simd(last), simd(p)) < epsilon { continue }
            out.append(p)
        }
        return out
    }

    // MARK: - Smoothing

    /// Uniform Catmull-Rom through the control points, endpoint-clamped by duplicating the
    /// first and last points. Passes through every control point.
    static func catmullRom(_ points: [SCNVector3], samplesPerSegment: Int = 8) -> [SCNVector3] {
        guard points.count >= 3, samplesPerSegment >= 2 else { return points }
        let ext = [points[0]] + points + [points[points.count - 1]]
        var out: [SCNVector3] = []
        for i in 0..<(points.count - 1) {
            let p0 = simd(ext[i]), p1 = simd(ext[i + 1]), p2 = simd(ext[i + 2]), p3 = simd(ext[i + 3])
            for s in 0..<samplesPerSegment {
                let t = Float(s) / Float(samplesPerSegment)
                let t2 = t * t
                let t3 = t2 * t
                var v = 2 * p1
                v += (p2 - p0) * t
                v += (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                v += (3 * p1 - p0 - 3 * p2 + p3) * t3
                out.append(SCNVector3(v * 0.5))
            }
        }
        out.append(points[points.count - 1])
        return out
    }

    // MARK: - Arc length

    /// Cumulative distance at each point; `[0, …, totalLength]`. Drives constant-speed tour
    /// sampling and the tube's directional UVs.
    static func arcLengths(_ points: [SCNVector3]) -> [Float] {
        var out: [Float] = points.isEmpty ? [] : [0]
        for i in 1..<max(points.count, 1) {
            out.append(out[i - 1] + simd_distance(simd(points[i - 1]), simd(points[i])))
        }
        return out
    }

    /// Point at `distance` along the polyline (clamped to its ends).
    static func point(at distance: Float, along points: [SCNVector3], arcs: [Float]) -> SCNVector3 {
        guard let total = arcs.last, points.count == arcs.count, !points.isEmpty else {
            return points.first ?? SCNVector3Zero
        }
        let d = min(max(distance, 0), total)
        var i = 1
        while i < arcs.count && arcs[i] < d { i += 1 }
        guard i < arcs.count else { return points[points.count - 1] }
        let span = arcs[i] - arcs[i - 1]
        let t = span > 1e-6 ? (d - arcs[i - 1]) / span : 0
        return SCNVector3(simd_mix(simd(points[i - 1]), simd(points[i]), SIMD3(repeating: t)))
    }

    // MARK: - Tube mesh

    struct TubeMesh {
        var positions: [SCNVector3]
        var normals: [SCNVector3]
        /// `u` = arc-length position 0→1 along the tube, `v` = position around the ring.
        var uvs: [CGPoint]
        var indices: [Int32]
    }

    /// Vertex data for a tube following `points`: one ring per point, oriented by
    /// parallel-transport frames (minimal rotation between samples — no twist artifacts on
    /// the vertical stair stubs). Returns nil for degenerate input.
    static func tubeMesh(points rawPoints: [SCNVector3],
                         radius: Float,
                         radialSegments: Int = 8) -> TubeMesh? {
        let points = dedupe(rawPoints)
        guard points.count >= 2, radialSegments >= 3, radius > 0 else { return nil }
        let arcs = arcLengths(points)
        guard let total = arcs.last, total > 1e-5 else { return nil }

        var tangents: [SIMD3<Float>] = []
        for i in 0..<points.count {
            let prev = simd(points[max(i - 1, 0)])
            let next = simd(points[min(i + 1, points.count - 1)])
            let d = next - prev
            tangents.append(simd_length(d) > 1e-6 ? simd_normalize(d) : SIMD3(1, 0, 0))
        }

        // Parallel transport: start with any normal ⟂ tangent, then re-project it at each step.
        var normalsAlong: [SIMD3<Float>] = []
        var n = perpendicular(to: tangents[0])
        normalsAlong.append(n)
        for i in 1..<tangents.count {
            let projected = n - tangents[i] * simd_dot(n, tangents[i])
            n = simd_length(projected) > 1e-6 ? simd_normalize(projected) : perpendicular(to: tangents[i])
            normalsAlong.append(n)
        }

        var mesh = TubeMesh(positions: [], normals: [], uvs: [], indices: [])
        for i in 0..<points.count {
            let center = simd(points[i])
            let normal = normalsAlong[i]
            let binormal = simd_normalize(simd_cross(tangents[i], normal))
            let u = CGFloat(arcs[i] / total)
            for j in 0..<radialSegments {
                let angle = Float(j) / Float(radialSegments) * 2 * .pi
                let radial = normal * cos(angle) + binormal * sin(angle)
                mesh.positions.append(SCNVector3(center + radial * radius))
                mesh.normals.append(SCNVector3(radial))
                mesh.uvs.append(CGPoint(x: u, y: CGFloat(j) / CGFloat(radialSegments)))
            }
        }
        for i in 0..<(points.count - 1) {
            for j in 0..<radialSegments {
                let a = Int32(i * radialSegments + j)
                let b = Int32(i * radialSegments + (j + 1) % radialSegments)
                let c = Int32((i + 1) * radialSegments + j)
                let d = Int32((i + 1) * radialSegments + (j + 1) % radialSegments)
                mesh.indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return mesh
    }

    /// Tube as a single SCNGeometry (one draw call — required for the pulse to travel the
    /// whole path as one continuous animation).
    static func tubeGeometry(points: [SCNVector3],
                             radius: Float,
                             radialSegments: Int = 8) -> SCNGeometry? {
        guard let mesh = tubeMesh(points: points, radius: radius, radialSegments: radialSegments)
        else { return nil }
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: mesh.positions),
                SCNGeometrySource(normals: mesh.normals),
                SCNGeometrySource(textureCoordinates: mesh.uvs),
            ],
            elements: [element]
        )
    }

    // MARK: -

    private static func perpendicular(to t: SIMD3<Float>) -> SIMD3<Float> {
        // Pick the world axis least aligned with the tangent, then Gram-Schmidt it.
        let axis: SIMD3<Float> = abs(t.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)
        return simd_normalize(axis - t * simd_dot(axis, t))
    }

    private static func simd(_ v: SCNVector3) -> SIMD3<Float> {
        SIMD3(Float(v.x), Float(v.y), Float(v.z))
    }
}
