//  SyncReconcilerTests.swift — the decision table, every cell of it.
//
//  `SyncReconciler.plan` is a pure function over three value inputs, which is what lets S8.4's
//  hard half be verified on a machine with no simulator. These tests build the inputs by hand
//  and assert the whole decision rather than poking at the outcome of a network round trip.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class SyncReconcilerTests: XCTestCase {

    private var base: HomeModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try Fixtures.load("bungalow")
    }

    // MARK: - Builders

    private func local(_ home: HomeModel) -> LocalHome { LocalHome(model: home) }

    private func remote(_ home: HomeModel,
                        id: String = "srv-1",
                        revision: Int = 1,
                        updatedAt: Date = Date(timeIntervalSince1970: 1_000)) -> StoredHome {
        // Built through the decoder rather than a memberwise init, so these tests also keep
        // exercising the wire shape they will actually be handed.
        let homeJSON = String(decoding: try! HomeModel.encoder().encode(home), as: UTF8.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: updatedAt)
        let json = """
        {"id":"\(id)","user_id":"u-1","home":\(homeJSON),"revision":\(revision),\
        "created_at":"\(stamp)","updated_at":"\(stamp)"}
        """
        return try! HomeModel.decoder.decode(StoredHome.self, from: Data(json.utf8))
    }

    private func record(_ home: HomeModel,
                        remoteID: String = "srv-1",
                        revision: Int = 1) -> HomeSyncRecord {
        HomeSyncRecord(localHomeID: home.home_id,
                       remoteID: remoteID,
                       syncedRevision: revision,
                       syncedFingerprint: HomeFingerprint.of(home),
                       lastSyncedAt: Date(timeIntervalSince1970: 1_000))
    }

    private func state(_ records: HomeSyncRecord...) -> SyncState {
        var state = SyncState.empty
        for record in records { state.remember(record) }
        return state
    }

    private func onlyAction(_ plan: SyncPlan, file: StaticString = #filePath, line: UInt = #line) throws -> SyncAction {
        XCTAssertEqual(plan.actions.count, 1, "expected exactly one action", file: file, line: line)
        return try XCTUnwrap(plan.actions.first, file: file, line: line)
    }

    // MARK: - The four one-sided cases

    func testAHomeThisDeviceHasNeverUploadedIsCreated() throws {
        let plan = SyncReconciler.plan(local: [local(base)], remote: [], state: .empty)
        let action = try onlyAction(plan)
        XCTAssertEqual(action.operation, .createRemote)
        XCTAssertEqual(action.reason, .newLocalHome)
        XCTAssertTrue(plan.staleRecordIDs.isEmpty)
    }

    /// The acceptance criterion this session cannot demonstrate with two real devices, stated
    /// here as the behaviour it reduces to: a home the server has and this device does not is
    /// pulled down. A second device is how that home got there; it is not how the rule works.
    func testAHomeCreatedOnAnotherDeviceIsPulled() throws {
        let theirs = base.renamedCopy(homeID: "home-from-the-other-phone", name: "Beach House")
        let plan = SyncReconciler.plan(local: [], remote: [remote(theirs, id: "srv-9", revision: 4)],
                                       state: .empty)
        let action = try onlyAction(plan)
        XCTAssertEqual(action.localHomeID, "home-from-the-other-phone")
        XCTAssertEqual(action.operation, .pullRemote(remoteID: "srv-9", revision: 4))
        XCTAssertEqual(action.reason, .newRemoteHome)
    }

    /// The server has no delete endpoint, so a record pointing at a home that is gone is a
    /// stale sidecar, not a deletion to honour. Deleting the local copy on that guess would
    /// destroy the user's only remaining copy.
    func testARememberedHomeTheServerNoLongerHasIsRecreatedNotDeleted() throws {
        let plan = SyncReconciler.plan(local: [local(base)], remote: [], state: state(record(base)))
        let action = try onlyAction(plan)
        XCTAssertEqual(action.operation, .createRemote)
        XCTAssertEqual(action.reason, .staleRecordRemoteGone)
        XCTAssertEqual(plan.staleRecordIDs, [base.home_id],
                       "the stale record must be dropped, or the next sync updates a ghost")
    }

    func testAHomeInSyncIsLeftAlone() throws {
        let plan = SyncReconciler.plan(local: [local(base)], remote: [remote(base)],
                                       state: state(record(base)))
        let action = try onlyAction(plan)
        XCTAssertEqual(action.operation, .upToDate)
        XCTAssertEqual(action.reason, .unchanged)
        XCTAssertFalse(plan.hasWork)
    }

    // MARK: - The matched cases

    func testLocalEditsArePushedAsAnUpdate() throws {
        var edited = base!
        edited.floors[0].rooms[0].name = "Front Room"
        let plan = SyncReconciler.plan(local: [local(edited)],
                                       remote: [remote(base, id: "srv-7")],
                                       state: state(record(base, remoteID: "srv-7")))
        let action = try onlyAction(plan)
        XCTAssertEqual(action.operation, .updateRemote(remoteID: "srv-7"))
        XCTAssertEqual(action.reason, .localEdits)
    }

    func testRemoteEditsArePulled() throws {
        var theirs = base!
        theirs.name = "Renamed elsewhere"
        let plan = SyncReconciler.plan(local: [local(base)],
                                       remote: [remote(theirs, id: "srv-7", revision: 5)],
                                       state: state(record(base, remoteID: "srv-7", revision: 4)))
        let action = try onlyAction(plan)
        XCTAssertEqual(action.operation, .pullRemote(remoteID: "srv-7", revision: 5))
        XCTAssertEqual(action.reason, .remoteEdits)
    }

    /// A revision LOWER than the one recorded is a state that cannot be interpreted — the
    /// counter only increases. Keeping the local copy is the direction that cannot lose work.
    func testARevisionBelowTheRecordedOneIsNotTreatedAsRemoteEdits() throws {
        let plan = SyncReconciler.plan(local: [local(base)],
                                       remote: [remote(base, revision: 2)],
                                       state: state(record(base, revision: 9)))
        XCTAssertEqual(try onlyAction(plan).operation, .upToDate)
    }

    // MARK: - Conflicts

    func testAConflictGoesToWhicheverSideWasModifiedLast() throws {
        var mine = base!
        mine.name = "Mine"
        mine.meta.modified = Date(timeIntervalSince1970: 2_000_000)
        var theirs = base!
        theirs.name = "Theirs"
        theirs.meta.modified = Date(timeIntervalSince1970: 1_000_000)

        let plan = SyncReconciler.plan(
            local: [local(mine)],
            remote: [remote(theirs, id: "srv-3", revision: 8)],
            state: state(record(base, remoteID: "srv-3", revision: 2)))
        let action = try onlyAction(plan)
        XCTAssertEqual(action.operation, .updateRemote(remoteID: "srv-3"))
        XCTAssertEqual(action.reason, .conflictLocalWins)
    }

    func testAConflictTheOtherDeviceWonIsPulled() throws {
        var mine = base!
        mine.name = "Mine"
        mine.meta.modified = Date(timeIntervalSince1970: 1_000_000)
        var theirs = base!
        theirs.name = "Theirs"
        theirs.meta.modified = Date(timeIntervalSince1970: 2_000_000)

        let plan = SyncReconciler.plan(
            local: [local(mine)],
            remote: [remote(theirs, id: "srv-3", revision: 8)],
            state: state(record(base, remoteID: "srv-3", revision: 2)))
        let action = try onlyAction(plan)
        XCTAssertEqual(action.operation, .pullRemote(remoteID: "srv-3", revision: 8))
        XCTAssertEqual(action.reason, .conflictRemoteWins)
    }

    /// An exact tie must go to the SERVER on every device. If each device preferred its own
    /// copy, two devices would trade the same home back and forth forever, incrementing the
    /// revision on every exchange and never converging.
    func testAnExactTieGoesToTheServerSoTwoDevicesConverge() throws {
        let stamp = Date(timeIntervalSince1970: 1_500_000)
        var mine = base!
        mine.name = "Mine"
        mine.meta.modified = stamp
        var theirs = base!
        theirs.name = "Theirs"
        theirs.meta.modified = stamp

        let plan = SyncReconciler.plan(
            local: [local(mine)],
            remote: [remote(theirs, id: "srv-3", revision: 8)],
            state: state(record(base, remoteID: "srv-3", revision: 2)))
        XCTAssertEqual(try onlyAction(plan).operation, .pullRemote(remoteID: "srv-3", revision: 8))
    }

    /// Present on both sides with no memory of ever syncing it — a reinstall, or a lost
    /// sidecar. There is no "who is ahead" to read, so it falls to the same tiebreak.
    func testPresentOnBothSidesWithNoRecordIsSettledByModifiedDate() throws {
        var mine = base!
        mine.meta.modified = Date(timeIntervalSince1970: 3_000_000)
        var theirs = base!
        theirs.meta.modified = Date(timeIntervalSince1970: 1_000_000)

        let plan = SyncReconciler.plan(local: [local(mine)],
                                       remote: [remote(theirs, id: "srv-5")],
                                       state: .empty)
        let action = try onlyAction(plan)
        XCTAssertEqual(action.operation, .updateRemote(remoteID: "srv-5"))
        XCTAssertEqual(action.reason, .neverSyncedOnThisDevice)
    }

    // MARK: - Duplicate server records

    /// Two devices that both create the same home before either syncs each POST with no
    /// `home_id`, so the server mints two records carrying the same embedded `home_id`. Every
    /// device must collapse them to the SAME winner or they will fight over which is real.
    func testDuplicateServerRecordsCollapseToTheHighestRevision() throws {
        let plan = SyncReconciler.plan(
            local: [],
            remote: [remote(base, id: "srv-a", revision: 2),
                     remote(base, id: "srv-b", revision: 7)],
            state: .empty)
        XCTAssertEqual(try onlyAction(plan).operation, .pullRemote(remoteID: "srv-b", revision: 7))
    }

    func testDuplicateServerRecordsBreakTiesDeterministically() throws {
        let stamp = Date(timeIntervalSince1970: 1_234)
        let forwards = SyncReconciler.plan(
            local: [],
            remote: [remote(base, id: "srv-b", revision: 3, updatedAt: stamp),
                     remote(base, id: "srv-a", revision: 3, updatedAt: stamp)],
            state: .empty)
        let backwards = SyncReconciler.plan(
            local: [],
            remote: [remote(base, id: "srv-a", revision: 3, updatedAt: stamp),
                     remote(base, id: "srv-b", revision: 3, updatedAt: stamp)],
            state: .empty)
        XCTAssertEqual(forwards, backwards, "the winner must not depend on response ordering")
        XCTAssertEqual(try onlyAction(forwards).operation,
                       .pullRemote(remoteID: "srv-a", revision: 3))
    }

    // MARK: - Whole-library properties

    func testEveryHomeOnEitherSideIsAccountedFor() throws {
        let mine = base.renamedCopy(homeID: "home-mine")
        let shared = base.renamedCopy(homeID: "home-shared")
        let theirs = base.renamedCopy(homeID: "home-theirs")

        let plan = SyncReconciler.plan(
            local: [local(mine), local(shared)],
            remote: [remote(shared, id: "srv-shared"), remote(theirs, id: "srv-theirs")],
            state: state(record(shared, remoteID: "srv-shared")))

        XCTAssertEqual(plan.actions.map(\.localHomeID),
                       ["home-mine", "home-shared", "home-theirs"],
                       "actions must be ordered by home id so plans are comparable")
        XCTAssertEqual(plan.actions[0].operation, .createRemote)
        XCTAssertEqual(plan.actions[1].operation, .upToDate)
        XCTAssertEqual(plan.actions[2].operation, .pullRemote(remoteID: "srv-theirs", revision: 1))
        XCTAssertTrue(plan.hasWork)
    }

    func testPlanningIsDeterministic() throws {
        let a = base.renamedCopy(homeID: "home-a")
        let b = base.renamedCopy(homeID: "home-b")
        let first = SyncReconciler.plan(local: [local(a), local(b)],
                                        remote: [remote(b, id: "srv-b")], state: .empty)
        let second = SyncReconciler.plan(local: [local(b), local(a)],
                                         remote: [remote(b, id: "srv-b")], state: .empty)
        XCTAssertEqual(first, second)
    }

    func testAnEmptyDeviceAndAnEmptyServerPlanNothing() {
        let plan = SyncReconciler.plan(local: [], remote: [], state: .empty)
        XCTAssertTrue(plan.actions.isEmpty)
        XCTAssertFalse(plan.hasWork)
    }
}
