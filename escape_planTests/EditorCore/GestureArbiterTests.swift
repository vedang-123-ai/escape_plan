//  GestureArbiterTests.swift — the one-finger-drag ownership rule the unified view lives by:
//  a drag edits only what is already selected (or the selected room's parts); all else orbits.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class GestureArbiterTests: XCTestCase {

    func testNothingUnderFingerOrbits() {
        XCTAssertEqual(GestureArbiter.intent(hit: .none, current: .room(roomId: "r1")), .camera)
    }

    func testNoSelectionAlwaysOrbits() {
        XCTAssertEqual(GestureArbiter.intent(hit: .room(roomId: "r1"), current: .none), .camera)
        XCTAssertEqual(GestureArbiter.intent(hit: .vertex(roomId: "r1", vertexIndex: 0), current: .none), .camera)
    }

    func testHittingTheSelectionEdits() {
        XCTAssertEqual(GestureArbiter.intent(hit: .room(roomId: "r1"), current: .room(roomId: "r1")), .edit)
        XCTAssertEqual(GestureArbiter.intent(hit: .opening(openingId: "o1"), current: .opening(openingId: "o1")), .edit)
        XCTAssertEqual(GestureArbiter.intent(hit: .wall(roomId: "r1", edgeIndex: 2),
                                             current: .wall(roomId: "r1", edgeIndex: 2)), .edit)
    }

    func testPartsOfTheSelectedRoomEdit() {
        // Selected room, dragging its corner or wall: still editing that room.
        XCTAssertEqual(GestureArbiter.intent(hit: .vertex(roomId: "r1", vertexIndex: 3),
                                             current: .room(roomId: "r1")), .edit)
        XCTAssertEqual(GestureArbiter.intent(hit: .wall(roomId: "r1", edgeIndex: 0),
                                             current: .room(roomId: "r1")), .edit)
        // And the reverse: a wall is selected, the finger lands on the room body.
        XCTAssertEqual(GestureArbiter.intent(hit: .room(roomId: "r1"),
                                             current: .vertex(roomId: "r1", vertexIndex: 1)), .edit)
    }

    func testOtherRoomsOrbit() {
        // A different room under the finger does NOT edit — one extra tap beats a misdrag.
        XCTAssertEqual(GestureArbiter.intent(hit: .room(roomId: "r2"), current: .room(roomId: "r1")), .camera)
        XCTAssertEqual(GestureArbiter.intent(hit: .vertex(roomId: "r2", vertexIndex: 0),
                                             current: .room(roomId: "r1")), .camera)
    }

    func testNonRoomSelectionsOnlyEditThemselves() {
        // Openings/stairs have no roomId — hitting anything else while they're selected orbits.
        XCTAssertEqual(GestureArbiter.intent(hit: .room(roomId: "r1"),
                                             current: .opening(openingId: "o1")), .camera)
        XCTAssertEqual(GestureArbiter.intent(hit: .opening(openingId: "o2"),
                                             current: .opening(openingId: "o1")), .camera)
        XCTAssertEqual(GestureArbiter.intent(hit: .stairs(stairsId: "s1"),
                                             current: .stairs(stairsId: "s1")), .edit)
    }
}

final class EdgeNormalProjectionTests: XCTestCase {

    func testDeltaProjectsOntoNormalOfHorizontalEdge() {
        // Edge along +x: the normal is ±y, so the x-component must vanish.
        let projected = Geometry.projectOntoEdgeNormal(Point(3, 2),
                                                       edgeFrom: Point(0, 0), to: Point(4, 0))
        XCTAssertEqual(projected.x, 0, accuracy: 1e-12)
        XCTAssertEqual(abs(projected.y), 2, accuracy: 1e-12)
    }

    func testAlongEdgeDeltaProjectsToZero() {
        let projected = Geometry.projectOntoEdgeNormal(Point(5, 5),
                                                       edgeFrom: Point(0, 0), to: Point(2, 2))
        XCTAssertEqual(projected.x, 0, accuracy: 1e-12)
        XCTAssertEqual(projected.y, 0, accuracy: 1e-12)
    }

    func testPureNormalDeltaSurvivesUnchanged() {
        let projected = Geometry.projectOntoEdgeNormal(Point(0, -1.5),
                                                       edgeFrom: Point(0, 0), to: Point(4, 0))
        XCTAssertEqual(projected.x, 0, accuracy: 1e-12)
        XCTAssertEqual(projected.y, -1.5, accuracy: 1e-12)
    }

    func testDegenerateEdgePassesDeltaThrough() {
        let delta = Point(1, 2)
        let projected = Geometry.projectOntoEdgeNormal(delta,
                                                       edgeFrom: Point(3, 3), to: Point(3, 3))
        XCTAssertEqual(projected.x, delta.x, accuracy: 1e-12)
        XCTAssertEqual(projected.y, delta.y, accuracy: 1e-12)
    }
}
