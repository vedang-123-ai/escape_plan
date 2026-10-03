//  SyncDeletionTests.swift — S11.7: the server copy of a deleted home actually goes away,
//  and the sidecar forgets an account that no longer exists.
//
//  Until S11.7 the backend had no delete endpoint at all. A home deleted on this device stayed
//  in the account forever and the reconciler could only refuse to download it again, on the
//  strength of a tombstone — so "I deleted that home" was true on one phone and false in the
//  cloud. These pin both halves of closing that: the DELETE goes out, and the tombstone stays
//  behind to protect a second device that has not synced yet.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class SyncDeletionTests: XCTestCase {

    private var backend: FakeCloudBackend!
    private var repository: InMemoryHomeRepository!
    private var stateStore: InMemorySyncStateStore!
    private var token: AccessToken?
    private var base: HomeModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        AuthStubURLProtocol.reset()
        backend = FakeCloudBackend()
        backend.install()
        repository = InMemoryHomeRepository()
        stateStore = InMemorySyncStateStore()
        token = makeTestToken()
        base = try Fixtures.load("bungalow")
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        backend = nil; repository = nil; stateStore = nil
        super.tearDown()
    }

    private func makeManager() -> SyncManager {
        SyncManager(
            client: CloudHomesClient(baseURL: URL(string: "https://backend.example.com")!,
                                     session: AuthStubURLProtocol.makeSession()),
            repository: repository,
            stateStore: stateStore,
            tokenProvider: { [weak self] in self?.token },
            now: { Date(timeIntervalSince1970: 1_800_000) })
    }

    private func outcome(_ status: SyncManager.Status,
                         file: StaticString = #filePath, line: UInt = #line) throws -> SyncOutcome {
        guard case .synced(_, let outcome) = status else {
            XCTFail("expected a completed sync, got \(status)", file: file, line: line)
            throw XCTSkip("not a completed sync")
        }
        return outcome
    }

    /// Upload a home, then delete it on this device, leaving the sidecar as the app would.
    private func syncThenDeleteLocally() async throws {
        repository = InMemoryHomeRepository([base])
        await makeManager().sync()
        XCTAssertNotNil(backend.record(withLocalHomeID: base.home_id), "setup failed")

        var state = stateStore.load()
        state.markDeleted(localHomeID: base.home_id, at: Date())
        try stateStore.save(state)
        repository = InMemoryHomeRepository()
    }

    // MARK: - The server copy goes

    func testDeletingAHomeHereRemovesTheServerCopyOnTheNextSync() async throws {
        try await syncThenDeleteLocally()
        let manager = makeManager()

        await manager.sync()

        XCTAssertNil(backend.record(withLocalHomeID: base.home_id),
                     "the account still holds a home the user deleted")
        XCTAssertEqual(try outcome(manager.status).deletedRemotely, 1)
        XCTAssertEqual(try outcome(manager.status).skipped, 1,
                       "it is still a skip — the decision not to download is unchanged")
    }

    /// The home must not come back on the way out. A delete that also re-downloaded would be
    /// worse than no delete at all.
    func testTheDeletedHomeIsNotWrittenBackToTheDevice() async throws {
        try await syncThenDeleteLocally()
        let manager = makeManager()

        await manager.sync()

        XCTAssertTrue(repository.writes.isEmpty)
    }

    /// Self-limiting by design: once the record is gone, `GET /homes` does not mention it, so
    /// the reconciler produces no action and nothing is retried on every launch forever.
    func testASecondSyncSendsNoFurtherDelete() async throws {
        try await syncThenDeleteLocally()
        await makeManager().sync()
        let after = backend.requestCount

        let manager = makeManager()
        await manager.sync()

        XCTAssertEqual(try outcome(manager.status).deletedRemotely, 0)
        XCTAssertEqual(backend.requestCount, after + 1, "only the GET; nothing to delete")
    }

    /// The tombstone STAYS. It is what suppresses the home on a second device that still
    /// holds its own copy and has not synced since.
    func testTheTombstoneSurvivesTheRemoteDeletion() async throws {
        try await syncThenDeleteLocally()

        await makeManager().sync()

        XCTAssertTrue(stateStore.load().isDeletedLocally(base.home_id),
                      "dropping the tombstone lets another device re-upload it")
    }

    /// A deletion is not a licence to touch another account's data. Alice deleting her copy
    /// must leave Bob's server record alone.
    func testOneUsersDeletionLeavesAnotherUsersServerCopyAlone() async throws {
        token = makeTestToken(subject: "alice")
        try await syncThenDeleteLocally()

        var bobsVersion = base!
        bobsVersion.name = "Bob's Bungalow"
        backend.seed(bobsVersion, revision: 2, userID: "bob")

        await makeManager().sync()

        XCTAssertEqual(backend.storedHomes.filter { $0.userID == "bob" }.count, 1,
                       "Alice's deletion reached into Bob's account")
    }

    /// A server that refuses the delete must not take the rest of the sync down. The home is
    /// still not downloaded — the tombstone is doing its original job — and the run completes.
    func testAFailedDeleteIsAPerHomeFailureNotAWholeRunFailure() async throws {
        try await syncThenDeleteLocally()
        // The GET succeeds; the DELETE is refused.
        backend.failNextDelete = 500
        let manager = makeManager()

        await manager.sync()

        let result = try outcome(manager.status)
        XCTAssertEqual(result.deletedRemotely, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(repository.writes.isEmpty, "and it still was not downloaded")
    }

    /// ─── THE ONE THAT MUST NOT REGRESS ───────────────────────────────────────────────────
    ///
    /// An OWNERLESS tombstone must never delete anything from the server.
    ///
    /// `isDeletedLocally` matches a tombstone whose `ownerUserID` is nil for ANY signed-in
    /// account, by design — before S11.7 that meant "do not download this", which is harmless.
    /// S11.7 escalated the same branch to `DELETE /homes/{id}`, which is not.
    ///
    /// The path is real, not theoretical, and it is built out of this repo's own facts: the
    /// starter homes keep FIXED `home_id`s across installs (`FixtureSeeder`). Fresh install,
    /// user deletes the seeded Bungalow BEFORE signing in (so the tombstone has no owner),
    /// then signs in — and their other device's real Bungalow is erased from the account.
    func testAnOwnerlessTombstoneNeverDeletesTheAccountsServerCopy() async throws {
        // Deleted before anyone signed in: no owner on the tombstone.
        var state = SyncState.empty
        state.markDeleted(localHomeID: base.home_id, at: Date())
        try stateStore.save(state)
        repository = InMemoryHomeRepository()

        // The account already holds a real copy, synced from another device.
        var fromOtherDevice = base!
        fromOtherDevice.name = "The one I actually want"
        backend.seed(fromOtherDevice, revision: 4, userID: "u-1")

        let manager = makeManager()
        await manager.sync()

        XCTAssertNotNil(backend.record(withLocalHomeID: base.home_id),
                        "an ownerless tombstone erased a home from the user's account")
        XCTAssertEqual(try outcome(manager.status).deletedRemotely, 0)
        XCTAssertEqual(try outcome(manager.status).skipped, 1,
                       "it must still be the pure skip it was before S11.7")
    }

    /// The server may hold DUPLICATE records for one `home_id` — two devices racing to create
    /// it, which is why `SyncReconciler.collapseDuplicates` exists. Deleting one per sync
    /// leaves the home in the account until the user happens to sync again.
    func testEveryDuplicateServerRecordOfADeletedHomeGoes() async throws {
        try await syncThenDeleteLocally()
        // A second record for the same home, as a racing device would have minted.
        backend.seed(base, revision: 1, userID: "u-1")
        XCTAssertEqual(backend.storedHomes.filter { $0.home.home_id == base.home_id }.count, 2)

        await makeManager().sync()

        XCTAssertTrue(backend.storedHomes.filter { $0.home.home_id == base.home_id }.isEmpty,
                      "a duplicate server record outlived the deletion")
    }

    // MARK: - What the delete confirmation promises (S11.21)
    //
    // The home list's delete confirmation reads `HomeDeletionReach` to say whether the account's
    // copy goes too. Each test states the answer, deletes the way the app does, then syncs against
    // the fake backend and checks the promise was kept. Never the live server.

    private var deleteRequests: [URLRequest] {
        AuthStubURLProtocol.capturedRequests.filter { $0.httpMethod == "DELETE" }
    }

    /// Deletes `base` on this device exactly as `HomeDocumentSyncRepository` does: tombstone,
    /// then the home is gone from disk.
    private func deleteLocally() throws {
        var state = stateStore.load()
        state.markDeleted(localHomeID: base.home_id, at: Date())
        try stateStore.save(state)
        repository = InMemoryHomeRepository()
    }

    /// A starter home deleted before anyone signed in. `base` is the Bungalow fixture, whose fixed
    /// `home_id` every install shares, and the account already holds a real Bungalow from another
    /// device: "from this iPhone" must be the whole truth.
    func testDeletingAStarterHomeBeforeSigningInReachesOnlyThisDevice() async throws {
        XCTAssertEqual(HomeDeletionReach.of(base.home_id, in: stateStore.load(), signedInUserID: nil),
                       .thisDeviceOnly)
        try deleteLocally()
        var fromOtherDevice = base!
        fromOtherDevice.name = "My real Bungalow"
        backend.seed(fromOtherDevice, revision: 3, userID: "u-1")

        // The user signs in afterwards.
        await makeManager().sync()

        XCTAssertTrue(deleteRequests.isEmpty, "a delete made signed out reached the account")
        XCTAssertNotNil(backend.record(withLocalHomeID: base.home_id))
    }

    /// Signed in, and the home is this account's: the confirmation says the account copy goes,
    /// and the next sync sends the tombstone's `DELETE /homes/{id}`.
    func testDeletingWhileSignedInReachesTheAccount() async throws {
        repository = InMemoryHomeRepository([base])
        await makeManager().sync()
        let recordID = try XCTUnwrap(backend.record(withLocalHomeID: base.home_id)?.id, "setup failed")

        XCTAssertEqual(HomeDeletionReach.of(base.home_id, in: stateStore.load(), signedInUserID: "u-1"),
                       .deviceAndAccount)
        try deleteLocally()
        XCTAssertEqual(stateStore.load().deletions[base.home_id]?.ownerUserID, "u-1",
                       "the tombstone must carry the owner, or sync will never send the delete")
        await makeManager().sync()

        XCTAssertEqual(deleteRequests.map { $0.url?.lastPathComponent }, [recordID])
        XCTAssertNil(backend.record(withLocalHomeID: base.home_id))
    }

    /// Backed up, but that account is signed out now. Nothing leaves while signed out; the
    /// account's copy goes when it signs back in here, as the confirmation says.
    func testDeletingAHomeWhoseAccountIsSignedOutReachesItOnSignIn() async throws {
        repository = InMemoryHomeRepository([base])
        await makeManager().sync()
        token = nil

        XCTAssertEqual(HomeDeletionReach.of(base.home_id, in: stateStore.load(), signedInUserID: nil),
                       .deviceNowAccountLater)
        try deleteLocally()
        await makeManager().sync()
        XCTAssertTrue(deleteRequests.isEmpty)
        XCTAssertNotNil(backend.record(withLocalHomeID: base.home_id))

        token = makeTestToken()
        await makeManager().sync()
        XCTAssertNil(backend.record(withLocalHomeID: base.home_id))
    }

    /// Another account is signed in. The home's own account still loses its copy only when it
    /// signs in; the account signed in now is never touched.
    func testAHomeOwnedByAnotherAccountIsNotTheSignedInAccountsToDelete() async throws {
        token = makeTestToken(subject: "alice")
        repository = InMemoryHomeRepository([base])
        await makeManager().sync()

        XCTAssertEqual(HomeDeletionReach.of(base.home_id, in: stateStore.load(), signedInUserID: "bob"),
                       .deviceNowAccountLater)
        try deleteLocally()
        token = makeTestToken(subject: "bob")
        await makeManager().sync()

        XCTAssertTrue(deleteRequests.isEmpty, "Bob's sync deleted Alice's home")
        XCTAssertNotNil(backend.record(withLocalHomeID: base.home_id))
    }

    // MARK: - Forgetting a deleted account

    func testForgettingAnAccountClearsItsRecordsAndOwnership() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        let manager = makeManager()
        await manager.sync()
        XCTAssertFalse(stateStore.load().records.isEmpty, "setup failed")

        manager.forgetAccount("alice")

        let state = stateStore.load()
        XCTAssertTrue(state.records.isEmpty)
        XCTAssertNil(state.userID)
        XCTAssertEqual(state.ownership(of: base.home_id), .unclaimed,
                       "a home claimed by a deleted account can never be backed up again")
        XCTAssertEqual(manager.status, .signedOut)
    }

    /// The whole reason `forgetAccount` clears ownership rather than just the records: the
    /// next person to sign in on this phone must be able to back the homes up.
    func testTheNextAccountCanAdoptHomesTheDeletedAccountOwned() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        let first = makeManager()
        await first.sync()
        first.forgetAccount("alice")

        token = makeTestToken(subject: "bob")
        let second = makeManager()
        await second.sync()

        XCTAssertEqual(try outcome(second.status).pushed, 1)
        XCTAssertEqual(backend.storedHomes.filter { $0.userID == "bob" }.count, 1)
    }

    /// A sync already in flight must not write its pre-deletion sidecar back over the wipe.
    ///
    /// `sync()` holds its own `state` across every `await` and persists after each action, so
    /// a deletion confirmed during a launch sync — up to 90s of it against a cold Render
    /// instance — would otherwise restore exactly the dangling ownership claims
    /// `forgetAccount` exists to remove. Found in review, 2026-09-24.
    func testASyncInFlightCannotUndoTheAccountDeletion() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        let manager = makeManager()

        // Delete the account while the sync is suspended on its first request, then let the
        // sync run to completion and write its own copy of the sidecar.
        async let syncing: Void = manager.sync()
        manager.forgetAccount("alice")
        await syncing

        let state = stateStore.load()
        XCTAssertNil(state.homeOwners[base.home_id],
                     "the in-flight sync restored a deleted account's ownership claim")
        XCTAssertTrue(state.records.isEmpty,
                      "the in-flight sync restored a deleted account's sync records")
        XCTAssertEqual(state.ownership(of: base.home_id), .unclaimed)
    }

    /// And the guard must not outlive the account it was for: a different account signing in
    /// afterwards has to be able to record its own homes.
    func testTheNextAccountsRecordsAreNotForgotten() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        let first = makeManager()
        await first.sync()
        first.forgetAccount("alice")

        token = makeTestToken(subject: "bob")
        let second = makeManager()
        await second.sync()

        let state = stateStore.load()
        XCTAssertFalse(state.records.isEmpty, "Bob's sync recorded nothing")
        XCTAssertEqual(state.ownership(of: base.home_id), .mine)
    }

    /// Forgetting my account must not rewrite what this device knows about somebody else's.
    func testForgettingAnAccountLeavesAnotherAccountsClaimsAlone() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        let manager = makeManager()
        await manager.sync()

        manager.forgetAccount("bob")

        let state = stateStore.load()
        XCTAssertEqual(state.ownership(of: base.home_id), .mine,
                       "Alice's claim was collateral damage")
        XCTAssertFalse(state.records.isEmpty)
    }

    /// The promise `AccountPrivacy.deletionSummary` makes on screen: the homes on this iPhone
    /// are not touched. The sidecar is the only thing `forgetAccount` may write.
    func testForgettingAnAccountNeverTouchesAHomeDocument() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        let manager = makeManager()
        await manager.sync()
        let writesBefore = repository.writes.count

        manager.forgetAccount("alice")

        XCTAssertEqual(repository.writes.count, writesBefore)
        XCTAssertEqual(try repository.loadAllHomes().count, 1,
                       "deleting the account erased a home from this device")
    }
}
