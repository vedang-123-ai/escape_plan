//  ObjectActionsTests.swift — the v1.1 object vocabulary: box primitives that render as
//  prisms and block within-room routing. Store invariants + rotated-rect hit-testing.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class ObjectActionsTests: XCTestCase {

    private func makeStore() throws -> HomeModelStore {
        try HomeModelStore.testStore(try Fixtures.load("bungalow"))
    }

    private func addSofa(_ store: HomeModelStore, id: String = "o1") {
        store.dispatch(.addObject(objectId: id, floorId: store.activeFloorId, category: .sofa,
                                  center: Point(2.5, 2.0), size_m: [2.0, 0.9], height_m: 0.8))
    }

    func testAddObjectAppendsWithManualSourceAndValidates() throws {
        let store = try makeStore()
        addSofa(store)
        let object = try XCTUnwrap(store.activeFloor.objects.first)
        XCTAssertEqual(object.id, "o1")
        XCTAssertEqual(object.category, .sofa)
        XCTAssertEqual(object.source, .manual)
        XCTAssertEqual(object.rotation_deg, 0)
        XCTAssertModelValid(store.model)
    }

    func testAddObjectRejectsNonPositiveSize() throws {
        let store = try makeStore()
        let outcome = store.dispatch(.addObject(objectId: "o1", floorId: store.activeFloorId,
                                                category: .table, center: Point(1, 1),
                                                size_m: [0, 1], height_m: 0.5))
        XCTAssertFalse(outcome.didApply)
        XCTAssertTrue(store.activeFloor.objects.isEmpty)
    }

    func testAddObjectRejectsDuplicateId() throws {
        let store = try makeStore()
        addSofa(store)
        let outcome = store.dispatch(.addObject(objectId: "o1", floorId: store.activeFloorId,
                                                category: .bed, center: Point(1, 6),
                                                size_m: [1.9, 1.4], height_m: 0.6))
        XCTAssertFalse(outcome.didApply, "object ids share the global id namespace")
        XCTAssertEqual(store.activeFloor.objects.count, 1)
    }

    func testDragObjectTranslatesCenter() throws {
        let store = try makeStore()
        addSofa(store)
        XCTAssertTrue(store.dispatch(.dragObject(objectId: "o1", by: Point(0.5, -0.25))).didApply)
        let object = try XCTUnwrap(store.activeFloor.objects.first)
        XCTAssertEqual(object.center.x, 3.0, accuracy: 1e-9)
        XCTAssertEqual(object.center.y, 1.75, accuracy: 1e-9)
    }

    func testRotateResizeAndRecategorize() throws {
        let store = try makeStore()
        addSofa(store)
        XCTAssertTrue(store.dispatch(.rotateObject(objectId: "o1", rotation_deg: 90)).didApply)
        XCTAssertTrue(store.dispatch(.resizeObject(objectId: "o1", size_m: [1.0, 0.5],
                                                   height_m: 1.1)).didApply)
        XCTAssertTrue(store.dispatch(.setObjectCategory(objectId: "o1", category: .storage)).didApply)
        let object = try XCTUnwrap(store.activeFloor.objects.first)
        XCTAssertEqual(object.rotation_deg, 90, accuracy: 1e-9)
        XCTAssertEqual(object.size_m, [1.0, 0.5])
        XCTAssertEqual(object.height_m, 1.1, accuracy: 1e-9)
        XCTAssertEqual(object.category, .storage)
    }

    func testResizeRejectsNonPositiveAndLeavesModelUntouched() throws {
        let store = try makeStore()
        addSofa(store)
        let before = store.model
        XCTAssertFalse(store.dispatch(.resizeObject(objectId: "o1", size_m: [1.0],
                                                    height_m: 1.0)).didApply)
        XCTAssertFalse(store.dispatch(.resizeObject(objectId: "o1", size_m: [1.0, -2],
                                                    height_m: 1.0)).didApply)
        XCTAssertEqual(store.model, before)
    }

    func testDeleteObjectRemovesItAndUnknownIdsAreRejected() throws {
        let store = try makeStore()
        addSofa(store)
        XCTAssertTrue(store.dispatch(.deleteObject(objectId: "o1")).didApply)
        XCTAssertTrue(store.activeFloor.objects.isEmpty)
        XCTAssertFalse(store.dispatch(.deleteObject(objectId: "o1")).didApply)
        XCTAssertFalse(store.dispatch(.dragObject(objectId: "ghost", by: Point(1, 0))).didApply)
    }

    func testDragObjectIsAContinuousDragForUndoCoalescing() {
        XCTAssertTrue(EditAction.dragObject(objectId: "o1", by: Point(0, 0)).isContinuousDrag)
        XCTAssertFalse(EditAction.rotateObject(objectId: "o1", rotation_deg: 45).isContinuousDrag)
    }

    func testBlockedFixtureDecodesAndIsValid() throws {
        let model = try Fixtures.load("bungalow-blocked")
        XCTAssertEqual(model.floors[0].objects.count, 2)
        XCTAssertModelValid(model)
    }
}

final class ObjectHitTestingTests: XCTestCase {

    private let sofa = FloorObject(id: "o1", category: .sofa, center: Point(2, 2),
                                   size_m: [2.0, 1.0], height_m: 0.8, source: .manual)

    func testAxisAlignedContainment() {
        XCTAssertTrue(HitTesting.objectContains(sofa, Point(2, 2)))
        XCTAssertTrue(HitTesting.objectContains(sofa, Point(2.99, 2.49)))
        XCTAssertFalse(HitTesting.objectContains(sofa, Point(3.1, 2)))
        XCTAssertFalse(HitTesting.objectContains(sofa, Point(2, 2.6)))
    }

    func testRotatedContainment() {
        var rotated = sofa
        rotated.rotation_deg = 90
        // After 90° the long axis runs along y: (2, 2.9) is inside, (2.9, 2) no longer is.
        XCTAssertTrue(HitTesting.objectContains(rotated, Point(2, 2.9)))
        XCTAssertFalse(HitTesting.objectContains(rotated, Point(2.9, 2)))
    }

    func testHitTestPrefersObjectOverRoomInterior() throws {
        var model = try Fixtures.load("bungalow")
        model.floors[0].objects.append(sofa)
        let floor = model.floors[0]
        XCTAssertEqual(HitTesting.hitTest(Point(2, 2), floor: floor,
                                          tolerances: .init(vertexRadiusM: 0.1, wallRadiusM: 0.1)),
                       .object(objectId: "o1"))
        // Away from the sofa the same tap still selects the room.
        XCTAssertEqual(HitTesting.hitTest(Point(4, 3), floor: floor,
                                          tolerances: .init(vertexRadiusM: 0.1, wallRadiusM: 0.1)),
                       .room(roomId: "r_living"))
    }

    func testTopmostObjectWinsWhenOverlapping() throws {
        var model = try Fixtures.load("bungalow")
        model.floors[0].objects.append(sofa)
        model.floors[0].objects.append(FloorObject(id: "o2", category: .table,
                                                   center: Point(2, 2), size_m: [0.8, 0.8],
                                                   height_m: 0.7, source: .manual))
        XCTAssertEqual(HitTesting.topObject(Point(2, 2), floor: model.floors[0]),
                       .object(objectId: "o2"),
                       "later-listed objects render on top and must hit-test the same way")
    }
}
