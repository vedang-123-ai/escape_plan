import Foundation
import simd

#if canImport(RoomPlan)
import RoomPlan
#endif

enum SemanticMatchResult {
    case match(matrix: simd_float4x4, roomId: String)
    case ambiguous(candidateRoomIds: [String])
    case noMatch
}

protocol LiveRoomExtractable {
    var extractedCenter: SIMD2<Float> { get }
    var extractedLongestWall: (length: Float, normal: SIMD2<Float>, direction: SIMD2<Float>)? { get }
    var extractedDoorPositions: [SIMD2<Float>] { get }
    var extractedBoundingBox: (width: Float, depth: Float) { get }
}

/// One wall segment, as the matcher needs it and independent of RoomPlan.
///
/// This type exists so the wall-merging below can be TESTED. `CapturedRoom` is iOS-only, so
/// anything written against it directly cannot run on a machine with no simulator — which is
/// how the defect this fixes survived two audits that both correctly identified it.
struct WallSegmentSample: Equatable, Sendable {
    /// Midpoint, in the scan's horizontal plane.
    var center: SIMD2<Float>
    /// Unit vector along the wall.
    var direction: SIMD2<Float>
    var length: Float

    init(center: SIMD2<Float>, direction: SIMD2<Float>, length: Float) {
        self.center = center
        self.direction = direction
        self.length = length
    }
}

/// Merges wall segments that are really one wall, then reports the longest.
///
/// ─── WHY MERGING IS NECESSARY ─────────────────────────────────────────────────────────────
/// **RoomPlan splits a wall wherever a door or an opening interrupts it.** A 10 m living-room
/// wall broken by two doorways arrives as three ~3 m segments. Taking the longest SEGMENT then
/// picks an unbroken 4 m perpendicular wall instead, and since the matcher aligns the scan to
/// the model by that wall's direction, the result is a permanent **90° rotation error** —
/// silent, total, and only reproducible on a real scan. Raised as MEDIUM by the S9.1 audit,
/// confirmed still-unfixed by the S9.2 audit, fixed 2026-09-16.
///
/// Segments are grouped when they are parallel AND collinear — same line, not merely the same
/// bearing, or the two long sides of a corridor would merge into one. The merged length is the
/// SPAN of the group along its own direction, so the doorway gaps are included: the wall is
/// 10 m long whether or not you can walk through parts of it.
enum WallGrouping {

    /// `cos 10°`. RoomPlan's wall normals wobble by a few degrees on a real scan, so exact
    /// parallelism finds nothing; 10° is loose enough to absorb that and tight enough that two
    /// genuinely different walls never merge (the next interesting angle in a home is 45°).
    static let parallelTolerance: Float = 0.985

    /// Metres. Two segments of one wall can be offset by the wall's own thickness plus scan
    /// noise; 0.25 m covers that without reaching the far side of any real room.
    static let collinearTolerance: Float = 0.25

    /// The longest wall, with its segments merged. `nil` when there is nothing usable.
    static func longestWall(from segments: [WallSegmentSample])
        -> (length: Float, normal: SIMD2<Float>, direction: SIMD2<Float>)? {

        var groups: [[WallSegmentSample]] = []

        for segment in segments where segment.length > 0 && segment.direction != .zero {
            let direction = canonicalDirection(segment.direction)
            var placed = false

            for index in groups.indices {
                let reference = canonicalDirection(groups[index][0].direction)
                // `abs` because a wall scanned from the other side points the opposite way and
                // is still the same wall.
                guard abs(dot(direction, reference)) >= parallelTolerance else { continue }

                // Parallel is not enough: the two long sides of a corridor are parallel and
                // are emphatically not one wall. Require the same LINE, measured as the
                // perpendicular offset between the segments' centres.
                let normal = SIMD2<Float>(-reference.y, reference.x)
                let offset = abs(dot(segment.center - groups[index][0].center, normal))
                guard offset <= collinearTolerance else { continue }

                groups[index].append(segment)
                placed = true
                break
            }
            if !placed { groups.append([segment]) }
        }

        var best: (length: Float, normal: SIMD2<Float>, direction: SIMD2<Float>)?
        for group in groups {
            // Take the direction from the group's longest member: it is the best-estimated of
            // them, and using it keeps the merged direction stable as shorter noisy stubs join.
            guard let longest = group.max(by: { $0.length < $1.length }) else { continue }
            let direction = canonicalDirection(longest.direction)

            // The span along the wall's own direction — endpoints projected onto it, so the
            // doorway gaps between segments count toward the length.
            var minProjection = Float.greatestFiniteMagnitude
            var maxProjection = -Float.greatestFiniteMagnitude
            for segment in group {
                let half = segment.direction * (segment.length / 2)
                for endpoint in [segment.center + half, segment.center - half] {
                    let projection = dot(endpoint, direction)
                    minProjection = min(minProjection, projection)
                    maxProjection = max(maxProjection, projection)
                }
            }
            let span = maxProjection - minProjection
            guard span > (best?.length ?? 0) else { continue }
            best = (length: span,
                    normal: SIMD2<Float>(-direction.y, direction.x),
                    direction: direction)
        }
        return best
    }

    /// Points a direction into a consistent half-plane, so a wall and the same wall scanned
    /// from the other side group together. `match()` already tries both the computed rotation
    /// and that rotation plus 180°, so collapsing the sign here costs nothing downstream.
    static func canonicalDirection(_ direction: SIMD2<Float>) -> SIMD2<Float> {
        let unit = normalize(direction)
        if unit.x < 0 || (unit.x == 0 && unit.y < 0) { return -unit }
        return unit
    }
}

struct SemanticMatcher {
    init() {}
    
    func match(liveRoom: LiveRoomExtractable, against model: HomeModel) -> SemanticMatchResult {
        let liveWidth = liveRoom.extractedBoundingBox.width
        let liveDepth = liveRoom.extractedBoundingBox.depth
        let liveArea = liveWidth * liveDepth
        
        guard let liveLongestWall = liveRoom.extractedLongestWall else {
            return .noMatch
        }
        
        struct Candidate {
            let roomId: String
            let center: SIMD2<Float>
            let longestWall: (length: Float, normal: SIMD2<Float>, direction: SIMD2<Float>)
            let doorPositions: [SIMD2<Float>]
            let area: Float
        }
        
        var candidates: [Candidate] = []
        
        for floor in model.floors {
            for room in floor.rooms {
                let poly = room.polygon
                guard poly.count >= 3 else { continue }
                
                var minX = Float.greatestFiniteMagnitude
                var maxX = -Float.greatestFiniteMagnitude
                var minY = Float.greatestFiniteMagnitude
                var maxY = -Float.greatestFiniteMagnitude
                
                var maxEdgeLength: Float = 0
                var maxEdgeDir = SIMD2<Float>(1, 0)
                var maxEdgeNorm = SIMD2<Float>(0, 1)
                
                for i in 0..<poly.count {
                    let p1 = poly[i]
                    let p2 = poly[(i + 1) % poly.count]
                    
                    let fx1 = Float(p1.x)
                    let fy1 = Float(p1.y)
                    let fx2 = Float(p2.x)
                    let fy2 = Float(p2.y)
                    
                    minX = min(minX, fx1)
                    maxX = max(maxX, fx1)
                    minY = min(minY, fy1)
                    maxY = max(maxY, fy1)
                    
                    let dx = fx2 - fx1
                    let dy = fy2 - fy1
                    let len = sqrt(dx * dx + dy * dy)
                    if len > maxEdgeLength {
                        maxEdgeLength = len
                        maxEdgeDir = SIMD2<Float>(dx, dy) / len
                        maxEdgeNorm = SIMD2<Float>(-dy, dx) / len
                    }
                }
                
                var area: Float = 0
                for i in 0..<poly.count {
                    let p1 = poly[i]
                    let p2 = poly[(i + 1) % poly.count]
                    area += Float(p1.x * p2.y - p2.x * p1.y)
                }
                area = abs(area) / 2.0
                
                // Compare area (e.g. 15% tolerance)
                let areaDiff = abs(area - liveArea) / max(liveArea, 0.001)
                if areaDiff < 0.20 {
                    let center = SIMD2<Float>((minX + maxX) / 2.0, (minY + maxY) / 2.0)
                    
                    // find doors for this room
                    var doorPos: [SIMD2<Float>] = []
                    for opening in floor.openings {
                        if opening.room_ids.contains(room.id) {
                            let wallRef = opening.wall_segment
                            if let polyRoom = floor.rooms.first(where: { $0.id == wallRef.room_id }) {
                                let rPoly = polyRoom.polygon
                                if wallRef.edge_index < rPoly.count {
                                    let p1 = rPoly[wallRef.edge_index]
                                    let p2 = rPoly[(wallRef.edge_index + 1) % rPoly.count]
                                    
                                    let tMid = (wallRef.t0 + wallRef.t1) / 2.0
                                    let midX = Float(p1.x + (p2.x - p1.x) * tMid)
                                    let midY = Float(p1.y + (p2.y - p1.y) * tMid)
                                    doorPos.append(SIMD2<Float>(midX, midY))
                                }
                            }
                        }
                    }
                    
                    let candidate = Candidate(
                        roomId: room.id,
                        center: center,
                        longestWall: (length: maxEdgeLength, normal: maxEdgeNorm, direction: maxEdgeDir),
                        doorPositions: doorPos,
                        area: area
                    )
                    candidates.append(candidate)
                }
            }
        }
        
        if candidates.isEmpty { return .noMatch }
        
        struct EvaluatedCandidate {
            let roomId: String
            let transform: simd_float4x4
            let score: Float
            /// Whether `score` was computed from actual matched doors.
            ///
            /// This flag is the whole fix for a defect found by review 2026-09-14: the
            /// door-distance branch fell through to `totalDist = 0` whenever EITHER side had no
            /// doors, and lower is better — so a candidate with no doors at all (a closet, or a
            /// scan that missed a doorway) scored a perfect 0 and outranked a correct room that
            /// matched its doors at, say, 0.35 m. **Absence of evidence was being scored as
            /// perfect evidence.** A score with no evidence behind it is not comparable to one
            /// with, so it is kept out of the ranking rather than given a different number.
            let hasDoorEvidence: Bool
        }
        
        var evaluated: [EvaluatedCandidate] = []
        
        for candidate in candidates {
            let lDir = liveLongestWall.direction
            let cDir = candidate.longestWall.direction
            
            let angle = atan2(cDir.y, cDir.x) - atan2(lDir.y, lDir.x)
            let angles = [angle, angle + Float.pi]
            
            for ang in angles {
                let rotM = simd_float4x4(rotationY: ang)
                
                var tOut = simd_float4x4(translation: SIMD3<Float>(candidate.center.x, 0, candidate.center.y))
                var tIn = simd_float4x4(translation: SIMD3<Float>(-liveRoom.extractedCenter.x, 0, -liveRoom.extractedCenter.y))
                
                let transform = tOut * rotM * tIn
                
                var totalDist: Float = 0
                if !liveRoom.extractedDoorPositions.isEmpty && !candidate.doorPositions.isEmpty {
                    for ld in liveRoom.extractedDoorPositions {
                        let pt = SIMD4<Float>(ld.x, 0, ld.y, 1)
                        let tPt = transform * pt
                        let t2d = SIMD2<Float>(tPt.x, tPt.z)
                        
                        var minDist = Float.greatestFiniteMagnitude
                        for cd in candidate.doorPositions {
                            let dist = simd_distance(t2d, cd)
                            minDist = min(minDist, dist)
                        }
                        totalDist += minDist
                    }
                    totalDist /= Float(liveRoom.extractedDoorPositions.count)
                }

                let hasDoorEvidence = !liveRoom.extractedDoorPositions.isEmpty
                    && !candidate.doorPositions.isEmpty
                evaluated.append(EvaluatedCandidate(roomId: candidate.roomId,
                                                    transform: transform,
                                                    score: totalDist,
                                                    hasDoorEvidence: hasDoorEvidence))
            }
        }
        
        // Only candidates whose score came from matched doors are ranked. Mixing in the
        // no-evidence ones was the defect: they carry a 0 that means "nothing to compare",
        // not "a perfect fit", and it sorted them straight to the top.
        let comparable = evaluated.filter(\.hasDoorEvidence)

        // If NOTHING has door evidence, fall back to the whole set — every score is 0, so they
        // all tie, and the ambiguity check below turns that into `.ambiguous`. That is the
        // behaviour the 2026-09-14 ambiguity fix deliberately established (a 180° rotation
        // cannot be resolved without doors, so the honest answer is "I can't tell"), and
        // `testNoDoorAmbiguity` pins it. This fix narrows that one: it stops a no-evidence
        // candidate from OUTRANKING a door-matched one. It does not change what happens when
        // there is no evidence anywhere.
        let ranked = comparable.isEmpty ? evaluated : comparable

        let sorted = ranked.sorted { $0.score < $1.score }
        let best = sorted[0]
        var ambiguousIds = Set<String>()
        var roomEvaluationCounts: [String: Int] = [:]
        
        for e in sorted {
            if abs(e.score - best.score) < 0.2 { // less than 20cm difference
                roomEvaluationCounts[e.roomId, default: 0] += 1
                ambiguousIds.insert(e.roomId)
            }
        }
        
        if roomEvaluationCounts.values.contains(where: { $0 > 1 }) || ambiguousIds.count > 1 {
            return .ambiguous(candidateRoomIds: Array(ambiguousIds))
        }
        
        return .match(matrix: best.transform, roomId: best.roomId)
    }
}

extension simd_float4x4 {
    init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self = simd_float4x4(
            SIMD4<Float>(c, 0, s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(-s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
    
    init(translation t: SIMD3<Float>) {
        self = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }
}

#if canImport(RoomPlan)
@available(iOS 16.0, *)
extension CapturedRoom: LiveRoomExtractable {
    var extractedCenter: SIMD2<Float> {
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        
        for wall in walls {
            let pos = wall.transform.columns.3
            minX = min(minX, pos.x)
            maxX = max(maxX, pos.x)
            minZ = min(minZ, pos.z)
            maxZ = max(maxZ, pos.z)
        }
        if walls.isEmpty { return .zero }
        return SIMD2<Float>((minX + maxX) / 2.0, (minZ + maxZ) / 2.0)
    }
    
    /// Segments merged first — RoomPlan splits a wall at every doorway, and taking the longest
    /// raw segment picks the wrong wall and rotates the whole scan 90°. See `WallGrouping`.
    var extractedLongestWall: (length: Float, normal: SIMD2<Float>, direction: SIMD2<Float>)? {
        WallGrouping.longestWall(from: walls.map { wall in
            WallSegmentSample(
                center: SIMD2<Float>(wall.transform.columns.3.x, wall.transform.columns.3.z),
                direction: SIMD2<Float>(wall.transform.columns.0.x, wall.transform.columns.0.z),
                length: wall.dimensions.x)
        })
    }
    
    var extractedDoorPositions: [SIMD2<Float>] {
        return doors.map { SIMD2<Float>($0.transform.columns.3.x, $0.transform.columns.3.z) }
    }
    
    var extractedBoundingBox: (width: Float, depth: Float) {
        guard let longest = extractedLongestWall else { return (0, 0) }
        let dir = longest.direction
        let norm = longest.normal
        
        var minProjDir = Float.greatestFiniteMagnitude
        var maxProjDir = -Float.greatestFiniteMagnitude
        var minProjNorm = Float.greatestFiniteMagnitude
        var maxProjNorm = -Float.greatestFiniteMagnitude
        
        for wall in walls {
            let pos = SIMD2<Float>(wall.transform.columns.3.x, wall.transform.columns.3.z)
            let halfLen = wall.dimensions.x / 2.0
            let wallDir = SIMD2<Float>(wall.transform.columns.0.x, wall.transform.columns.0.z)
            
            let p1 = pos + wallDir * halfLen
            let p2 = pos - wallDir * halfLen
            
            for p in [p1, p2] {
                let pDir = dot(p, dir)
                let pNorm = dot(p, norm)
                minProjDir = min(minProjDir, pDir)
                maxProjDir = max(maxProjDir, pDir)
                minProjNorm = min(minProjNorm, pNorm)
                maxProjNorm = max(maxProjNorm, pNorm)
            }
        }
        if walls.isEmpty { return (0, 0) }
        return (maxProjDir - minProjDir, maxProjNorm - minProjNorm)
    }
}
#endif
