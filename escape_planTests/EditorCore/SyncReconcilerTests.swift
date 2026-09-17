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
        XCTAssertTrue(plan.staleRecordHomeIDs.isEmpty)
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
        XCTAssertEqual(plan.staleRecordHomeIDs, [base.home_id],
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

// MARK: - Regressions found by review, 2026-09-16

/// Each test below pins one defect the S8.4 review found. They are separated from the decision
/// table above because each is a specific sequence of events that destroyed or resurrected a
/// user's home, not a cell in a matrix.
final class SyncReconcilerRegressionTests: XCTestCase {

    private var base: HomeModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        base = try Fixtures.load("bungalow")
    }

    private func local(_ home: HomeModel) -> LocalHome { LocalHome(model: home) }

    private func remote(_ home: HomeModel, id: String = "srv-1", revision: Int = 1) -> StoredHome {
        let homeJSON = String(decoding: try! HomeModel.encoder().encode(home), as: UTF8.self)
        let json = """
        {"id":"\(id)","user_id":"u-1","home":\(homeJSON),"revision":\(revision),\
        "created_at":"2026-09-16T05:00:00Z","updated_at":"2026-09-16T05:00:00Z"}
        """
        return try! HomeModel.decoder.decode(StoredHome.self, from: Data(json.utf8))
    }

    private func record(_ home: HomeModel, remoteID: String = "srv-1", revision: Int = 1) -> HomeSyncRecord {
        HomeSyncRecord(localHomeID: home.home_id, remoteID: remoteID, syncedRevision: revision,
                       syncedFingerprint: HomeFingerprint.of(home),
                       lastSyncedAt: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: - The factory starter home must never beat a month of the user's edits

    /// The sequence: device A seeds the starter Bungalow, the user edits it for a month, syncs.
    /// Device B (or A after a reinstall) seeds the SAME `home_id` from the same bundled fixture.
    /// Both sides now hold `5d3f…abc1` and B has no sidecar, so the tiebreak decides — and the
    /// bundled fixture must lose, or a pristine demo home is pushed over the user's real one
    /// and then pulled down onto device A too.
    ///
    /// The fix that makes this true is in `FixtureSeeder.seedStarterHomes`, which now seeds
    /// `now: model.meta.modified` instead of stamping the install time. This test pins the
    /// consequence; `HomeDocumentSyncRepositoryTests` pins the seeding itself.
    func testAFreshlySeededStarterHomeLosesToTheEditedServerCopy() throws {
        // The fixture, exactly as bundled: meta.modified is 2026-07-10.
        let pristine = base!
        var edited = base!
        edited.floors[0].rooms[0].name = "Front Room"
        edited.meta.modified = Date(timeIntervalSince1970: 1_800_000_000)  // long after

        let plan = SyncReconciler.plan(local: [local(pristine)],
                                       remote: [remote(edited, id: "srv-9", revision: 7)],
                                       state: .empty)
        XCTAssertEqual(plan.actions.first?.operation, .pullRemote(remoteID: "srv-9", revision: 7),
                       "the bundled fixture must never overwrite the user's edited home")
    }

    /// The same pair, with the install-time stamp the seeder USED to write. This is the
    /// failure as it existed — kept as an executable statement of why the seeder changed,
    /// so nobody "simplifies" `now: model.meta.modified` back out again.
    func testAStarterHomeStampedAtInstallTimeWouldHaveWonAndThatIsTheBug() throws {
        var stampedAtInstall = base!
        stampedAtInstall.meta.modified = Date(timeIntervalSince1970: 1_900_000_000)
        var edited = base!
        edited.floors[0].rooms[0].name = "Front Room"
        edited.meta.modified = Date(timeIntervalSince1970: 1_800_000_000)

        let plan = SyncReconciler.plan(local: [local(stampedAtInstall)],
                                       remote: [remote(edited, id: "srv-9", revision: 7)],
                                       state: .empty)
        XCTAssertEqual(plan.actions.first?.operation, .updateRemote(remoteID: "srv-9"),
                       "documents the destructive direction — the seeder must not create this "
                     + "situation in the first place")
    }

    // MARK: - A deleted home must stay deleted

    func testAHomeDeletedOnThisDeviceIsNotDownloadedAgain() throws {
        var state = SyncState.empty
        state.markDeleted(localHomeID: base.home_id, at: Date())

        let plan = SyncReconciler.plan(local: [], remote: [remote(base)], state: state)
        XCTAssertEqual(plan.actions.first?.operation, .skip)
        XCTAssertEqual(plan.actions.first?.reason, .deletedOnThisDevice)
        XCTAssertFalse(plan.hasWork, "a skipped home is not work — the badge must not claim it")
    }

    /// Deleting must drop the sync record too, or the next sync would try to UPDATE a record
    /// for a home that is no longer on disk.
    func testMarkingAHomeDeletedAlsoDropsItsSyncRecord() {
        var state = SyncState.empty
        state.remember(record(base))
        XCTAssertNotNil(state.record(for: base.home_id))

        state.markDeleted(localHomeID: base.home_id, at: Date())
        XCTAssertNil(state.record(for: base.home_id))
        XCTAssertTrue(state.isDeletedLocally(base.home_id))
    }

    /// A tombstoned home that is on disk again (re-imported from a shared file) must sync
    /// normally, and the stale tombstone must be cleared — otherwise it is suppressed forever.
    func testAReimportedHomeClearsItsOwnTombstone() throws {
        var state = SyncState.empty
        state.markDeleted(localHomeID: base.home_id, at: Date())

        let plan = SyncReconciler.plan(local: [local(base)], remote: [], state: state)
        XCTAssertEqual(plan.actions.first?.operation, .createRemote)
        XCTAssertEqual(plan.staleTombstoneHomeIDs, [base.home_id])
    }

    /// Re-syncing a home clears its tombstone, so the two pieces of state cannot disagree.
    func testRememberingAHomeClearsItsTombstone() {
        var state = SyncState.empty
        state.markDeleted(localHomeID: base.home_id, at: Date())
        state.remember(record(base))
        XCTAssertFalse(state.isDeletedLocally(base.home_id))
    }

    // MARK: - The sidecar belongs to one account

    /// User A syncs, signs out, user B signs in on the same device. B must not inherit A's
    /// record ids — they point at server records in A's account, so acting on one either
    /// uploads into the wrong account or reports a home B has never seen as already synced.
    func testASidecarFromAnotherAccountIsDiscarded() {
        var aliceState = SyncState(userID: "alice", records: [:])
        aliceState.remember(record(base, remoteID: "srv-alice", revision: 5))

        let forBob = aliceState.scoped(to: "bob")
        XCTAssertNil(forBob.record(for: base.home_id))
        XCTAssertEqual(forBob.userID, "bob")
    }

    func testTheSameAccountKeepsItsRecords() {
        var state = SyncState(userID: "alice")
        state.remember(record(base, remoteID: "srv-alice", revision: 5))
        XCTAssertEqual(state.scoped(to: "alice").record(for: base.home_id)?.remoteID, "srv-alice")
    }

    /// An unknown id on either side must not be treated as a match. A token whose `sub` claim
    /// could not be parsed is "we don't know who this is", not "the same user as last time".
    func testAnUnknownAccountDoesNotMatchAKnownOne() {
        var state = SyncState(userID: "alice")
        state.remember(record(base))
        XCTAssertNil(state.scoped(to: nil).record(for: base.home_id))
        XCTAssertNil(SyncState(userID: nil, records: [base.home_id: record(base)])
            .scoped(to: "alice").record(for: base.home_id))
    }

    // MARK: - A conflict must be visible to the caller

    func testAConflictThatOverwritesLocalEditsSaysSo() throws {
        var mine = base!
        mine.name = "Mine"
        mine.meta.modified = Date(timeIntervalSince1970: 1_000_000)
        var theirs = base!
        theirs.name = "Theirs"
        theirs.meta.modified = Date(timeIntervalSince1970: 2_000_000)

        var state = SyncState.empty
        state.remember(record(base, remoteID: "srv-3", revision: 2))

        let action = try XCTUnwrap(SyncReconciler.plan(
            local: [local(mine)], remote: [remote(theirs, id: "srv-3", revision: 8)],
            state: state).actions.first)
        XCTAssertTrue(action.overwritesLocalEdits,
                      "the caller must know to keep a copy before this lands")
    }

    /// An ordinary remote-only update is NOT a conflict — nothing local is at risk, and
    /// treating it as one would litter the library with "(this device)" copies.
    func testAnOrdinaryPullDoesNotClaimToOverwriteLocalEdits() throws {
        var theirs = base!
        theirs.name = "Renamed elsewhere"
        var state = SyncState.empty
        state.remember(record(base, remoteID: "srv-3", revision: 4))

        let action = try XCTUnwrap(SyncReconciler.plan(
            local: [local(base)], remote: [remote(theirs, id: "srv-3", revision: 5)],
            state: state).actions.first)
        XCTAssertEqual(action.reason, .remoteEdits)
        XCTAssertFalse(action.overwritesLocalEdits)
    }

    func testANewRemoteHomeDoesNotClaimToOverwriteAnything() throws {
        let action = try XCTUnwrap(SyncReconciler.plan(
            local: [], remote: [remote(base)], state: .empty).actions.first)
        XCTAssertFalse(action.overwritesLocalEdits)
    }
}
