//  OpeningOverlapParityTests.swift — Client-backend parity test for opening overlaps (A17-02).
//
//  Tests that homes with overlapping openings on the same wall segment (as accepted by
//  the backend Pydantic models and JSON Schema) do not brick the House Editor session,
//  can be initialized in HomeModelStore, and produce a repairable warning.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class OpeningOverlapParityTests: XCTestCase {

    private func homeWithOverlappingOpenings() -> HomeModel {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let room = Room(
            id: "room_main",
            name: "Main Room",
            type: .living,
            polygon: [Point(0, 0), Point(5, 0), Point(5, 5), Point(0, 5)],
            source: .manual,
            confidence: nil
        )
        // Two overlapping doors on edge 0 (from (0,0) to (5,0))
        let doorA = Opening(
            id: "door_a",
            kind: .door,
            wall_segment: WallSegmentRef(room_id: "room_main", edge_index: 0, t0: 0.2, t1: 0.5),
            room_ids: ["room_main", EXTERIOR_ID],
            width_m: 1.5,
            height_m: 2.0,
            sill_height_m: 0.0,
            source: .manual,
            confidence: nil
        )
        let doorB = Opening(
            id: "door_b",
            kind: .door,
            wall_segment: WallSegmentRef(room_id: "room_main", edge_index: 0, t0: 0.4, t1: 0.7),
            room_ids: ["room_main", EXTERIOR_ID],
            width_m: 1.5,
            height_m: 2.0,
            sill_height_m: 0.0,
            source: .manual,
            confidence: nil
        )
        return HomeModel(
            schema_version: HomeModel.currentSchemaVersion,
            home_id: "home_overlap",
            name: "Home with Overlapping Openings",
            floors: [Floor(id: "f0", level: 0, name: "Ground", height_m: 2.7, rooms: [room], openings: [doorA, doorB])],
            meta: Meta(created: stamp, modified: stamp)
        )
    }

    func testOverlappingOpeningsDoesNotBrickEditorStoreInit() throws {
        let model = homeWithOverlappingOpenings()

        // 1. Structural validation for editor gate has no blocking errors
        let blockingIssues = EditorValidation.validate(model)
        XCTAssertTrue(blockingIssues.isEmpty, "Overlapping openings must not produce blocking errors that brick the editor")

        // 2. Produces a non-blocking repairable warning
        let warnings = EditorValidation.warnings(model)
        XCTAssertFalse(warnings.isEmpty, "Overlapping openings should produce a warning")
        XCTAssertTrue(warnings.contains { $0.kind == .openingPlacement && $0.isWarning })

        // 3. HomeModelStore initializes without throwing StoreError.invalidInitialModel
        XCTAssertNoThrow(try HomeModelStore.testStore(model), "Editor store must open the home successfully")
        let store = try HomeModelStore.testStore(model)
        XCTAssertEqual(store.model.floors[0].openings.count, 2)
    }

    func testAutoResolutionOrRepairViaDrag() throws {
        let model = homeWithOverlappingOpenings()
        let store = try HomeModelStore.testStore(model)

        // User can repair the overlap by dragging door_b away to non-overlapping t=0.85
        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "door_b", t: 0.85)))
        XCTAssertModelValid(store.model)
        let remainingWarnings = EditorValidation.warnings(store.model)
        XCTAssertTrue(remainingWarnings.isEmpty, "After dragging away, no warnings remain")
    }
}
