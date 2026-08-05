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

    /// Height above the slab top at which route tubes float. High enough to clear slab
    /// shadows and read from a three-quarter camera, low enough to still hug the floor.
    static let routeLiftM = 0.30

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

    // MARK: - Dashes

    /// Dash metrics for the secondary route, in meters of real house — a 0.45 m mark with a
    /// 0.28 m gap. Sized against the model, not the screen: at the default three-quarter camera
    /// this is roughly the width of a doorway, which is coarse enough to read as "dashed" from
    /// the overview and fine enough that a short bedroom-to-window leg still shows several marks.
    static let dashLengthM: Float = 0.45
    static let dashGapM: Float = 0.28

    /// One mark of a dashed route: its own polyline, plus where it sits in the parent route's
    /// 0→1 arc-length parameterization.
    struct Dash {
        var points: [SCNVector3]
        /// Carried into the tube's `u` coordinate so a dashed route keeps ONE continuous
        /// parameterization across its marks. Without this every dash would restart at u=0 and
        /// any arc-length shader (the travelling pulse) would stutter per-mark instead of
        /// flowing along the path.
        var uStart: Float
        var uEnd: Float
    }

    /// Split a polyline into dash marks by arc length.
    ///
    /// This is deliberately real geometry rather than the alpha-stipple fragment shader the
    /// secondary route used to carry. Three reasons: a shader dash is invisible to a unit test
    /// (there is nothing to assert but the string), it is measured in UV space so its apparent
    /// period changes with the length of the route, and it cannot be reused by the printable
    /// plan, which has no fragment shaders at all. Marks in world space have a fixed physical
    /// period, are inspectable, and hand the PDF lane the same dash list the 3D view draws.
    ///
    /// A route shorter than one dash returns a single unbroken mark — a two-meter leg must
    /// still draw, and "so short it looks solid" is a truthful rendering of a two-meter leg.
    static func dashes(_ rawPoints: [SCNVector3],
                       dashLength: Float = dashLengthM,
                       gapLength: Float = dashGapM) -> [Dash] {
        let points = dedupe(rawPoints)
        guard points.count >= 2, dashLength > 0, gapLength > 0 else { return [] }
        let arcs = arcLengths(points)
        guard let total = arcs.last, total > 1e-5 else { return [] }
        if total <= dashLength { return [Dash(points: points, uStart: 0, uEnd: 1)] }

        var out: [Dash] = []
        let period = dashLength + gapLength
        var start: Float = 0
        while start < total - 1e-5 {
            let end = min(start + dashLength, total)
            // A crumb left at the tail reads as dirt on the screen rather than as a dash, so
            // fold anything under a third of a mark into the preceding gap.
            if end - start >= dashLength * 0.35 {
                out.append(dash(points, arcs: arcs, from: start, to: end, total: total))
            }
            start += period
        }
        return out
    }

    private static func dash(_ points: [SCNVector3], arcs: [Float],
                             from: Float, to: Float, total: Float) -> Dash {
        var sub: [SCNVector3] = [point(at: from, along: points, arcs: arcs)]
        for (i, p) in points.enumerated() where arcs[i] > from + 1e-5 && arcs[i] < to - 1e-5 {
            sub.append(p)
        }
        sub.append(point(at: to, along: points, arcs: arcs))
        return Dash(points: dedupe(sub), uStart: from / total, uEnd: to / total)
    }

    // MARK: - Numbered stops

    /// The kinds of waypoint worth putting a number on. `path` waypoints (the interpolated
    /// points that curve a leg around furniture) are not stops — numbering those would put a
    /// chip every meter and turn the ordered-steps affordance into noise.
    enum StopKind: String {
        case start, doorway, stairs, exit

        /// Spoken by VoiceOver and printed on the paper plan. Navigational description of
        /// engine output only — this never editorializes about what to do at the stop.
        var title: String {
            switch self {
            case .start: return "Start here"
            case .doorway: return "Through the doorway"
            case .stairs: return "Take the stairs"
            case .exit: return "Out to safety"
            }
        }

        /// When two candidate stops land on the same spot, the more meaningful one wins.
        fileprivate var priority: Int {
            switch self {
            case .start: return 1
            case .doorway: return 2
            case .stairs: return 3
            case .exit: return 4
            }
        }

        fileprivate init?(_ kind: WaypointKind) {
            switch kind {
            case .room: self = .start
            case .opening: self = .doorway
            case .stair: self = .stairs
            case .exterior: self = .exit
            case .path, .unknown: return nil
            }
        }
    }

    /// One numbered stop along a route.
    struct Stop {
        /// 1-based, in walking order.
        let number: Int
        let kind: StopKind
        let waypoint: Waypoint

        /// "2. Through the doorway" — the marker's caption and its accessibility label, so the
        /// number a sighted user reads off the model is the number VoiceOver announces.
        var caption: String { "\(number). \(kind.title)" }
    }

    /// Two stops closer than this are the same place: the engine emits the exterior waypoint at
    /// its opening's coordinates, and a floor crossing is two `stair` waypoints sharing x/y.
    static let stopMergeRadiusM = 0.25

    /// The sequence of numbered stops for a route, in walking order.
    ///
    /// Coincident candidates collapse into one stop that keeps the EARLIER position and the
    /// STRONGER meaning: a stair crossing gets a single "take the stairs" on the floor you are
    /// leaving (not one chip per floor sharing a number), and a door that is also the exit is
    /// labelled as the exit. Numbering stays dense — 1…n with no gaps — because a gap in the
    /// sequence reads as a step you missed.
    static func numberedStops(for route: Route) -> [Stop] {
        var merged: [(kind: StopKind, waypoint: Waypoint)] = []
        for waypoint in route.waypoints {
            guard let kind = StopKind(waypoint.kind) else { continue }
            if let last = merged.last,
               hypot(last.waypoint.x - waypoint.x, last.waypoint.y - waypoint.y) <= stopMergeRadiusM {
                if kind.priority > last.kind.priority {
                    merged[merged.count - 1].kind = kind
                }
                continue
            }
            merged.append((kind, waypoint))
        }
        return merged.enumerated().map {
            Stop(number: $0.offset + 1, kind: $0.element.kind, waypoint: $0.element.waypoint)
        }
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
    ///
    /// `uRange` maps this tube's `u` coordinate onto a sub-span of a longer path — the whole
    /// tube by default, one mark's share of the route when the caller is drawing dashes.
    static func tubeMesh(points rawPoints: [SCNVector3],
                         radius: Float,
                         radialSegments: Int = 8,
                         uRange: ClosedRange<Float> = 0...1) -> TubeMesh? {
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
            let u = CGFloat(uRange.lowerBound
                            + (arcs[i] / total) * (uRange.upperBound - uRange.lowerBound))
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
                             radialSegments: Int = 8,
                             uRange: ClosedRange<Float> = 0...1) -> SCNGeometry? {
        guard let mesh = tubeMesh(points: points, radius: radius,
                                  radialSegments: radialSegments, uRange: uRange)
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
