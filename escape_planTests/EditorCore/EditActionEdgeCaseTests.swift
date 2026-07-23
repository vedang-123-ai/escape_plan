//  EditActionEdgeCaseTests.swift — edges of the S2.2/S3.4 EditActions that the original
//  lane suites (HomeModelStoreTests, ProfileActionsTests, UndoStackTests) don't cover:
//  dragOpening far-end/out-of-range clamping and boundary width shrink, degenerate stairs
//  footprints, stairs selection clearing, profile duplicate-tag / update-to-invalid
//  rejections, floor deletion vs sleeping profiles, and undo coalescing over dragOpening.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class EditActionEdgeCaseTests: XCTestCase {

    // MARK: - dragOpening clamping
    //
    // Bungalow's d_front sits on r_living edge 0 (length 5 m), t0=0.4/t1=0.58, width_m 0.9,
    // so half the width in t-units is 0.09.

    private func frontDoorSegment(in store: HomeModelStore) -> WallSegmentRef {
        store.activeFloor.openings.first { $0.id == "d_front" }!.wall_segment
    }

    func testDragOpeningClampsAtTheFarEnd() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 1.0)))

        let seg = frontDoorSegment(in: store)
        XCTAssertEqual(seg.t1, 1, accuracy: 1e-9, "the far edge must clamp to the wall end")
        XCTAssertEqual(seg.t0, 0.91, accuracy: 1e-9)
        XCTAssertModelValid(store.model)
    }

    func testDragOpeningOutOfRangeInputClampsInsteadOfRejecting() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))

        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: -0.5)),
                         "an overshooting gesture must clamp, not bounce the whole drag")
        var seg = frontDoorSegment(in: store)
        XCTAssertEqual(seg.t0, 0, accuracy: 1e-9)
        XCTAssertEqual(seg.t1, 0.09, accuracy: 1e-9)

        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 1.5)))
        seg = frontDoorSegment(in: store)
        XCTAssertEqual(seg.t0, 0.91, accuracy: 1e-9)
        XCTAssertEqual(seg.t1, 1, accuracy: 1e-9)
        XCTAssertModelValid(store.model)
    }

    func testDragOpeningAtTheBoundaryShrinksWidthButStaysValid() throws {
        // Current (deliberately pinned) behavior: t0/t1 are clamped independently, so at a
        // wall end the parametric span halves (0.18 -> 0.09) instead of preserving width_m.
        // If the reducer ever changes to shift-preserve width, this test should be updated
        // alongside that decision — it exists so the change is a choice, not an accident.
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 0)))

        let seg = frontDoorSegment(in: store)
        XCTAssertEqual(seg.t1 - seg.t0, 0.09, accuracy: 1e-9,
                       "independent clamping halves the span at the wall end")
        XCTAssertLessThan(seg.t0, seg.t1, "the span must never collapse to zero or invert")
        XCTAssertModelValid(store.model)
    }

    func testDragOpeningMidWallPreservesParametricRef() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let before = frontDoorSegment(in: store)

        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 0.7)))

        let after = frontDoorSegment(in: store)
        XCTAssertEqual(after.room_id, before.room_id, "a drag must never re-home the opening")
        XCTAssertEqual(after.edge_index, before.edge_index, "a drag must never change the host edge")
        XCTAssertEqual(after.t1 - after.t0, before.t1 - before.t0, accuracy: 1e-9,
                       "width is preserved away from the wall ends")
    }

    // MARK: - Stairs footprint validation

    func testAddStairsRejectsAFootprintWithTooFewVertices() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let before = store.model
        XCTAssertRejected(store.dispatch(.addStairs(
            fromFloorId: "f1", fromRoomId: "r_living", toFloorId: "f2", toRoomId: "r_bed_master",
            footprint: [Point(0, 0), Point(1, 0)], kind: .straight)))
        XCTAssertEqual(store.model, before, "a rejected action must leave the model untouched")
    }

    func testAddStairsRejectsASelfIntersectingFootprint() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        // A bowtie: edges 0-1 and 2-3 cross.
        let bowtie = [Point(0, 0), Point(1, 1), Point(1, 0), Point(0, 1)]
        XCTAssertRejected(store.dispatch(.addStairs(
            fromFloorId: "f1", fromRoomId: "r_living", toFloorId: "f2", toRoomId: "r_bed_master",
            footprint: bowtie, kind: .straight)))
    }

    func testDeleteStairsClearsASelectionPointingAtIt() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        store.select(.stairs(stairsId: "s_main"))

        XCTAssertApplied(store.dispatch(.deleteStairs(stairsId: "s_main")))
        XCTAssertEqual(store.selection, .none,
                       "a selection pointing at deleted stairs is a crash waiting to happen")
    }

    func testDeleteStairsKeepsAnUnrelatedSelection() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        store.select(.room(roomId: "r_living"))

        XCTAssertApplied(store.dispatch(.deleteStairs(stairsId: "s_main")))
        XCTAssertEqual(store.selection, .room(roomId: "r_living"),
                       "deleting stairs must not disturb an unrelated selection")
    }

    // MARK: - Profile edges (beyond ProfileActionsTests)

    func testAddProfileRejectsDuplicateTags() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let before = store.model
        XCTAssertRejected(store.dispatch(.addProfile(
            profileId: "p_twin", name: "Twin", tags: [.child, .child],
            bedroom_room_id: "r_bed_kids")))
        XCTAssertEqual(store.model, before)
    }

    func testUpdateProfileRejectsAnEmptyName() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let before = store.model
        XCTAssertRejected(store.dispatch(.updateProfile(
            profileId: "p_maya", name: "", tags: [.child], bedroom_room_id: "r_bed_kids")))
        XCTAssertEqual(store.model, before, "the existing profile must survive a bad edit intact")
    }

    func testUpdateProfileRejectsADanglingBedroom() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let before = store.model
        XCTAssertRejected(store.dispatch(.updateProfile(
            profileId: "p_maya", name: "Maya", tags: [.child], bedroom_room_id: "r_nope")))
        XCTAssertEqual(store.model, before)
    }

    func testDeleteFloorIsRefusedWhileAProfileSleepsThere() throws {
        // Both twostory profiles sleep on f2.
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        XCTAssertRejected(store.dispatch(.deleteFloor(floorId: "f2")),
                          "deleting a floor must not orphan a profile's bedroom")

        XCTAssertApplied(store.dispatch(.deleteProfile(profileId: "p_maya")))
        XCTAssertApplied(store.dispatch(.deleteProfile(profileId: "p_grandpa")))
        XCTAssertApplied(store.dispatch(.deleteFloor(floorId: "f2")),
                         "with the sleepers gone the same deletion must go through")
        XCTAssertModelValid(store.model)
    }

    // MARK: - Undo coalescing over dragOpening

    func testCoalescedOpeningDragIsOneUndoEntry() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let undoStack = UndoStack()
        store.onCommit = { undoStack.recordCommit($0) }
        let before = store.model

        undoStack.beginCoalescing(snapshot: store.model)
        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 0.35)))
        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 0.27)))
        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 0.2)))
        let afterGesture = store.model
        undoStack.endCoalescing()

        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertEqual(store.model, before,
                       "one undo must restore the pre-gesture t0/t1, not just the last step")
        let seg = frontDoorSegment(in: store)
        XCTAssertEqual(seg.t0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(seg.t1, 0.58, accuracy: 1e-9)
        XCTAssertFalse(undoStack.canUndo, "the whole gesture must have been exactly one entry")

        XCTAssertTrue(undoStack.redo(on: store))
        XCTAssertEqual(store.model, afterGesture)
        XCTAssertEqual(frontDoorSegment(in: store).t0, 0.11, accuracy: 1e-9)
    }
}
