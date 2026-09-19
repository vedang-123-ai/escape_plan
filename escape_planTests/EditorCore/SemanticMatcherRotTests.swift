import XCTest
import simd
#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class SemanticMatcherRotTests: XCTestCase {
    func test90DegreeRotation() {
        // live longest wall is along Z axis (0, 1)
        let mockRoom = MockLiveRoom(
            extractedCenter: .zero,
            extractedLongestWall: (length: 10, normal: SIMD2<Float>(-1, 0), direction: SIMD2<Float>(0, 1)),
            extractedDoorPositions: [SIMD2<Float>(-5, 0)],
            extractedBoundingBox: (width: 10, depth: 10),
            extractedPerimeter: 40
        )
        
        // HomeModel room longest wall is along X axis (1, 0)
        let poly = [
            Point(x: -5, y: -5),
            Point(x: 5, y: -5),
            Point(x: 5, y: 5),
            Point(x: -5, y: 5)
        ]
        
        let room = Room(id: "r1", name: "Living", type: .living, polygon: poly, source: .manual, confidence: nil)
        let opening = Opening(id: "o1", kind: .door, room_ids: ["r1"], wall_segment: WallSegmentRef(room_id: "r1", edge_index: 2, t0: 0.4, t1: 0.6), width_m: 1.0, height_m: 2.0, sill_height_m: 0.0, egress: nil, source: .manual, confidence: nil)
        let floor = Floor(id: "f1", level: 1, name: "First", height_m: 3.0, rooms: [room], openings: [opening])
        let model = HomeModel(schema_version: "2.1", home_id: "h1", name: "Test", floors: [floor], meta: Meta(created: Date(), modified: Date()))
        
        let matcher = SemanticMatcher()
        let result = matcher.match(liveRoom: mockRoom, against: model)
        
        switch result {
        case .match(let matrix, let roomId):
            XCTAssertEqual(roomId, "r1")
            
            // Apply matrix to live direction (0, 0, 1)
            let outDir = matrix * SIMD4<Float>(0, 0, 1, 0)
            XCTAssertEqual(outDir.x, 1, accuracy: 0.001)
            XCTAssertEqual(outDir.z, 0, accuracy: 0.001)
        default:
            XCTFail("Expected a match")
        }
    }
}
