//  OpeningActionsTests.swift — the addOpening/deleteOpening/setOpeningKind/setOpeningWidth
//  vocabulary plus the adjacency derivation behind it (OpeningPlacement).
//
//  The load-bearing claims: room_ids is DERIVED from geometry (shared wall -> interior,
//  unshared -> EXTERIOR, which is what makes a door an exit), invalid placements are rejected
//  with the model untouched, and openings ride their wall parametrically through drags.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class OpeningActionsTests: XCTestCase {

    /// Two 4×4 rooms side by side sharing the x=4 wall: room_a's edge 1 runs (4,0)->(4,4) and
    /// coincides with room_b's edge 3. Every other wall faces the exterior.
    private func twoRoomHome() -> HomeModel {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Room(id: "room_a", name: "A", type: .living,
                     polygon: [Point(0, 0), Point(4, 0), Point(4, 4), Point(0, 4)],
                     source: .manual, confidence: nil)
        let b = Room(id: "room_b", name: "B", type: .kitchen,
                     polygon: [Point(4, 0), Point(8, 0), Point(8, 4), Point(4, 4)],
                     source: .manual, confidence: nil)
        return HomeModel(schema_version: HomeModel.currentSchemaVersion, home_id: "h_test",
                         name: "Openings Test Home",
                         floors: [Floor(id: "f0", level: 0, name: "Ground", height_m: 2.7,
                                        rooms: [a, b])],
                         meta: Meta(created: stamp, modified: stamp))
    }

    private var floor: Floor { get throws { try XCTUnwrap(store.model.floors.first) } }
    private var store: HomeModelStore!

    override func setUpWithError() throws {
        store = try HomeModelStore.testStore(twoRoomHome())
    }

    // MARK: - addOpening: adjacency derivation

    func testDoorOnExteriorWallIsAnExit() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .door)))
        let opening = try XCTUnwrap(try floor.openings.first)
        XCTAssertEqual(opening.room_ids, ["room_a", EXTERIOR_ID])
        XCTAssertTrue(opening.isExit)
        XCTAssertEqual(opening.kind, .door)
        XCTAssertModelValid(store.model)
    }

    func testDoorOnSharedWallConnectsBothRooms() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 1, t: 0.5,
                                                    kind: .door)))
        let opening = try XCTUnwrap(try floor.openings.first)
        XCTAssertEqual(opening.room_ids, ["room_a", "room_b"])
        XCTAssertFalse(opening.isExit)
        XCTAssertEqual(opening.wall_segment.room_id, "room_a")
        XCTAssertEqual(opening.wall_segment.edge_index, 1)
    }

    func testWindowAdjacencyIsDerivedTheSameWay() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_b", edgeIndex: 1, t: 0.5,
                                                    kind: .window)))
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_b", edgeIndex: 3, t: 0.5,
                                                    kind: .window)))
        let exterior = try XCTUnwrap(try floor.openings.first)
        XCTAssertEqual(exterior.room_ids, ["room_b", EXTERIOR_ID],
                       "window on room_b's outer wall faces EXTERIOR (egress-window encoding)")
        let interior = try XCTUnwrap(try floor.openings.last)
        XCTAssertEqual(interior.room_ids, ["room_b", "room_a"],
                       "window on the shared wall is an interior window")
    }

    // MARK: - addOpening: geometry defaults

    func testDoorDefaultsMatchFixtureConventions() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .door)))
        let o = try XCTUnwrap(try floor.openings.first)
        XCTAssertEqual(o.width_m, 0.9)
        XCTAssertEqual(o.height_m, 2.0)
        XCTAssertEqual(o.sill_height_m, 0.0)
        XCTAssertEqual(o.source, .manual)
        XCTAssertNil(o.confidence)
        XCTAssertNil(o.egress, "egress is the backend annotator's field, never set by the editor")
        // 0.9 m on a 4 m wall = 0.1125 either side of center.
        XCTAssertEqual(o.wall_segment.t0, 0.5 - 0.1125, accuracy: 1e-9)
        XCTAssertEqual(o.wall_segment.t1, 0.5 + 0.1125, accuracy: 1e-9)
    }

    func testWindowDefaultsMatchFixtureConventions() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 2, t: 0.5,
                                                    kind: .window)))
        let o = try XCTUnwrap(try floor.openings.first)
        XCTAssertEqual(o.kind, .window)
        XCTAssertEqual(o.width_m, 1.0)
        XCTAssertEqual(o.height_m, 1.2)
        XCTAssertEqual(o.sill_height_m, 0.8)
    }

    func testSpanSlidesInwardNearWallEnd() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.01,
                                                    kind: .door)))
        let seg = try XCTUnwrap(try floor.openings.first).wall_segment
        XCTAssertEqual(seg.t0, 0, accuracy: 1e-9, "clamped flush to the wall start, not past it")
        XCTAssertEqual(seg.t1, 0.225, accuracy: 1e-9)
        XCTAssertModelValid(store.model)
    }

    // MARK: - addOpening: rejections

    func testRejectedWhenWallTooShort() throws {
        let before = store.model
        // room_a's bottom edge is 4 m; a 0.9 m door fits. Shrink the test to a wall that can't
        // host it: a 0.5 m sliver room.
        XCTAssertApplied(store.dispatch(.addRoom(floorId: "f0", origin: Point(0, 6),
                                                 width_m: 0.5, height_m: 3,
                                                 type: .other, name: "Sliver")))
        let sliverId = try XCTUnwrap(try floor.rooms.last).id
        XCTAssertRejected(store.dispatch(.addOpening(roomId: sliverId, edgeIndex: 0, t: 0.5,
                                                     kind: .door)),
                          "0.9 m door on a 0.5 m wall")
        XCTAssertEqual(store.model.floors[0].openings.count, 0)
        XCTAssertNotEqual(before, store.model, "the room add itself applied")
    }

    func testRejectedForUnknownRoomAndBadEdge() throws {
        let before = store.model
        XCTAssertRejected(store.dispatch(.addOpening(roomId: "nope", edgeIndex: 0, t: 0.5,
                                                     kind: .door)))
        XCTAssertRejected(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 9, t: 0.5,
                                                     kind: .door)))
        XCTAssertEqual(before, store.model)
    }

    func testOverlappingOpeningsOnSameEdgeRejected() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .door)))
        let before = store.model
        XCTAssertRejected(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.55,
                                                     kind: .door)),
                          "second door overlapping the first")
        XCTAssertEqual(before, store.model, "rejected action must leave the model untouched")

        // Far enough along the same wall is fine.
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.85,
                                                    kind: .window)))
        XCTAssertEqual(store.model.floors[0].openings.count, 2)
        XCTAssertModelValid(store.model)
    }

    func testDragOpeningCannotCrossAnotherOpening() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.3,
                                                    kind: .door)))
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.8,
                                                    kind: .window)))
        let doorId = store.model.floors[0].openings[0].id
        XCTAssertRejected(store.dispatch(.dragOpening(openingId: doorId, t: 0.8)),
                          "sliding the door onto the window")
        XCTAssertModelValid(store.model)
    }

    // MARK: - deleteOpening

    func testDeleteOpeningRemovesItAndClearsSelection() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .door)))
        let id = try XCTUnwrap(try floor.openings.first).id
        store.select(.opening(openingId: id))
        XCTAssertApplied(store.dispatch(.deleteOpening(openingId: id)))
        XCTAssertTrue(store.model.floors[0].openings.isEmpty)
        XCTAssertEqual(store.selection, .none)
        XCTAssertRejected(store.dispatch(.deleteOpening(openingId: id)), "already gone")
    }

    // MARK: - setOpeningKind / setOpeningWidth

    func testSetOpeningKindSwapsDimensionDefaultsKeepsSpan() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .door)))
        let id = try XCTUnwrap(try floor.openings.first).id
        XCTAssertApplied(store.dispatch(.setOpeningKind(openingId: id, kind: .window)))
        let o = try XCTUnwrap(try floor.openings.first)
        XCTAssertEqual(o.kind, .window)
        XCTAssertEqual(o.height_m, 1.2)
        XCTAssertEqual(o.sill_height_m, 0.8)
        XCTAssertEqual(o.width_m, 0.9, "width and position stay put on a kind switch")
        XCTAssertEqual(o.wall_segment.t0, 0.5 - 0.1125, accuracy: 1e-9)
        XCTAssertEqual(o.room_ids, ["room_a", EXTERIOR_ID], "adjacency untouched")
    }

    func testSetOpeningWidthRecentersAndRejectsOverwide() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .door)))
        let id = try XCTUnwrap(try floor.openings.first).id
        XCTAssertApplied(store.dispatch(.setOpeningWidth(openingId: id, width_m: 1.8)))
        let seg = try XCTUnwrap(try floor.openings.first).wall_segment
        XCTAssertEqual(seg.t0, 0.5 - 0.225, accuracy: 1e-9)
        XCTAssertEqual(seg.t1, 0.5 + 0.225, accuracy: 1e-9)

        let before = store.model
        XCTAssertRejected(store.dispatch(.setOpeningWidth(openingId: id, width_m: 5)),
                          "5 m opening on a 4 m wall")
        XCTAssertEqual(before, store.model)
    }

    // MARK: - Undo/redo

    func testAddOpeningUndoRedoRoundTrip() throws {
        let undoStack = UndoStack()
        store.onCommit = { undoStack.recordCommit($0) }

        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 1, t: 0.5,
                                                    kind: .door)))
        let withDoor = store.model
        XCTAssertEqual(undoStack.undoLabel, "Add Door")

        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertTrue(store.model.floors[0].openings.isEmpty)
        XCTAssertTrue(undoStack.redo(on: store))
        XCTAssertEqual(store.model, withDoor)
    }

    func testDeleteOpeningUndoRestoresIt() throws {
        let undoStack = UndoStack()
        store.onCommit = { undoStack.recordCommit($0) }
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .window)))
        let id = try XCTUnwrap(try floor.openings.first).id
        XCTAssertApplied(store.dispatch(.deleteOpening(openingId: id)))
        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertEqual(store.model.floors[0].openings.first?.id, id)
    }

    // MARK: - Openings ride their wall

    func testDraggedWallCarriesItsOpening() throws {
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .door)))
        let before = try XCTUnwrap(try floor.openings.first)
        let beforeMid = try XCTUnwrap(Geometry.pointOnEdge(
            store.model.floors[0].rooms[0].polygon, edgeIndex: 0,
            t: (before.wall_segment.t0 + before.wall_segment.t1) / 2))

        XCTAssertApplied(store.dispatch(.dragEdge(roomId: "room_a", edgeIndex: 0,
                                                  by: Point(0, -1))))

        let after = try XCTUnwrap(try floor.openings.first)
        XCTAssertEqual(after.wall_segment.t0, before.wall_segment.t0,
                       "parametric ref is untouched by the drag")
        let afterMid = try XCTUnwrap(Geometry.pointOnEdge(
            store.model.floors[0].rooms[0].polygon, edgeIndex: 0,
            t: (after.wall_segment.t0 + after.wall_segment.t1) / 2))
        XCTAssertPointEqual(afterMid, Point(beforeMid.x, beforeMid.y - 1),
                            "the opening's world position moved with its wall")
        XCTAssertModelValid(store.model)
    }

    // MARK: - Placement hit-testing

    func testWallPointResolvesTapToParametricPosition() throws {
        let hit = try XCTUnwrap(HitTesting.wallPoint(Point(4.05, 2.0), floor: try floor,
                                                     within: 0.2))
        XCTAssertEqual(hit.roomId, "room_a")
        XCTAssertEqual(hit.edgeIndex, 1)
        XCTAssertEqual(hit.t, 0.5, accuracy: 1e-9)

        XCTAssertNil(HitTesting.wallPoint(Point(2, 2), floor: try floor, within: 0.2),
                     "a tap in the middle of a room is not a wall tap")
    }

    // MARK: - UndoStack.reset

    func testUndoStackResetDropsAllHistory() throws {
        let undoStack = UndoStack()
        store.onCommit = { undoStack.recordCommit($0) }
        XCTAssertApplied(store.dispatch(.addOpening(roomId: "room_a", edgeIndex: 0, t: 0.5,
                                                    kind: .door)))
        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertTrue(undoStack.canRedo)
        undoStack.reset()
        XCTAssertFalse(undoStack.canUndo)
        XCTAssertFalse(undoStack.canRedo)
        XCTAssertFalse(undoStack.undo(on: store))
        XCTAssertFalse(undoStack.redo(on: store))
    }
}
