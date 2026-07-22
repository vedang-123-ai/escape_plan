//  UndoStackTests.swift — undo/redo bookkeeping on top of HomeModelStore.Commit snapshots.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class UndoStackTests: XCTestCase {

    private func makeStore() throws -> (HomeModelStore, UndoStack) {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let undoStack = UndoStack()
        store.onCommit = { undoStack.recordCommit($0) }
        return (store, undoStack)
    }

    func testUndoRestoresThePreCommitSnapshot() throws {
        let (store, undoStack) = try makeStore()
        let before = store.model

        XCTAssertApplied(store.dispatch(.renameRoom(roomId: "r_living", name: "Lounge")))
        XCTAssertTrue(undoStack.canUndo)

        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertEqual(store.model, before)
    }

    func testRedoReappliesAnUndoneCommit() throws {
        let (store, undoStack) = try makeStore()
        XCTAssertApplied(store.dispatch(.renameRoom(roomId: "r_living", name: "Lounge")))
        let after = store.model

        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertTrue(undoStack.canRedo)
        XCTAssertTrue(undoStack.redo(on: store))
        XCTAssertEqual(store.model, after)
    }

    func testUndoingClearsRedoOnNewAction() throws {
        let (store, undoStack) = try makeStore()
        XCTAssertApplied(store.dispatch(.renameRoom(roomId: "r_living", name: "Lounge")))
        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertTrue(undoStack.canRedo)

        XCTAssertApplied(store.dispatch(.renameRoom(roomId: "r_living", name: "Den")))
        XCTAssertFalse(undoStack.canRedo, "a fresh action must invalidate the redo history")
    }

    func testCoalescingGroupsAContinuousDragIntoOneUndoEntry() throws {
        let (store, undoStack) = try makeStore()
        let before = store.model

        undoStack.beginCoalescing(snapshot: store.model)
        XCTAssertApplied(store.dispatch(.dragRoom(roomId: "r_bedroom", by: Point(0.1, 0))))
        XCTAssertApplied(store.dispatch(.dragRoom(roomId: "r_bedroom", by: Point(0.1, 0))))
        XCTAssertApplied(store.dispatch(.dragRoom(roomId: "r_bedroom", by: Point(0.1, 0))))
        let afterGesture = store.model
        undoStack.endCoalescing()

        XCTAssertTrue(undoStack.canUndo)
        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertEqual(store.model, before, "one undo must restore the PRE-gesture state, not just the last step")
        XCTAssertFalse(undoStack.canUndo, "the whole gesture must have been exactly one entry")

        XCTAssertTrue(undoStack.redo(on: store))
        XCTAssertEqual(store.model, afterGesture)
    }

    func testCoalescingWithNoActualChangeDoesNotPushAnEmptyEntry() throws {
        let (store, undoStack) = try makeStore()
        undoStack.beginCoalescing(snapshot: store.model)
        undoStack.endCoalescing()
        XCTAssertFalse(undoStack.canUndo)
    }

    func testCoalescingWhereEveryStepIsRejectedPushesNothing() throws {
        let (store, undoStack) = try makeStore()
        undoStack.beginCoalescing(snapshot: store.model)
        // Out-of-range index -> every dispatch during this "gesture" is rejected.
        XCTAssertRejected(store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 99, to: Point(0, 0))))
        undoStack.endCoalescing()
        XCTAssertFalse(undoStack.canUndo)
    }

    func testNonContinuousActionsPushOnePerDispatch() throws {
        let (store, undoStack) = try makeStore()
        XCTAssertApplied(store.dispatch(.renameRoom(roomId: "r_living", name: "Lounge")))
        XCTAssertApplied(store.dispatch(.renameRoom(roomId: "r_kitchen", name: "Cookhouse")))

        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertEqual(store.model.locateRoom("r_kitchen")?.room.name, "Kitchen")
        XCTAssertEqual(store.model.locateRoom("r_living")?.room.name, "Lounge",
                       "each non-continuous action is its own undo entry")

        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertEqual(store.model.locateRoom("r_living")?.room.name, "Living Room")
    }
}
