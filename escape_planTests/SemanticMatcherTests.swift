import XCTest
import simd
@testable import escape_plan

struct MockLiveRoom: LiveRoomExtractable {
    var extractedCenter: SIMD2<Float>
    var extractedLongestWall: (length: Float, normal: SIMD2<Float>, direction: SIMD2<Float>)?
    var extractedDoorPositions: [SIMD2<Float>]
    var extractedBoundingBox: (width: Float, depth: Float)
}

final class SemanticMatcherTests: XCTestCase {
    
    func testPerfectMatch() {
        // Room center at 0,0, longest wall along X axis
        let mockRoom = MockLiveRoom(
            extractedCenter: .zero,
            extractedLongestWall: (length: 10, normal: SIMD2<Float>(0, 1), direction: SIMD2<Float>(1, 0)),
            extractedDoorPositions: [SIMD2<Float>(0, 5)], // Door on the "top" wall
            extractedBoundingBox: (width: 10, depth: 10)
        )
        
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
            
            // Expected translation is zero, rotation is zero
            let outCenter = matrix * SIMD4<Float>(0, 0, 0, 1)
            XCTAssertEqual(outCenter.x, 0, accuracy: 0.001)
            XCTAssertEqual(outCenter.z, 0, accuracy: 0.001)
            
        default:
            XCTFail("Expected a perfect match")
        }
    }
    
    func test180DegreeAmbiguityResolvedByDoors() {
        // Captured room is rotated 180 degrees
        let mockRoom = MockLiveRoom(
            extractedCenter: SIMD2<Float>(10, 10),
            extractedLongestWall: (length: 10, normal: SIMD2<Float>(0, -1), direction: SIMD2<Float>(-1, 0)),
            extractedDoorPositions: [SIMD2<Float>(10, 5)], // Door at top
            extractedBoundingBox: (width: 10, depth: 10)
        )
        
        let poly = [
            Point(x: -5, y: -5),
            Point(x: 5, y: -5),
            Point(x: 5, y: 5),
            Point(x: -5, y: 5)
        ]
        
        let room = Room(id: "r1", name: "Living", type: .living, polygon: poly, source: .manual, confidence: nil)
        let opening = Opening(id: "o1", kind: .door, room_ids: ["r1"], wall_segment: WallSegmentRef(room_id: "r1", edge_index: 0, t0: 0.4, t1: 0.6), width_m: 1.0, height_m: 2.0, sill_height_m: 0.0, egress: nil, source: .manual, confidence: nil)
        let floor = Floor(id: "f1", level: 1, name: "First", height_m: 3.0, rooms: [room], openings: [opening])
        let model = HomeModel(schema_version: "2.1", home_id: "h1", name: "Test", floors: [floor], meta: Meta(created: Date(), modified: Date()))
        
        let matcher = SemanticMatcher()
        let result = matcher.match(liveRoom: mockRoom, against: model)
        
        switch result {
        case .match(let matrix, let roomId):
            XCTAssertEqual(roomId, "r1")
            // Apply matrix to live door position (10, 5).
            // Expect it to end up at the model's opening position.
            // Edge 0 is from (-5, -5) to (5, -5). Midpoint is (0, -5).
            let outDoor = matrix * SIMD4<Float>(10, 0, 5, 1)
            XCTAssertEqual(outDoor.x, 0, accuracy: 0.001)
            XCTAssertEqual(outDoor.z, -5, accuracy: 0.001)
        default:
            XCTFail("Expected match")
        }
    }
    
    func testIdenticalRoomsReturnsAmbiguous() {
        let mockRoom = MockLiveRoom(
            extractedCenter: .zero,
            extractedLongestWall: (length: 10, normal: SIMD2<Float>(0, 1), direction: SIMD2<Float>(1, 0)),
            extractedDoorPositions: [SIMD2<Float>(0, 5)],
            extractedBoundingBox: (width: 10, depth: 10)
        )
        
        let poly1 = [
            Point(x: -5, y: -5),
            Point(x: 5, y: -5),
            Point(x: 5, y: 5),
            Point(x: -5, y: 5)
        ]
        
        // Exact same dimensions, offset by X=20
        let poly2 = [
            Point(x: 15, y: -5),
            Point(x: 25, y: -5),
            Point(x: 25, y: 5),
            Point(x: 15, y: 5)
        ]
        
        let room1 = Room(id: "r1", name: "Bed 1", type: .bedroom, polygon: poly1, source: .manual, confidence: nil)
        let room2 = Room(id: "r2", name: "Bed 2", type: .bedroom, polygon: poly2, source: .manual, confidence: nil)
        
        let opening1 = Opening(id: "o1", kind: .door, room_ids: ["r1"], wall_segment: WallSegmentRef(room_id: "r1", edge_index: 2, t0: 0.4, t1: 0.6), width_m: 1.0, height_m: 2.0, sill_height_m: 0.0, egress: nil, source: .manual, confidence: nil)
        let opening2 = Opening(id: "o2", kind: .door, room_ids: ["r2"], wall_segment: WallSegmentRef(room_id: "r2", edge_index: 2, t0: 0.4, t1: 0.6), width_m: 1.0, height_m: 2.0, sill_height_m: 0.0, egress: nil, source: .manual, confidence: nil)
        
        let floor = Floor(id: "f1", level: 1, name: "First", height_m: 3.0, rooms: [room1, room2], openings: [opening1, opening2])
        let model = HomeModel(schema_version: "2.1", home_id: "h1", name: "Test", floors: [floor], meta: Meta(created: Date(), modified: Date()))
        
        let matcher = SemanticMatcher()
        let result = matcher.match(liveRoom: mockRoom, against: model)
        
        switch result {
        case .ambiguous(let candidateRoomIds):
            XCTAssertEqual(candidateRoomIds.count, 2)
            XCTAssertTrue(candidateRoomIds.contains("r1"))
            XCTAssertTrue(candidateRoomIds.contains("r2"))
        default:
            XCTFail("Expected ambiguous result due to identical rooms")
        }
    }
    
    func test45DegreeRotatedRoomMatch() {
        let angle = Float.pi / 4.0
        let c = cos(angle)
        let s = sin(angle)
        
        let mockRoom = MockLiveRoom(
            extractedCenter: SIMD2<Float>(10, 10),
            extractedLongestWall: (length: 10, normal: SIMD2<Float>(-s, c), direction: SIMD2<Float>(c, s)),
            extractedDoorPositions: [SIMD2<Float>(10 - 5 * s, 10 + 5 * c)],
            extractedBoundingBox: (width: 10, depth: 10)
        )
        
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
            
            let outDoor = matrix * SIMD4<Float>(10 - 5 * s, 0, 10 + 5 * c, 1)
            XCTAssertEqual(outDoor.x, 0, accuracy: 0.001)
            XCTAssertEqual(outDoor.z, 5, accuracy: 0.001)
        default:
            XCTFail("Expected match for 45 degree rotated room")
        }
    }
    
    func testNoDoorAmbiguity() {
        let mockRoom = MockLiveRoom(
            extractedCenter: .zero,
            extractedLongestWall: (length: 10, normal: SIMD2<Float>(0, 1), direction: SIMD2<Float>(1, 0)),
            extractedDoorPositions: [], // NO DOORS
            extractedBoundingBox: (width: 10, depth: 10)
        )
        
        let poly = [
            Point(x: -5, y: -5),
            Point(x: 5, y: -5),
            Point(x: 5, y: 5),
            Point(x: -5, y: 5)
        ]
        
        let room = Room(id: "r1", name: "Living", type: .living, polygon: poly, source: .manual, confidence: nil)
        let floor = Floor(id: "f1", level: 1, name: "First", height_m: 3.0, rooms: [room], openings: [])
        let model = HomeModel(schema_version: "2.1", home_id: "h1", name: "Test", floors: [floor], meta: Meta(created: Date(), modified: Date()))
        
        let matcher = SemanticMatcher()
        let result = matcher.match(liveRoom: mockRoom, against: model)
        
        switch result {
        case .ambiguous(let candidateRoomIds):
            XCTAssertEqual(candidateRoomIds.count, 1)
            XCTAssertEqual(candidateRoomIds.first, "r1")
        default:
            XCTFail("Expected ambiguity because 180 deg rotation cannot be disambiguated without doors")
        }
    }
}
