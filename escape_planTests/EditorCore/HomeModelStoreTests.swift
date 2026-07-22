//  HomeModelStoreTests.swift — the store's behaviour, action by action.
//
//  The blanket "no sequence of actions can break the model" proof lives in
//  StoreInvariantTests. This file pins down what each action is supposed to DO.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class HomeModelStoreTests: XCTestCase {

    // MARK: - Construction

    func testStoreRefusesAnInvalidSeedModel() throws {
        var broken = try Fixtures.load("bungalow")
        broken.floors[0].rooms[0].polygon.reverse()  // now clockwise

        XCTAssertThrowsError(try HomeModelStore.testStore(broken)) { error in
            guard case HomeModelStore.StoreError.invalidInitialModel(let issues) = error else {
                return XCTFail("expected invalidInitialModel, got \(error)")
            }
            XCTAssertTrue(issues.contains { $0.kind == .polygonOrientation })
        }
    }

    func testActiveFloorDefaultsToTheLowestLevel() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let lowest = store.model.floors.min { $0.level < $1.level }!
        XCTAssertEqual(store.activeFloorId, lowest.id)
    }

    func testNewHomeIsTheSmallestValidDocument() {
        // The schema requires >= 1 floor and >= 1 room per floor, so there is no such thing as
        // a truly empty home — "start from scratch" starts here.
        let model = HomeModelStore.newHome()
        XCTAssertModelValid(model, "the starter home must itself be valid")
        XCTAssertEqual(model.floors.count, 1)
        XCTAssertEqual(model.floors[0].rooms.count, 1)
        XCTAssertEqual(model.floors[0].level, 0)
    }

    // MARK: - Rejection leaves nothing behind

    func testARejectedActionLeavesTheModelBitForBitUnchanged() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let before = store.model

        // Drag a corner of the living room diagonally across the footprint -> bowtie.
        let outcome = store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 0,
                                                 to: Point(5, 4)))
        XCTAssertRejected(outcome, "a self-intersecting drag must not land")
        XCTAssertEqual(store.model, before, "a rejection must not leave partial state behind")
    }

    func testARejectedActionDoesNotFireTheCommitHook() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        var commits = 0
        store.onCommit = { _ in commits += 1 }

        XCTAssertRejected(store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 0,
                                                     to: Point(5, 4))))
        XCTAssertEqual(commits, 0, "S2.2's undo stack must never see a rejected action")
    }

    func testUnknownIdsAreRejectedNotCrashed() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        XCTAssertRejected(store.dispatch(.renameRoom(roomId: "nope", name: "X")))
        XCTAssertRejected(store.dispatch(.deleteRoom(roomId: "nope")))
        XCTAssertRejected(store.dispatch(.renameFloor(floorId: "nope", name: "X")))
        XCTAssertRejected(store.dispatch(.dragVertex(roomId: "nope", vertexIndex: 0, to: Point(0, 0))))
        XCTAssertRejected(store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 99, to: Point(0, 0))))
        XCTAssertRejected(store.dispatch(.dragEdge(roomId: "r_living", edgeIndex: 99, by: Point(1, 0))))
    }

    // MARK: - Commit hook

    func testCommitHookCarriesBeforeAndAfterSnapshots() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        var commit: HomeModelStore.Commit?
        store.onCommit = { commit = $0 }

        XCTAssertApplied(store.dispatch(.renameRoom(roomId: "r_living", name: "Lounge")))

        let c = try XCTUnwrap(commit, "S2.2's undo stack and autosave both hang off this hook")
        XCTAssertEqual(c.action, .renameRoom(roomId: "r_living", name: "Lounge"))
        XCTAssertEqual(c.before.locateRoom("r_living")?.room.name, "Living Room")
        XCTAssertEqual(c.after.locateRoom("r_living")?.room.name, "Lounge")
        XCTAssertEqual(c.after, store.model)
    }

    func testReplaceModelValidatesButDoesNotCommit() throws {
        // This is the path S2.2's undo uses: restoring a snapshot must not push a new one.
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        var commits = 0
        store.onCommit = { _ in commits += 1 }

        let other = try Fixtures.load("apartment")
        XCTAssertApplied(store.replaceModel(other))
        XCTAssertEqual(store.model, other)
        XCTAssertEqual(commits, 0)

        var broken = other
        broken.floors[0].rooms[0].polygon.reverse()
        XCTAssertRejected(store.replaceModel(broken))
        XCTAssertEqual(store.model, other, "a rejected replace must not take effect")
    }

    func testMutationsStampMetaModified() throws {
        var model = try Fixtures.load("bungalow")
        let past = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01T00:00:00Z
        model.meta.modified = past
        let store = try HomeModelStore.testStore(model)

        XCTAssertApplied(store.dispatch(.setHomeName("Renamed")))
        XCTAssertNotEqual(store.model.meta.modified, past)
        XCTAssertEqual(store.model.meta.created, model.meta.created, "created never moves")
    }

    // MARK: - Drags

    func testDragVertexMovesOnlyThatCorner() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let before = store.model.locateRoom("r_living")!.room.polygon

        XCTAssertApplied(store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 1,
                                                    to: Point(5.5, -0.5))))

        let after = store.model.locateRoom("r_living")!.room.polygon
        XCTAssertPointEqual(after[1], Point(5.5, -0.5))
        for i in [0, 2, 3] {
            XCTAssertPointEqual(after[i], before[i], "vertex \(i) should not have moved")
        }
    }

    func testDragEdgeTranslatesBothEndpointsAndStretchesNeighbours() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        // Living room is [0,0],[5,0],[5,4],[0,4]. Edge 2 is the top wall ([5,4] -> [0,4]).
        XCTAssertApplied(store.dispatch(.dragEdge(roomId: "r_living", edgeIndex: 2,
                                                  by: Point(0, 1))))

        let p = store.model.locateRoom("r_living")!.room.polygon
        XCTAssertPointEqual(p[2], Point(5, 5), accuracy: 1e-9)
        XCTAssertPointEqual(p[3], Point(0, 5), accuracy: 1e-9)
        // The side walls stretched because they share those endpoints.
        XCTAssertPointEqual(p[0], Point(0, 0), accuracy: 1e-9)
        XCTAssertPointEqual(p[1], Point(5, 0), accuracy: 1e-9)
        XCTAssertEqual(Geometry.area(p), 25.0, accuracy: 1e-9)
    }

    func testDragEdgeWrapsAroundTheClosingEdge() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        // Edge 3 is the closing wall: vertex 3 -> vertex 0.
        XCTAssertApplied(store.dispatch(.dragEdge(roomId: "r_living", edgeIndex: 3,
                                                  by: Point(-1, 0))))
        let p = store.model.locateRoom("r_living")!.room.polygon
        XCTAssertPointEqual(p[3], Point(-1, 4), accuracy: 1e-9)
        XCTAssertPointEqual(p[0], Point(-1, 0), accuracy: 1e-9)
    }

    func testDragRoomTranslatesTheWholeFootprintRigidly() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let before = store.model.locateRoom("r_bedroom")!.room.polygon

        XCTAssertApplied(store.dispatch(.dragRoom(roomId: "r_bedroom", by: Point(-2, 3))))

        let after = store.model.locateRoom("r_bedroom")!.room.polygon
        XCTAssertEqual(Geometry.area(before), Geometry.area(after), accuracy: 1e-9)
        for (a, b) in zip(before, after) {
            XCTAssertPointEqual(b, Geometry.add(a, Point(-2, 3)), accuracy: 1e-9)
        }
    }

    func testOpeningsRideAlongWhenTheirWallMoves() throws {
        // The whole point of parametric wall_segment refs. The door's stored placement never
        // changes; where it resolves to in the world does.
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))

        func frontDoorPosition() -> Point {
            let floor = store.activeFloor
            let door = floor.openings.first { $0.id == "d_front" }!
            let host = floor.room(door.wall_segment.room_id)!
            return Geometry.pointOnEdge(host.polygon, edgeIndex: door.wall_segment.edge_index,
                                        t: (door.wall_segment.t0 + door.wall_segment.t1) / 2)!
        }

        let doorBefore = store.activeFloor.openings.first { $0.id == "d_front" }!
        let worldBefore = frontDoorPosition()

        // The front door lives on edge 0 of r_living. Drag that wall down 1m.
        XCTAssertApplied(store.dispatch(.dragEdge(roomId: "r_living", edgeIndex: 0,
                                                  by: Point(0, -1))))

        let doorAfter = store.activeFloor.openings.first { $0.id == "d_front" }!
        XCTAssertEqual(doorBefore.wall_segment, doorAfter.wall_segment,
                       "the stored parametric ref must be untouched — no fixup code needed")
        XCTAssertPointEqual(frontDoorPosition(), Geometry.add(worldBefore, Point(0, -1)),
                            accuracy: 1e-9, "the door should have ridden along with its wall")
    }

    // MARK: - Opening drag (S2.2)

    func testDragOpeningSlidesAlongItsWallPreservingWidth() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        // d_front is on r_living's edge 0 (length 5), t0=0.4/t1=0.58, width_m 0.9 -> width in
        // t-units is 0.18. Slide its midpoint to t=0.2.
        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 0.2)))

        let seg = store.activeFloor.openings.first { $0.id == "d_front" }!.wall_segment
        XCTAssertEqual(seg.t0, 0.11, accuracy: 1e-9)
        XCTAssertEqual(seg.t1, 0.29, accuracy: 1e-9)
        XCTAssertEqual(seg.t1 - seg.t0, 0.18, accuracy: 1e-9, "width must be preserved")
    }

    func testDragOpeningClampsAtWallEnds() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        XCTAssertApplied(store.dispatch(.dragOpening(openingId: "d_front", t: 0.0)))
        let seg = store.activeFloor.openings.first { $0.id == "d_front" }!.wall_segment
        XCTAssertGreaterThanOrEqual(seg.t0, 0)
        XCTAssertLessThanOrEqual(seg.t1, 1)
        XCTAssertEqual(seg.t0, 0, accuracy: 1e-9)
    }

    func testDragOpeningRejectsUnknownOpeningId() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        XCTAssertRejected(store.dispatch(.dragOpening(openingId: "nope", t: 0.5)))
    }

    // MARK: - Stairs (S2.2)

    private static let extraStairsFootprint: [Point] = [
        Point(0.5, 0.5), Point(1.5, 0.5), Point(1.5, 1.5), Point(0.5, 1.5)
    ]

    func testAddStairsConnectsTwoFloors() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        XCTAssertApplied(store.dispatch(.addStairs(
            fromFloorId: "f1", fromRoomId: "r_living", toFloorId: "f2", toRoomId: "r_bed_master",
            footprint: Self.extraStairsFootprint, kind: .straight)))

        let added = store.model.stairs.first { $0.from.room_id == "r_living" }
        let stairs = try XCTUnwrap(added)
        XCTAssertEqual(stairs.from.floor_id, "f1")
        XCTAssertEqual(stairs.to.floor_id, "f2")
        XCTAssertEqual(stairs.to.room_id, "r_bed_master")
        XCTAssertEqual(stairs.kind, .straight)
    }

    func testAddStairsRejectedWhenFromAndToFloorsAreTheSame() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        XCTAssertRejected(store.dispatch(.addStairs(
            fromFloorId: "f1", fromRoomId: "r_living", toFloorId: "f1", toRoomId: "r_kitchen",
            footprint: Self.extraStairsFootprint, kind: .straight)))
    }

    func testAddStairsRejectedWhenRoomDoesNotExistOnFloor() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        XCTAssertRejected(store.dispatch(.addStairs(
            fromFloorId: "f1", fromRoomId: "nope", toFloorId: "f2", toRoomId: "r_bed_master",
            footprint: Self.extraStairsFootprint, kind: .straight)))
        XCTAssertRejected(store.dispatch(.addStairs(
            fromFloorId: "f1", fromRoomId: "r_living", toFloorId: "f2", toRoomId: "nope",
            footprint: Self.extraStairsFootprint, kind: .straight)))
    }

    func testDeleteStairsRemovesEntry() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        XCTAssertEqual(store.model.stairs.count, 1)
        XCTAssertApplied(store.dispatch(.deleteStairs(stairsId: "s_main")))
        XCTAssertTrue(store.model.stairs.isEmpty)
    }

    func testDeleteStairsRejectsUnknownId() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        XCTAssertRejected(store.dispatch(.deleteStairs(stairsId: "nope")))
    }

    // MARK: - Snapping through the store

    func testDragVertexSnapsToAnAdjacentRoomsCorner() throws {
        // The bungalow's living room and kitchen share the x=5 wall. Dragging the living room's
        // corner *near* the kitchen's corner should land exactly on it.
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"), snap: .default)

        let outcome = store.dispatch(.dragVertex(roomId: "r_living", vertexIndex: 1,
                                                 to: Point(4.94, 0.04)))
        XCTAssertApplied(outcome)
        guard case .applied(let snap) = outcome else { return XCTFail() }
        XCTAssertEqual(snap?.kind, .vertex)
        XCTAssertPointEqual(store.model.locateRoom("r_living")!.room.polygon[1],
                            Point(5, 0), accuracy: 1e-9)
    }

    func testStoreNeverSnapsARoomToItself() throws {
        // If a room's own corners were snap targets, dragging a corner near its neighbour would
        // collapse the wall to zero length and the polygon would go degenerate.
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"), snap: .default)
        let ctx = store.snapContext(store.model, floorId: store.activeFloorId,
                                    excludingRoom: "r_living")
        let living = store.model.locateRoom("r_living")!.room
        for v in living.polygon {
            XCTAssertFalse(ctx.vertices.contains(v) && !isSharedWithAnotherRoom(v, store: store),
                           "\(v) is the dragged room's own corner and must not be a snap target")
        }
    }

    private func isSharedWithAnotherRoom(_ p: Point, store: HomeModelStore) -> Bool {
        store.activeFloor.rooms
            .filter { $0.id != "r_living" }
            .contains { $0.polygon.contains(p) }
    }

    // MARK: - Rooms

    func testAddRoomPlacesACCWRectangleOnTheGivenFloor() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let floorId = store.activeFloorId

        XCTAssertApplied(store.dispatch(.addRoom(floorId: floorId, origin: Point(20, 20),
                                                 width_m: 3, height_m: 4, type: .bedroom,
                                                 name: "Guest Room")))
        let room = try XCTUnwrap(store.activeFloor.rooms.last)
        XCTAssertEqual(room.name, "Guest Room")
        XCTAssertEqual(room.type, .bedroom)
        XCTAssertEqual(room.source, .manual, "editor-authored rooms are never 'scan'")
        XCTAssertNil(room.confidence)
        XCTAssertTrue(Geometry.isCounterClockwise(room.polygon))
        XCTAssertEqual(Geometry.area(room.polygon), 12, accuracy: 1e-9)
    }

    func testDeleteRoomCascadesToItsOpenings() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let doomed = store.activeFloor.openings.filter { $0.room_ids.contains("r_bath") }
        XCTAssertFalse(doomed.isEmpty, "fixture precondition: the bathroom has openings")

        XCTAssertApplied(store.dispatch(.deleteRoom(roomId: "r_bath")))

        XCTAssertNil(store.model.locateRoom("r_bath"))
        for o in doomed {
            XCTAssertFalse(store.activeFloor.openings.contains { $0.id == o.id },
                           "opening \(o.id) should have gone with its room")
        }
        XCTAssertModelValid(store.model)
    }

    func testDeleteRoomIsRefusedWhenAProfileSleepsThere() throws {
        // Cascading here would silently destroy information the user typed in. Refuse instead.
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let profile = try XCTUnwrap(store.model.profiles.first)

        XCTAssertRejected(store.dispatch(.deleteRoom(roomId: profile.bedroom_room_id)))
        XCTAssertNotNil(store.model.locateRoom(profile.bedroom_room_id))
    }

    func testDeleteRoomIsRefusedWhenStairsLandThere() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let stair = try XCTUnwrap(store.model.stairs.first)
        XCTAssertRejected(store.dispatch(.deleteRoom(roomId: stair.from.room_id)))
    }

    func testCannotDeleteTheLastRoomOnAFloor() throws {
        let store = try HomeModelStore.testStore(HomeModelStore.newHome())
        let onlyRoom = store.activeFloor.rooms[0].id
        XCTAssertRejected(store.dispatch(.deleteRoom(roomId: onlyRoom)),
                          "a floor with no rooms is not representable in the schema")
    }

    func testRenamingToAnEmptyNameIsRejected() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        XCTAssertRejected(store.dispatch(.renameRoom(roomId: "r_living", name: "")))
        XCTAssertRejected(store.dispatch(.setHomeName("")))
    }

    // MARK: - Floors

    func testAddFloorTakesTheNextFreeLevelAndIsBornValid() throws {
        let store = try HomeModelStore.testStore(HomeModelStore.newHome())
        let ground = store.activeFloorId

        XCTAssertApplied(store.dispatch(.addFloor(relativeTo: ground, above: true)))
        XCTAssertApplied(store.dispatch(.addFloor(relativeTo: ground, above: true)))
        XCTAssertApplied(store.dispatch(.addFloor(relativeTo: ground, above: false)))

        XCTAssertEqual(store.model.floors.map(\.level), [-1, 0, 1, 2],
                       "adding above twice must not collide on level 1")
        XCTAssertModelValid(store.model)
        for floor in store.model.floors {
            XCTAssertFalse(floor.rooms.isEmpty, "every floor is seeded with a starter room")
        }
    }

    func testFloorsStaySortedByLevel() throws {
        let store = try HomeModelStore.testStore(HomeModelStore.newHome())
        XCTAssertApplied(store.dispatch(.addFloor(relativeTo: store.activeFloorId, above: false)))
        XCTAssertEqual(store.model.floors.map(\.level).sorted(), store.model.floors.map(\.level))
    }

    func testCannotDeleteTheOnlyFloor() throws {
        let store = try HomeModelStore.testStore(HomeModelStore.newHome())
        XCTAssertRejected(store.dispatch(.deleteFloor(floorId: store.activeFloorId)))
    }

    func testDeletingAFloorTakesItsStairsAndReassignsTheActiveFloor() throws {
        var model = try Fixtures.load("twostory")
        model.profiles = []  // profiles are tested separately; isolate the stair behaviour here
        let store = try HomeModelStore.testStore(model)

        let upper = store.model.floors.max { $0.level < $1.level }!
        XCTAssertFalse(store.model.stairs.isEmpty, "fixture precondition: twostory has stairs")
        XCTAssertTrue(store.setActiveFloor(upper.id))

        XCTAssertApplied(store.dispatch(.deleteFloor(floorId: upper.id)))
        XCTAssertNil(store.model.floor(upper.id))
        XCTAssertTrue(store.model.stairs.isEmpty, "stairs to nowhere must not survive")
        XCTAssertNotEqual(store.activeFloorId, upper.id, "the active floor must still exist")
        XCTAssertNotNil(store.model.floor(store.activeFloorId))
        XCTAssertModelValid(store.model)
    }

    func testDeletingAFloorIsRefusedWhenSomeoneSleepsOnIt() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let profile = try XCTUnwrap(store.model.profiles.first)
        let floorId = store.model.locateRoom(profile.bedroom_room_id)!.floorId

        XCTAssertRejected(store.dispatch(.deleteFloor(floorId: floorId)))
    }

    func testSetActiveFloorRejectsUnknownIdsAndClearsSelection() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        store.select(.room(roomId: "r_living"))

        XCTAssertFalse(store.setActiveFloor("nope"))
        XCTAssertEqual(store.selection, .room(roomId: "r_living"), "a failed switch changes nothing")

        let other = store.model.floors.first { $0.id != store.activeFloorId }!
        XCTAssertTrue(store.setActiveFloor(other.id))
        XCTAssertEqual(store.selection, .none, "stale cross-floor selection must be dropped")
    }

    func testInvalidFloorHeightIsRejected() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        XCTAssertRejected(store.dispatch(.setFloorHeight(floorId: store.activeFloorId, height_m: 0)))
        XCTAssertRejected(store.dispatch(.setFloorHeight(floorId: store.activeFloorId, height_m: -3)))
        XCTAssertApplied(store.dispatch(.setFloorHeight(floorId: store.activeFloorId, height_m: 2.4)))
    }

    // MARK: - Selection

    func testDeletingASelectedRoomClearsTheSelection() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        store.select(.vertex(roomId: "r_bath", vertexIndex: 2))

        XCTAssertApplied(store.dispatch(.deleteRoom(roomId: "r_bath")))
        XCTAssertEqual(store.selection, .none, "a selection pointing at a deleted room is a crash waiting to happen")
    }

    // MARK: - Ids

    func testGeneratedIdsAreUniqueAcrossEntityKinds() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        for i in 0..<10 {
            XCTAssertApplied(store.dispatch(.addRoom(floorId: store.activeFloorId,
                                                     origin: Point(Double(i) * 10, 40),
                                                     width_m: 3, height_m: 3,
                                                     type: .other, name: "R\(i)")))
        }
        XCTAssertModelValid(store.model, "id collisions would surface here")
    }
}
