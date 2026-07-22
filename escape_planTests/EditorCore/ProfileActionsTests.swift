//  ProfileActionsTests.swift — the S3.4 profile CRUD actions, action by action.
//
//  Same shape as HomeModelStoreTests: what each action DOES, and that every rejection leaves
//  the model bit-for-bit unchanged. The twostory fixture ships with Maya (child) and Grandpa
//  (mobility_limited), so it doubles as the "edit existing" test bed.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class ProfileActionsTests: XCTestCase {

    // MARK: - Add

    func testAddProfileAppendsAndValidates() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let room = store.model.floors[0].rooms[0].id

        let outcome = store.dispatch(.addProfile(profileId: "p_new", name: "Sam",
                                                 tags: [.child, .pet],
                                                 bedroom_room_id: room))
        XCTAssertApplied(outcome)
        let added = store.model.profiles.first { $0.id == "p_new" }
        XCTAssertEqual(added?.name, "Sam")
        XCTAssertEqual(added?.tags, [.child, .pet])
        XCTAssertEqual(added?.bedroom_room_id, room)
        XCTAssertModelValid(store.model)
    }

    func testAddProfileRejectsEmptyName() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let before = store.model
        let room = store.model.floors[0].rooms[0].id

        XCTAssertRejected(store.dispatch(.addProfile(profileId: "p_new", name: "",
                                                     tags: [], bedroom_room_id: room)))
        XCTAssertEqual(store.model, before)
    }

    func testAddProfileRejectsDanglingBedroom() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let before = store.model

        XCTAssertRejected(store.dispatch(.addProfile(profileId: "p_new", name: "Sam",
                                                     tags: [], bedroom_room_id: "no_such_room")))
        XCTAssertEqual(store.model, before)
    }

    func testAddProfileRejectsDuplicateId() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let existing = store.model.profiles[0]
        let before = store.model

        XCTAssertRejected(store.dispatch(.addProfile(profileId: existing.id, name: "Clone",
                                                     tags: [],
                                                     bedroom_room_id: existing.bedroom_room_id)))
        XCTAssertEqual(store.model, before)
    }

    func testAddProfileRejectsReservedExteriorId() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let room = store.model.floors[0].rooms[0].id

        XCTAssertRejected(store.dispatch(.addProfile(profileId: "EXTERIOR", name: "Sam",
                                                     tags: [], bedroom_room_id: room)))
    }

    // MARK: - Update

    func testUpdateProfileReplacesFields() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let target = store.model.profiles[0]
        let otherRoom = store.model.floors
            .flatMap(\.rooms)
            .first { $0.id != target.bedroom_room_id }!

        let outcome = store.dispatch(.updateProfile(profileId: target.id, name: "Renamed",
                                                    tags: [.elderly, .mobility_limited],
                                                    bedroom_room_id: otherRoom.id))
        XCTAssertApplied(outcome)
        let updated = store.model.profiles.first { $0.id == target.id }
        XCTAssertEqual(updated?.name, "Renamed")
        XCTAssertEqual(updated?.tags, [.elderly, .mobility_limited])
        XCTAssertEqual(updated?.bedroom_room_id, otherRoom.id)
        XCTAssertEqual(store.model.profiles.count, 2, "update must not add or remove")
        XCTAssertModelValid(store.model)
    }

    func testUpdateUnknownProfileIsRejected() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let before = store.model
        let room = store.model.floors[0].rooms[0].id

        XCTAssertRejected(store.dispatch(.updateProfile(profileId: "no_such_profile",
                                                        name: "Ghost", tags: [],
                                                        bedroom_room_id: room)))
        XCTAssertEqual(store.model, before)
    }

    // MARK: - Delete

    func testDeleteProfileRemovesIt() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let target = store.model.profiles[0]

        XCTAssertApplied(store.dispatch(.deleteProfile(profileId: target.id)))
        XCTAssertFalse(store.model.profiles.contains { $0.id == target.id })
        XCTAssertModelValid(store.model)
    }

    func testDeleteUnknownProfileIsRejected() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let before = store.model

        XCTAssertRejected(store.dispatch(.deleteProfile(profileId: "no_such_profile")))
        XCTAssertEqual(store.model, before)
    }

    // MARK: - Interplay with room deletion (S2.1 refusal, S3.4 unblocks it)

    func testDeletingAProfileUnblocksDeletingItsBedroom() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("twostory"))
        let target = store.model.profiles[0]
        let bedroom = target.bedroom_room_id

        XCTAssertRejected(store.dispatch(.deleteRoom(roomId: bedroom)),
                          "a room someone sleeps in must not be deletable")
        XCTAssertApplied(store.dispatch(.deleteProfile(profileId: target.id)))
        XCTAssertApplied(store.dispatch(.deleteRoom(roomId: bedroom)),
                         "with the profile gone the room delete must succeed")
        XCTAssertModelValid(store.model)
    }

    // MARK: - Commit hook (autosave/undo seam)

    func testProfileActionsFireOnCommit() throws {
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        let room = store.model.floors[0].rooms[0].id
        var commits: [HomeModelStore.Commit] = []
        store.onCommit = { commits.append($0) }

        store.dispatch(.addProfile(profileId: "p_new", name: "Sam", tags: [],
                                   bedroom_room_id: room))
        store.dispatch(.updateProfile(profileId: "p_new", name: "Sam Jr", tags: [.child],
                                      bedroom_room_id: room))
        store.dispatch(.deleteProfile(profileId: "p_new"))

        XCTAssertEqual(commits.count, 3)
        XCTAssertEqual(commits.map(\.action.undoLabel),
                       ["Add Profile", "Edit Profile", "Delete Profile"])
        XCTAssertEqual(commits[2].after.profiles.count,
                       commits[0].before.profiles.count)
    }
}
