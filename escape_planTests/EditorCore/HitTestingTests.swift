//  HitTestingTests.swift — tap resolution, tested without a device.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class HitTestingTests: XCTestCase {

    private func bungalowFloor() throws -> Floor {
        try Fixtures.load("bungalow").floors[0]
    }

    // MARK: - Priority

    func testVertexBeatsWall() throws {
        let floor = try bungalowFloor()
        // [0,0] is a corner of r_living AND sits on two of its walls.
        let hit = HitTesting.hitTest(Point2D(0.02, 0.02), floor: floor)
        guard case .vertex(let roomId, let index) = hit else {
            return XCTFail("expected a vertex, got \(hit) — corners would be unselectable")
        }
        XCTAssertEqual(roomId, "r_living")
        XCTAssertEqual(index, 0)
    }

    func testWallBeatsRoomInterior() throws {
        let floor = try bungalowFloor()
        // On the bottom wall of r_living: away from either corner, and clear of the front
        // door's t-range (0.4…0.58 of a 5m wall ≈ x 2.0…2.9).
        let hit = HitTesting.hitTest(Point2D(1.0, 0.05), floor: floor)
        guard case .wall(let roomId, let edgeIndex) = hit else {
            return XCTFail("expected a wall, got \(hit)")
        }
        XCTAssertEqual(roomId, "r_living")
        XCTAssertEqual(edgeIndex, 0)
    }

    func testOpeningBeatsItsWall() throws {
        let floor = try bungalowFloor()
        // d_front sits on r_living edge 0 at t 0.4…0.58, i.e. x ≈ 2.0…2.9.
        let hit = HitTesting.hitTest(Point2D(2.45, 0.03), floor: floor)
        XCTAssertEqual(hit, .opening(openingId: "d_front"),
                       "a door is a smaller target sitting on a wall — it must win")
    }

    func testTappingTheSameWallOutsideTheDoorsRangeSelectsTheWall() throws {
        let floor = try bungalowFloor()
        // Same wall, but past the door's t-range.
        let hit = HitTesting.hitTest(Point2D(4.5, 0.03), floor: floor)
        XCTAssertEqual(hit, .wall(roomId: "r_living", edgeIndex: 0))
    }

    func testRoomInteriorSelectsTheRoom() throws {
        let floor = try bungalowFloor()
        XCTAssertEqual(HitTesting.hitTest(Point2D(2.5, 2.0), floor: floor),
                       .room(roomId: "r_living"))
        XCTAssertEqual(HitTesting.hitTest(Point2D(7.5, 6.0), floor: floor),
                       .room(roomId: "r_bath"))
    }

    func testTappingEmptySpaceSelectsNothing() throws {
        let floor = try bungalowFloor()
        XCTAssertEqual(HitTesting.hitTest(Point2D(50, 50), floor: floor), .none)
    }

    func testToleranceIsRespected() throws {
        let floor = try bungalowFloor()
        let tight = HitTesting.Tolerances(vertexRadiusM: 0.01, wallRadiusM: 0.01)
        // 5cm from the wall: a hit at the default 20cm, a miss at 1cm.
        XCTAssertEqual(HitTesting.hitTest(Point2D(4.5, 0.05), floor: floor),
                       .wall(roomId: "r_living", edgeIndex: 0))
        XCTAssertEqual(HitTesting.hitTest(Point2D(4.5, 0.05), floor: floor, tolerances: tight),
                       .room(roomId: "r_living"), "outside the wall tolerance, this is the interior")
    }

    func testNearestVertexWinsWhenTwoRoomsShareACorner() throws {
        let floor = try bungalowFloor()
        // [5,4] is a corner of all four bungalow rooms. Any of them is a defensible answer;
        // what matters is that it resolves to a vertex at that exact point, deterministically.
        let hit = HitTesting.hitTest(Point2D(5.0, 4.0), floor: floor)
        guard case .vertex(let roomId, let index) = hit else {
            return XCTFail("expected a vertex, got \(hit)")
        }
        let room = try XCTUnwrap(floor.room(roomId))
        XCTAssertPointEqual(room.polygon[index], Point2D(5, 4))
        XCTAssertEqual(HitTesting.hitTest(Point2D(5.0, 4.0), floor: floor), hit, "must be stable")
    }

    // MARK: - Needs-review flagging

    func testManualItemsNeverNeedReview() {
        XCTAssertFalse(HitTesting.needsReview(source: .manual, confidence: nil))
        XCTAssertFalse(HitTesting.needsReview(source: .manual, confidence: 0.1))
    }

    func testLowConfidenceScanItemsNeedReview() {
        XCTAssertTrue(HitTesting.needsReview(source: .scan, confidence: 0.2))
        XCTAssertFalse(HitTesting.needsReview(source: .scan, confidence: 0.9))
        XCTAssertTrue(HitTesting.needsReview(source: .scan, confidence: nil),
                      "a scan item with no confidence is untrustworthy, not trustworthy")
    }

    func testItemsNeedingReviewFindsBothRoomsAndOpenings() throws {
        var floor = try bungalowFloor()
        floor.rooms[1].source = .scan
        floor.rooms[1].confidence = 0.2
        floor.openings[0].source = .scan
        floor.openings[0].confidence = 0.95

        let flagged = HitTesting.itemsNeedingReview(floor: floor)
        XCTAssertEqual(flagged, [floor.rooms[1].id])
        XCTAssertFalse(flagged.contains(floor.openings[0].id), "0.95 is confident")
    }
}
