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
    
    var extractedLongestWall: (length: Float, normal: SIMD2<Float>, direction: SIMD2<Float>)? {
        guard let longest = walls.max(by: { $0.dimensions.x < $1.dimensions.x }) else { return nil }
        
        let dir = SIMD2<Float>(longest.transform.columns.0.x, longest.transform.columns.0.z)
        let norm = SIMD2<Float>(longest.transform.columns.2.x, longest.transform.columns.2.z)
        let length = longest.dimensions.x
        
        return (length: length, normal: normalize(norm), direction: normalize(dir))
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
