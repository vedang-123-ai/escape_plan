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
            extractedBoundingBox: (width: 10, depth: 10)
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

    /// A 90 degree test cannot tell the rotation direction: the matcher also tries angle + 180,
    /// which rescues a wrong-signed quarter turn. 30 degrees has no such rescue.
    func testDoorLandsOnModelDoorAfterA30DegreeRotation() {
        let a: Float = 30 * .pi / 180
        func rot(_ p: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2<Float>(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a))
        }
        let modelDoor = SIMD2<Float>(-5, -5)
        let liveDoor = rot(modelDoor)
        let mockRoom = MockLiveRoom(
            extractedCenter: .zero,
            extractedLongestWall: (length: 20, normal: rot(SIMD2<Float>(0, 1)), direction: rot(SIMD2<Float>(1, 0))),
            extractedDoorPositions: [liveDoor],
            extractedBoundingBox: (width: 20, depth: 10)
        )
        let poly = [Point(x: -10, y: -5), Point(x: 10, y: -5), Point(x: 10, y: 5), Point(x: -10, y: 5)]
        let room = Room(id: "r1", name: "Living", type: .living, polygon: poly, source: .manual, confidence: nil)
        let opening = Opening(id: "o1", kind: .door, room_ids: ["r1"], wall_segment: WallSegmentRef(room_id: "r1", edge_index: 0, t0: 0.2, t1: 0.3), width_m: 1.0, height_m: 2.0, sill_height_m: 0.0, egress: nil, source: .manual, confidence: nil)
        let floor = Floor(id: "f1", level: 1, name: "First", height_m: 3.0, rooms: [room], openings: [opening])
        let model = HomeModel(schema_version: "2.1", home_id: "h1", name: "Test", floors: [floor], meta: Meta(created: Date(), modified: Date()))

        guard case .match(let matrix, let roomId) = SemanticMatcher().match(liveRoom: mockRoom, against: model) else {
            return XCTFail("Expected a match")
        }
        XCTAssertEqual(roomId, "r1")
        let p = matrix * SIMD4<Float>(liveDoor.x, 0, liveDoor.y, 1)
        XCTAssertEqual(p.x, modelDoor.x, accuracy: 0.01)
        XCTAssertEqual(p.z, modelDoor.y, accuracy: 0.01)
    }
}
