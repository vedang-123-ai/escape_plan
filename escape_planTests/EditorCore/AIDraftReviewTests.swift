//  AIDraftReviewTests.swift — the C2 review gate's pure core: ai_plan elements always need
//  review, `hasAIDraftContent` detects any leftover draft, and `confirmAIDraft` flips
//  everything to manual in one undoable commit.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class AIDraftReviewTests: XCTestCase {

    private func draftHome() throws -> HomeModel {
        var model = try Fixtures.load("bungalow")
        for f in model.floors.indices {
            for r in model.floors[f].rooms.indices {
                model.floors[f].rooms[r].source = .ai_plan
                model.floors[f].rooms[r].confidence = 0.5
            }
            for o in model.floors[f].openings.indices {
                model.floors[f].openings[o].source = .ai_plan
                model.floors[f].openings[o].confidence = 0.5
            }
        }
        return model
    }

    func testAIPlanAlwaysNeedsReviewRegardlessOfConfidence() {
        XCTAssertTrue(HitTesting.needsReview(source: .ai_plan, confidence: 0.99))
        XCTAssertTrue(HitTesting.needsReview(source: .ai_plan, confidence: nil))
        XCTAssertFalse(HitTesting.needsReview(source: .manual, confidence: nil))
        XCTAssertTrue(HitTesting.needsReview(source: .scan, confidence: 0.3))
        XCTAssertFalse(HitTesting.needsReview(source: .scan, confidence: 0.9))
    }

    func testObjectsJoinTheReviewList() throws {
        var model = try Fixtures.load("bungalow-blocked")
        model.floors[0].objects[0].source = .ai_plan
        model.floors[0].objects[0].confidence = 0.5
        let ids = HitTesting.itemsNeedingReview(floor: model.floors[0])
        XCTAssertTrue(ids.contains(model.floors[0].objects[0].id))
    }

    func testHasAIDraftContentDetectsAnySingleDraftElement() throws {
        var model = try Fixtures.load("bungalow")
        XCTAssertFalse(model.hasAIDraftContent)
        model.floors[0].openings[0].source = .ai_plan
        model.floors[0].openings[0].confidence = 0.5
        XCTAssertTrue(model.hasAIDraftContent)
    }

    func testConfirmAIDraftFlipsEverythingToManualInOneUndoableCommit() throws {
        let store = try HomeModelStore.testStore(try draftHome())
        XCTAssertTrue(store.model.hasAIDraftContent)

        let undoStack = UndoStack()
        store.onCommit = { undoStack.recordCommit($0) }

        XCTAssertTrue(store.dispatch(.confirmAIDraft).didApply)
        XCTAssertFalse(store.model.hasAIDraftContent)
        XCTAssertTrue(store.model.floors.allSatisfy { floor in
            floor.rooms.allSatisfy { $0.source == .manual }
                && floor.openings.allSatisfy { $0.source == .manual }
        })

        // One commit, one undo — and undo restores the draft state.
        XCTAssertTrue(undoStack.canUndo)
        XCTAssertTrue(undoStack.undo(on: store))
        XCTAssertTrue(store.model.hasAIDraftContent)
    }

    func testConfirmOnAFullyManualHomeIsANoOpCommit() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let before = store.model
        XCTAssertTrue(store.dispatch(.confirmAIDraft).didApply)
        // Only meta.modified changes.
        var after = store.model
        after.meta = before.meta
        XCTAssertEqual(after, before)
    }
}
