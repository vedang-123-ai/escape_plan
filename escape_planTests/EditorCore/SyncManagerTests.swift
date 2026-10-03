//  SyncManagerTests.swift — a whole sync, end to end, against a fake /homes backend.
//
//  These drive the REAL `CloudHomesClient` over `AuthStubURLProtocol` into `FakeCloudBackend`
//  (SyncTestSupport.swift), so a mistake in the URL path, the Authorization header, the
//  request body or the response decoding fails here rather than surviving until someone has a
//  device. The only things stubbed are the transport and the home repository.
//
//  The acceptance criterion S8.4 cannot demonstrate on this machine — "pulls down homes
//  created on other devices" — needs two phones. What it REDUCES to is tested here: a home
//  present on the server and absent from this device is written to this device, under the same
//  `home_id`, with its `meta.modified` intact. See BLOCKERS.md §2.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class SyncManagerTests: XCTestCase {

    private var backend: FakeCloudBackend!
    private var repository: InMemoryHomeRepository!
    private var stateStore: InMemorySyncStateStore!
    private var token: AccessToken?
    private var sessionExpiredCount = 0
    private var base: HomeModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        AuthStubURLProtocol.reset()
        backend = FakeCloudBackend()
        backend.install()
        repository = InMemoryHomeRepository()
        stateStore = InMemorySyncStateStore()
        token = makeTestToken()
        sessionExpiredCount = 0
        base = try Fixtures.load("bungalow")
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        backend = nil
        repository = nil
        stateStore = nil
        super.tearDown()
    }

    private func makeManager(now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_800_000) })
        -> SyncManager {
        SyncManager(
            client: CloudHomesClient(baseURL: URL(string: "https://backend.example.com")!,
                                     session: AuthStubURLProtocol.makeSession()),
            repository: repository,
            stateStore: stateStore,
            tokenProvider: { [weak self] in self?.token },
            onSessionExpired: { [weak self] in self?.sessionExpiredCount += 1 },
            now: now)
    }

    private func outcome(_ status: SyncManager.Status,
                         file: StaticString = #filePath, line: UInt = #line) throws -> SyncOutcome {
        guard case .synced(_, let outcome) = status else {
            XCTFail("expected a completed sync, got \(status)", file: file, line: line)
            throw XCTSkip("not a completed sync")
        }
        return outcome
    }

    // MARK: - Acceptance criterion 1: local changes reach the backend

    func testAHomeOnThisDeviceIsPushedToTheBackend() async throws {
        repository = InMemoryHomeRepository([base])
        let manager = makeManager()

        await manager.sync()

        let stored = try XCTUnwrap(backend.record(withLocalHomeID: base.home_id))
        XCTAssertEqual(stored.home, base, "the backend must hold the home the device holds")
        XCTAssertEqual(stored.revision, 1)
        XCTAssertEqual(try outcome(manager.status).pushed, 1)
        XCTAssertTrue(try outcome(manager.status).isClean)
    }

    func testEditingAHomeAndSyncingAgainUpdatesTheSameRecord() async throws {
        repository = InMemoryHomeRepository([base])
        let manager = makeManager()
        await manager.sync()
        let firstID = try XCTUnwrap(backend.record(withLocalHomeID: base.home_id)).id

        var edited = base!
        edited.floors[0].rooms[0].name = "Front Room"
        edited.meta.modified = base.meta.modified.addingTimeInterval(60)
        repository = InMemoryHomeRepository([edited])
        let second = makeManager()
        await second.sync()

        XCTAssertEqual(backend.storedHomes.count, 1, "an edit must not mint a second record")
        let stored = try XCTUnwrap(backend.record(withLocalHomeID: base.home_id))
        XCTAssertEqual(stored.id, firstID)
        XCTAssertEqual(stored.revision, 2, "the server increments its own revision")
        XCTAssertEqual(stored.home.floors[0].rooms[0].name, "Front Room")
    }

    /// The whole reason the dirty check is taken over the DECODED model: an unchanged home
    /// must not be re-uploaded just because the server's JSON has explicit nulls in it.
    func testSyncingTwiceWithNoEditsUploadsNothingTheSecondTime() async throws {
        repository = InMemoryHomeRepository([base])
        await makeManager().sync()
        let afterFirst = backend.requestCount

        let second = makeManager()
        await second.sync()

        XCTAssertEqual(try outcome(second.status).pushed, 0)
        XCTAssertEqual(try outcome(second.status).unchanged, 1)
        XCTAssertEqual(backend.requestCount, afterFirst + 1, "only the GET should have happened")
        XCTAssertEqual(try XCTUnwrap(backend.record(withLocalHomeID: base.home_id)).revision, 1)
    }

    // MARK: - Acceptance criterion 2: homes from another device

    func testAHomeCreatedOnAnotherDeviceIsWrittenToThisOne() async throws {
        let theirs = base.renamedCopy(homeID: "home-from-the-other-phone", name: "Beach House")
        backend.seed(theirs, revision: 3)
        let manager = makeManager()

        await manager.sync()

        XCTAssertEqual(repository.writes.count, 1)
        XCTAssertEqual(repository.writes[0], theirs,
                       "the pulled home must land VERBATIM, meta.modified included")
        XCTAssertEqual(try outcome(manager.status).pulled, 1)
    }

    /// The ping-pong guard. If a pulled home were re-stamped with the current time on the way
    /// to disk it would look newer than the server's copy, get pushed straight back, and the
    /// two devices would trade the same home forever without a single edit between them.
    func testAPulledHomeIsNotImmediatelyPushedBack() async throws {
        let theirs = base.renamedCopy(homeID: "home-theirs", name: "Beach House")
        let recordID = backend.seed(theirs, revision: 3)

        await makeManager().sync()
        let revisionAfterPull = try XCTUnwrap(backend.storedHomes.first { $0.id == recordID }).revision

        // Second sync, same device, nothing touched in between.
        let second = makeManager()
        await second.sync()

        XCTAssertEqual(try outcome(second.status).pushed, 0)
        XCTAssertEqual(try outcome(second.status).unchanged, 1)
        XCTAssertEqual(try XCTUnwrap(backend.storedHomes.first { $0.id == recordID }).revision,
                       revisionAfterPull,
                       "the revision must not climb when nobody edited anything")
    }

    func testAnEditOnTheOtherDeviceArrivesOnTheNextSync() async throws {
        repository = InMemoryHomeRepository([base])
        await makeManager().sync()
        let recordID = try XCTUnwrap(backend.record(withLocalHomeID: base.home_id)).id

        var theirEdit = base!
        theirEdit.name = "Renamed on the other phone"
        backend.mutate(recordID: recordID, to: theirEdit)

        let second = makeManager()
        await second.sync()

        XCTAssertEqual(try outcome(second.status).pulled, 1)
        XCTAssertEqual(repository.writes.last?.name, "Renamed on the other phone")
    }

    func testAMixedLibraryPushesAndPullsInOneRun() async throws {
        let mine = base.renamedCopy(homeID: "home-mine", name: "Mine")
        let theirs = base.renamedCopy(homeID: "home-theirs", name: "Theirs")
        repository = InMemoryHomeRepository([mine])
        backend.seed(theirs)
        let manager = makeManager()

        await manager.sync()

        let result = try outcome(manager.status)
        XCTAssertEqual(result.pushed, 1)
        XCTAssertEqual(result.pulled, 1)
        XCTAssertNotNil(backend.record(withLocalHomeID: "home-mine"))
        XCTAssertEqual(repository.writes.map(\.home_id), ["home-theirs"])
    }

    // MARK: - Acceptance criterion 3: the status the UI renders

    func testStatusIsSignedOutWithNoToken() async {
        token = nil
        let manager = makeManager()
        XCTAssertEqual(manager.status, .signedOut)

        await manager.syncIfSignedIn()
        XCTAssertEqual(manager.status, .signedOut)
        XCTAssertEqual(backend.requestCount, 0, "a signed-out user must not hit the network")
    }

    func testStatusIsIdleBeforeTheFirstSyncOfASignedInLaunch() {
        XCTAssertEqual(makeManager().status, .idle)
    }

    func testACompletedSyncStampsTheTimeItFinished() async throws {
        repository = InMemoryHomeRepository([base])
        let manager = makeManager(now: { Date(timeIntervalSince1970: 1_800_000) })
        await manager.sync()

        guard case .synced(let at, _) = manager.status else { return XCTFail("not synced") }
        XCTAssertEqual(at, Date(timeIntervalSince1970: 1_800_000))
    }

    func testAFailedListLeavesAFailedStatusAndChangesNothing() async throws {
        repository = InMemoryHomeRepository([base])
        backend.failEveryRequest = 500
        let manager = makeManager()

        await manager.sync()

        guard case .failed(let failure) = manager.status else { return XCTFail("expected failure") }
        XCTAssertEqual(failure.kind, .server(statusCode: 500))
        XCTAssertTrue(repository.writes.isEmpty)
        XCTAssertTrue(backend.storedHomes.isEmpty)
    }

    func testAnUnreadableLibraryFailsBeforeAnythingIsSent() async {
        struct Boom: Error {}
        repository = InMemoryHomeRepository([base])
        repository.loadError = Boom()
        let manager = makeManager()

        await manager.sync()

        guard case .failed = manager.status else { return XCTFail("expected failure") }
        XCTAssertEqual(backend.requestCount, 0)
    }

    // MARK: - Robustness

    /// One home the server rejects must not take the rest of the library down with it.
    func testOneRejectedHomeDoesNotStopTheOthers() async throws {
        let first = base.renamedCopy(homeID: "home-a", name: "A")
        let second = base.renamedCopy(homeID: "home-b", name: "B")
        repository = InMemoryHomeRepository([first, second])
        let manager = makeManager()

        // The GET succeeds; the first POST is forced to 422.
        backend.failNextPost = 422
        await manager.sync()

        let result = try outcome(manager.status)
        XCTAssertEqual(result.pushed, 1, "the second home must still go up")
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.localHomeID, "home-a")
        XCTAssertEqual(result.failures.first?.failure.kind, .rejectedByServer)
        XCTAssertFalse(result.isClean)
    }

    /// A 401 mid-run invalidates every remaining action, so the run stops rather than
    /// collecting the same failure once per home — and the app is told to re-authenticate.
    func testADeadSessionStopsTheRunAndAsksForReauthentication() async throws {
        repository = InMemoryHomeRepository([base.renamedCopy(homeID: "home-a"),
                                             base.renamedCopy(homeID: "home-b")])
        let manager = makeManager()
        backend.failNextPost = 401
        await manager.sync()

        guard case .failed(let failure) = manager.status else { return XCTFail("expected failure") }
        XCTAssertEqual(failure.kind, .sessionExpired)
        XCTAssertTrue(failure.requiresReauthentication)
        XCTAssertEqual(sessionExpiredCount, 1)
        XCTAssertTrue(backend.storedHomes.isEmpty, "the run must stop at the first 401")
    }

    /// The remembered record points at a server copy that is gone. Re-create rather than
    /// showing the user the same error on every sync forever.
    func testAnUpdateToAVanishedRecordFallsBackToCreating() async throws {
        repository = InMemoryHomeRepository([base])
        await makeManager().sync()

        // The sidecar now points at a record the server does not have.
        var state = stateStore.load()
        let remembered = try XCTUnwrap(state.record(for: base.home_id))
        state.remember(HomeSyncRecord(localHomeID: remembered.localHomeID,
                                      remoteID: "srv-does-not-exist",
                                      syncedRevision: remembered.syncedRevision,
                                      syncedFingerprint: "0000000000000000",
                                      lastSyncedAt: remembered.lastSyncedAt))
        try stateStore.save(state)

        let second = makeManager()
        await second.sync()

        XCTAssertEqual(try outcome(second.status).pushed, 1)
        XCTAssertTrue(try outcome(second.status).isClean)
        XCTAssertEqual(try XCTUnwrap(stateStore.load().record(for: base.home_id)).remoteID,
                       try XCTUnwrap(backend.record(withLocalHomeID: base.home_id)).id)
    }

    /// Two concurrent runs would push the same home twice and mint a duplicate server record —
    /// the exact mess `SyncReconciler.collapseDuplicates` exists to clean up between DEVICES.
    /// It must not also happen inside one.
    func testConcurrentSyncsDoNotDoubleUpload() async throws {
        repository = InMemoryHomeRepository([base])
        let manager = makeManager()

        async let first: Void = manager.sync()
        async let second: Void = manager.sync()
        _ = await (first, second)

        XCTAssertEqual(backend.storedHomes.count, 1)
        XCTAssertEqual(backend.storedHomes[0].revision, 1)
    }

    // MARK: - The sidecar

    func testASuccessfulSyncRemembersTheServersRevisionAndRecordID() async throws {
        repository = InMemoryHomeRepository([base])
        await makeManager().sync()

        let record = try XCTUnwrap(stateStore.load().record(for: base.home_id))
        let stored = try XCTUnwrap(backend.record(withLocalHomeID: base.home_id))
        XCTAssertEqual(record.remoteID, stored.id)
        XCTAssertEqual(record.syncedRevision, stored.revision)
        XCTAssertEqual(record.syncedFingerprint, HomeFingerprint.of(base))
        XCTAssertEqual(record.lastSyncedAt, Date(timeIntervalSince1970: 1_800_000))
    }

    /// A sidecar that will not write is not worth failing a sync over — the work already
    /// landed on the server. The cost is one redundant upload next launch, not a lost home.
    func testAnUnwritableSidecarDoesNotFailTheSync() async throws {
        final class RefusingStore: SyncStateStore {
            struct Refused: Error {}
            func load() -> SyncState { .empty }
            func save(_ state: SyncState) throws { throw Refused() }
        }
        repository = InMemoryHomeRepository([base])
        let manager = SyncManager(
            client: CloudHomesClient(baseURL: URL(string: "https://backend.example.com")!,
                                     session: AuthStubURLProtocol.makeSession()),
            repository: repository,
            stateStore: RefusingStore(),
            tokenProvider: { [weak self] in self?.token })

        await manager.sync()

        XCTAssertEqual(try outcome(manager.status).pushed, 1)
        XCTAssertNotNil(backend.record(withLocalHomeID: base.home_id))
    }

}

// MARK: - Regressions found by review, 2026-09-16

/// One test per defect the S8.4 review found at the manager level. Kept separate from the
/// suite above so the reason each exists stays legible.
@MainActor
final class SyncManagerRegressionTests: XCTestCase {

    private var backend: FakeCloudBackend!
    private var repository: InMemoryHomeRepository!
    private var stateStore: InMemorySyncStateStore!
    private var token: AccessToken?
    private var sessionExpiredCount = 0
    private var base: HomeModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        AuthStubURLProtocol.reset()
        backend = FakeCloudBackend()
        backend.install()
        repository = InMemoryHomeRepository()
        stateStore = InMemorySyncStateStore()
        token = makeTestToken(subject: "alice")
        sessionExpiredCount = 0
        base = try Fixtures.load("bungalow")
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        backend = nil
        repository = nil
        stateStore = nil
        super.tearDown()
    }

    private func makeManager() -> SyncManager {
        SyncManager(
            client: CloudHomesClient(baseURL: URL(string: "https://backend.example.com")!,
                                     session: AuthStubURLProtocol.makeSession()),
            repository: repository,
            stateStore: stateStore,
            tokenProvider: { [weak self] in self?.token },
            onSessionExpired: { [weak self] in
                self?.sessionExpiredCount += 1
                // What the app actually does — and the reason the old test passed vacuously:
                // signing out removes the token, so the NEXT status write is `.signedOut` and
                // `.failed(.sessionExpired)` never reaches the screen.
                self?.token = nil
            },
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

    // MARK: - "Sign in again" must survive the sign-out it causes

    /// The old test asserted only that `onSessionExpired` fired, with a double that changed no
    /// state — so it passed while the production wiring made the message unreachable. Here the
    /// double does what the app does (drops the token), and the sticky flag is what keeps the
    /// explanation on screen.
    func testTheSessionExpiredMessageSurvivesTheSignOutItTriggers() async throws {
        repository = InMemoryHomeRepository([base])
        let manager = makeManager()
        backend.failNextPost = 401

        await manager.sync()
        XCTAssertEqual(sessionExpiredCount, 1)
        XCTAssertTrue(manager.needsReauthentication)

        // RootView observes `session.state` and re-enters. With no token this writes
        // `.signedOut` over `.failed(.sessionExpired)` — which is exactly why the flag is
        // separate from the status.
        await manager.syncIfSignedIn()
        XCTAssertEqual(manager.status, .signedOut)
        XCTAssertTrue(manager.needsReauthentication,
                      "the user must still be told WHY they were signed out")
    }

    func testSigningBackInAndSyncingClearsTheReauthenticationFlag() async throws {
        repository = InMemoryHomeRepository([base])
        let manager = makeManager()
        backend.failNextPost = 401
        await manager.sync()
        XCTAssertTrue(manager.needsReauthentication)

        token = makeTestToken(subject: "alice")
        await manager.sync()
        XCTAssertFalse(manager.needsReauthentication)
        XCTAssertTrue(try outcome(manager.status).isClean)
    }

    /// A 401 on the LIST, before any per-home work, must behave the same way.
    func testA401OnTheListAlsoAsksForReauthentication() async {
        backend.failEveryRequest = 401
        let manager = makeManager()
        await manager.sync()
        XCTAssertTrue(manager.needsReauthentication)
        XCTAssertEqual(sessionExpiredCount, 1)
    }

    // MARK: - A losing conflict is set aside, not destroyed

    func testTheLocalCopyIsKeptWhenTheOtherDeviceWinsAConflict() async throws {
        var mine = base!
        mine.name = "Mine"
        mine.meta.modified = Date(timeIntervalSince1970: 1_000_000)
        var theirs = base!
        theirs.name = "Theirs"
        theirs.meta.modified = Date(timeIntervalSince1970: 2_000_000)

        repository = InMemoryHomeRepository([mine])
        let recordID = backend.seed(theirs, revision: 8, userID: "alice")
        var state = SyncState(userID: "alice")
        state.remember(HomeSyncRecord(localHomeID: base.home_id, remoteID: recordID,
                                      syncedRevision: 2,
                                      syncedFingerprint: HomeFingerprint.of(base),
                                      lastSyncedAt: Date(timeIntervalSince1970: 1_000)))
        stateStore = InMemorySyncStateStore(state)

        let manager = makeManager()
        await manager.sync()

        let result = try outcome(manager.status)
        XCTAssertEqual(result.pulled, 1)
        XCTAssertEqual(result.conflicts.count, 1, "the user must be told their edit was replaced")
        XCTAssertEqual(result.conflicts.first?.localHomeID, base.home_id)
        XCTAssertFalse(result.isClean, "a silently replaced home is not a clean sync")

        XCTAssertEqual(repository.preserved.count, 1)
        XCTAssertEqual(repository.preserved.first?.name, "Mine (this device)")
        XCTAssertNotEqual(repository.preserved.first?.home_id, base.home_id,
                          "the copy must have its own id or it is not a copy")
        XCTAssertEqual(repository.writes.last?.name, "Theirs")
    }

    /// An ordinary pull must NOT leave a copy behind, or the library fills with duplicates.
    func testAnOrdinaryPullLeavesNoCopyBehind() async throws {
        let theirs = base.renamedCopy(homeID: "home-theirs", name: "Theirs")
        backend.seed(theirs, userID: "alice")
        let manager = makeManager()

        await manager.sync()

        XCTAssertEqual(try outcome(manager.status).pulled, 1)
        XCTAssertTrue(repository.preserved.isEmpty)
        XCTAssertTrue(try outcome(manager.status).conflicts.isEmpty)
    }

    // MARK: - The sidecar belongs to one account

    func testASecondUserOnTheSameDeviceDoesNotInheritTheFirstUsersRecords() async throws {
        repository = InMemoryHomeRepository([base])

        // Alice syncs.
        var manager = makeManager()
        await manager.sync()
        XCTAssertEqual(stateStore.load().userID, "alice")
        let aliceRecordID = try XCTUnwrap(stateStore.load().record(for: base.home_id)?.remoteID)

        // Bob signs in on the same device. The sidecar still holds Alice's record.
        token = makeTestToken(subject: "bob")
        manager = makeManager()
        await manager.sync()

        let afterBob = stateStore.load()
        XCTAssertEqual(afterBob.userID, "bob")
        XCTAssertNotEqual(afterBob.record(for: base.home_id)?.remoteID, aliceRecordID,
                          "Bob must not keep pointing at a record in Alice's account")
    }

    // MARK: - A deleted home stays deleted

    func testADeletedHomeIsNotDownloadedAgain() async throws {
        let deleted = base.renamedCopy(homeID: "home-deleted")
        backend.seed(deleted, userID: "alice")
        var state = SyncState(userID: "alice")
        state.markDeleted(localHomeID: "home-deleted", at: Date())
        stateStore = InMemorySyncStateStore(state)

        let manager = makeManager()
        await manager.sync()

        XCTAssertTrue(repository.writes.isEmpty, "a deliberately deleted home must not come back")
        XCTAssertEqual(try outcome(manager.status).skipped, 1)
        XCTAssertEqual(try outcome(manager.status).pulled, 0)
    }

    // MARK: - A request made during a sync is served, not dropped

    /// Render's free tier has been measured at a 42 s cold start. A user who finishes an edit
    /// and taps the badge during a launch sync must not have that request silently discarded —
    /// their edit would not go up and the badge would report success anyway.
    func testASyncRequestedWhileOneIsRunningIsServedAfterwards() async throws {
        repository = InMemoryHomeRepository([base])
        let manager = makeManager()

        async let first: Void = manager.sync()
        async let second: Void = manager.sync()
        _ = await (first, second)

        // Still exactly one record — the re-entry must not duplicate anything...
        XCTAssertEqual(backend.storedHomes.count, 1)
        // ...and the second run really happened: two GETs, not one.
        XCTAssertGreaterThanOrEqual(backend.requestCount, 3)
        XCTAssertTrue(try outcome(manager.status).isClean)
    }

    // MARK: - Progress is not lost when a run is cut short

    func testTheSidecarIsWrittenAfterEachHomeNotOnlyAtTheEnd() async throws {
        repository = InMemoryHomeRepository([base.renamedCopy(homeID: "home-a"),
                                             base.renamedCopy(homeID: "home-b")])
        let manager = makeManager()
        await manager.sync()

        // Three writes at least: one per home, plus the run's own. The point is that a run
        // killed after the first home still leaves that home's record behind.
        XCTAssertGreaterThanOrEqual(stateStore.saveCount, 2)
        XCTAssertNotNil(stateStore.load().record(for: "home-a"))
        XCTAssertNotNil(stateStore.load().record(for: "home-b"))
    }
}

// MARK: - Whose homes are these? (the scope question, ruled 2026-09-16)

/// The rule: **the first account to sign in adopts the device's homes; a second one never
/// does.** Both halves matter, and testing only one would let the other regress silently —
/// break adoption and "sign in to back up your homes" quietly does nothing; break the second
/// and one person's home layout, address and household land in a stranger's cloud account.
@MainActor
final class SyncHomeOwnershipTests: XCTestCase {

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
        base = try Fixtures.load("bungalow")
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        backend = nil
        repository = nil
        stateStore = nil
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

    // MARK: - Adoption must work

    /// The common case by a wide margin: someone uses the app offline for a while, then signs
    /// up. Their existing homes MUST reach their account, or the feature does nothing at all
    /// for the person most likely to use it.
    func testTheFirstAccountToSignInAdoptsTheDevicesHomes() async throws {
        repository = InMemoryHomeRepository([base.renamedCopy(homeID: "home-a"),
                                             base.renamedCopy(homeID: "home-b")])
        token = makeTestToken(subject: "alice")
        let manager = makeManager()

        await manager.sync()

        XCTAssertEqual(try outcome(manager.status).pushed, 2)
        XCTAssertEqual(try outcome(manager.status).skippedOtherAccount, 0)
        XCTAssertNotNil(backend.record(withLocalHomeID: "home-a"))
        XCTAssertNotNil(backend.record(withLocalHomeID: "home-b"))
    }

    func testSyncingRecordsWhoOwnsEachHome() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        await makeManager().sync()

        XCTAssertEqual(stateStore.load().ownership(of: base.home_id), .mine)
        XCTAssertEqual(stateStore.load().homeOwners[base.home_id], "alice")
    }

    /// Ownership must survive the account switch, or the rule has nothing to consult.
    func testOwnershipOutlivesAnAccountSwitch() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        await makeManager().sync()

        token = makeTestToken(subject: "bob")
        XCTAssertEqual(stateStore.load().scoped(to: "bob").ownership(of: base.home_id),
                       .anotherAccount(userID: "alice"))
    }

    // MARK: - A second account must not adopt them

    func testASecondAccountDoesNotUploadTheFirstUsersHomes() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        await makeManager().sync()
        let aliceRecordCount = backend.storedHomes.count
        XCTAssertEqual(aliceRecordCount, 1)

        // Bob signs in on the same device.
        token = makeTestToken(subject: "bob")
        let manager = makeManager()
        await manager.sync()

        XCTAssertEqual(backend.storedHomes.count, aliceRecordCount,
                       "Alice's home must not be copied into Bob's account")
        XCTAssertNil(backend.storedHomes.first { $0.userID == "bob" },
                     "Bob's account must still be empty")
        XCTAssertEqual(try outcome(manager.status).skippedOtherAccount, 1)
        XCTAssertEqual(try outcome(manager.status).pushed, 0)
    }

    /// And Bob's own homes must still sync — the rule is about ONE home's ownership, not a
    /// blanket refusal to sync once a second account appears.
    func testASecondAccountStillSyncsItsOwnHomes() async throws {
        repository = InMemoryHomeRepository([base.renamedCopy(homeID: "home-alice")])
        token = makeTestToken(subject: "alice")
        await makeManager().sync()

        token = makeTestToken(subject: "bob")
        try repository.writePulledHome(base.renamedCopy(homeID: "home-bob", name: "Bob's place"))
        let manager = makeManager()
        await manager.sync()

        XCTAssertEqual(try outcome(manager.status).pushed, 1)
        XCTAssertEqual(try outcome(manager.status).skippedOtherAccount, 1)
        XCTAssertEqual(backend.record(withLocalHomeID: "home-bob")?.userID, "bob")
        XCTAssertNil(backend.storedHomes.first { $0.home.home_id == "home-alice" && $0.userID == "bob" })
    }

    /// Nor may the second account's server copy overwrite the first user's local file. Skipped
    /// means skipped in both directions.
    func testASecondAccountDoesNotOverwriteTheFirstUsersLocalHome() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        await makeManager().sync()

        // Bob's account happens to hold a home with the same id — which is not exotic: the
        // three bundled starter homes keep FIXED home_ids on every install.
        var bobsVersion = base!
        bobsVersion.name = "Bob's Bungalow"
        backend.seed(bobsVersion, revision: 9, userID: "bob")

        token = makeTestToken(subject: "bob")
        let manager = makeManager()
        await manager.sync()

        XCTAssertTrue(repository.writes.isEmpty,
                      "Alice's local home must not be replaced by Bob's server copy")
        XCTAssertEqual(try outcome(manager.status).skippedOtherAccount, 1)
    }

    /// A home nobody has ever synced is unclaimed, even on a device that has seen two accounts.
    func testAHomeCreatedAfterTheSwitchIsAdoptedByTheCurrentAccount() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        await makeManager().sync()

        token = makeTestToken(subject: "bob")
        try repository.writePulledHome(base.renamedCopy(homeID: "brand-new"))
        await makeManager().sync()

        XCTAssertEqual(stateStore.load().homeOwners["brand-new"], "bob")
        XCTAssertEqual(backend.record(withLocalHomeID: "brand-new")?.userID, "bob")
    }

    // MARK: - Deletions are scoped the same way

    /// One user's deletion must not edit another user's library. The starter homes share fixed
    /// ids, so this is reachable rather than theoretical.
    func testOneUsersDeletionDoesNotSuppressAnothersHome() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        await makeManager().sync()

        // Alice deletes it.
        var state = stateStore.load()
        state.markDeleted(localHomeID: base.home_id, at: Date())
        try stateStore.save(state)
        repository = InMemoryHomeRepository()

        // Bob's account has a home at the same id, and must receive it.
        var bobsVersion = base!
        bobsVersion.name = "Bob's Bungalow"
        backend.seed(bobsVersion, revision: 2, userID: "bob")
        token = makeTestToken(subject: "bob")
        let manager = makeManager()

        await manager.sync()

        XCTAssertEqual(try outcome(manager.status).pulled, 1,
                       "Alice's deletion must not reach into Bob's library")
        XCTAssertEqual(repository.writes.first?.name, "Bob's Bungalow")
    }

    /// And it must still suppress it for Alice herself.
    func testTheDeletingUsersOwnTombstoneStillHolds() async throws {
        repository = InMemoryHomeRepository([base])
        token = makeTestToken(subject: "alice")
        await makeManager().sync()

        var state = stateStore.load()
        state.markDeleted(localHomeID: base.home_id, at: Date())
        try stateStore.save(state)
        repository = InMemoryHomeRepository()

        let manager = makeManager()
        await manager.sync()

        XCTAssertTrue(repository.writes.isEmpty, "Alice deleted it; it must stay deleted for her")
        XCTAssertEqual(try outcome(manager.status).skipped, 1)
    }
}

// MARK: - Conflict copies (S11.22, AUD-015)

/// A pull that loses a conflict sets the local copy aside as "<name> (this device)". The audit
/// found that with the home open in House the pull is refused AFTER the copy is made, the sync
/// record is not updated, and the next sync makes another copy: one more per sync, each uploaded
/// and downloaded to every other device. Reasoned from code by the audit; reproduced here.
@MainActor
final class SyncConflictCopyTests: XCTestCase {

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
        token = makeTestToken(subject: "alice")
        base = try Fixtures.load("bungalow")
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        backend = nil
        repository = nil
        stateStore = nil
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

    /// Edited here ("Mine") and on another device ("Theirs", later), so the server wins and the
    /// local copy must be set aside.
    private func makeRemoteWinsConflict() {
        var mine = base!
        mine.name = "Mine"
        mine.meta.modified = Date(timeIntervalSince1970: 1_000_000)
        var theirs = base!
        theirs.name = "Theirs"
        theirs.meta.modified = Date(timeIntervalSince1970: 2_000_000)

        repository = InMemoryHomeRepository([mine])
        let recordID = backend.seed(theirs, revision: 8, userID: "alice")
        var state = SyncState(userID: "alice")
        state.remember(HomeSyncRecord(localHomeID: base.home_id, remoteID: recordID,
                                      syncedRevision: 2,
                                      syncedFingerprint: HomeFingerprint.of(base),
                                      lastSyncedAt: Date(timeIntervalSince1970: 1_000)))
        stateStore = InMemorySyncStateStore(state)
    }

    private var conflictCopies: [HomeModel] {
        repository.homes.values.filter { $0.name.hasSuffix("(this device)") }
    }

    // MARK: MISSION 1

    func testTwoSyncsWithTheHomeOpenMakeAtMostOneConflictCopy() async throws {
        makeRemoteWinsConflict()
        repository.openHomeID = base.home_id

        await makeManager().sync()
        await makeManager().sync()

        XCTAssertLessThanOrEqual(conflictCopies.count, 1,
                                 "each sync with the home open made another \"(this device)\" copy")
    }

    // MARK: MISSION 2 and 4: never while open, and it still resolves once closed

    func testNoCopyIsMadeWhileTheHomeIsOpenAndTheBadgeSaysWhy() async throws {
        makeRemoteWinsConflict()
        repository.openHomeID = base.home_id
        let manager = makeManager()

        await manager.sync()

        let result = try outcome(manager.status)
        XCTAssertTrue(repository.preserved.isEmpty, "nothing may be copied for a pull that cannot land")
        XCTAssertTrue(repository.writes.isEmpty)
        XCTAssertTrue(result.conflicts.isEmpty, "no copy was made, so none may be reported")
        XCTAssertEqual(result.failures.map(\.localHomeID), [base.home_id])
        XCTAssertEqual(result.failures.first?.failure, .editorHasTheHomeOpen,
                       "the badge names this message when it is the only failure")
        XCTAssertEqual(stateStore.load().record(for: base.home_id)?.syncedRevision, 2,
                       "the pull did not happen, so the record must not claim it did")
    }

    func testThreeSyncsWhileOpenThenOneAfterClosingMakeExactlyOneCopy() async throws {
        makeRemoteWinsConflict()
        repository.openHomeID = base.home_id
        for _ in 1...3 { await makeManager().sync() }
        XCTAssertEqual(conflictCopies.count, 0)

        repository.openHomeID = nil
        let closed = makeManager()
        await closed.sync()

        let result = try outcome(closed.status)
        XCTAssertEqual(result.pulled, 1, "the conflict resolves once the home is closed")
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(conflictCopies.map(\.name), ["Mine (this device)"])
        XCTAssertEqual(repository.homes[base.home_id]?.name, "Theirs")
        XCTAssertEqual(stateStore.load().record(for: base.home_id)?.syncedRevision, 8)
        XCTAssertTrue(stateStore.load().preservedCopies.isEmpty, "a resolved conflict leaves nothing behind")

        // And it stays resolved: the next sync uploads the copy and makes no other.
        let after = makeManager()
        await after.sync()
        XCTAssertEqual(conflictCopies.count, 1)
        XCTAssertTrue(try outcome(after.status).conflicts.isEmpty)
    }

    // MARK: MISSION 3: at most once per conflict

    /// The one path left where a copy is made and the pull still fails: the disk refuses the
    /// write after the check passed. The next sync must find the copy, not make another.
    func testAFailedWriteAfterTheCopyReusesThatCopyNextTime() async throws {
        struct DiskFull: Error {}
        makeRemoteWinsConflict()
        repository.failNextWrite = DiskFull()

        let first = makeManager()
        await first.sync()
        XCTAssertEqual(try outcome(first.status).failures.count, 1)
        let copyID = try XCTUnwrap(conflictCopies.first?.home_id)
        XCTAssertEqual(stateStore.load().preservedCopies[base.home_id]?.copyHomeID, copyID)

        let second = makeManager()
        await second.sync()

        let result = try outcome(second.status)
        XCTAssertEqual(result.pulled, 1)
        XCTAssertEqual(repository.preserved.count, 1, "the same version must not be copied twice")
        XCTAssertEqual(result.conflicts, [HomeSyncConflict(localHomeID: base.home_id, preservedAs: copyID)])
        XCTAssertNil(stateStore.load().preservedCopies[base.home_id])
    }

    /// Since S11.21 the user can delete a "(this device)" copy. A recorded copy that is gone
    /// was discarded: it must not come back, and a fresh one must not be made.
    func testADeletedConflictCopyIsNeitherBroughtBackNorMadeAgain() async throws {
        struct DiskFull: Error {}
        makeRemoteWinsConflict()
        repository.failNextWrite = DiskFull()
        await makeManager().sync()
        let copyID = try XCTUnwrap(conflictCopies.first?.home_id)

        // What "Your homes" → Delete does: the file goes, then the tombstone is written.
        repository.delete(homeID: copyID)
        var state = stateStore.load()
        state.markDeleted(localHomeID: copyID, at: Date(timeIntervalSince1970: 1_700_000))
        try stateStore.save(state)

        let manager = makeManager()
        await manager.sync()

        let result = try outcome(manager.status)
        XCTAssertEqual(result.pulled, 1, "the conflict still resolves")
        XCTAssertTrue(result.conflicts.isEmpty, "there is no copy to tell the user about")
        XCTAssertEqual(repository.preserved.count, 1, "no second copy")
        XCTAssertNil(repository.homes[copyID], "the deleted copy must not come back")
        XCTAssertTrue(conflictCopies.isEmpty)
        XCTAssertEqual(repository.homes[base.home_id]?.name, "Theirs")

        // Two more syncs: still nothing.
        for _ in 1...2 { await makeManager().sync() }
        XCTAssertEqual(repository.preserved.count, 1)
        XCTAssertTrue(conflictCopies.isEmpty)
    }

    /// Edited again after the first copy: that version is new work, so it is kept too.
    func testAnEditMadeAfterTheCopyIsKeptAsWell() async throws {
        struct DiskFull: Error {}
        makeRemoteWinsConflict()
        repository.failNextWrite = DiskFull()
        await makeManager().sync()

        var edited = try XCTUnwrap(repository.homes[base.home_id])
        edited.floors[0].rooms[0].name = "Edited after the copy"
        repository.edit(edited)
        await makeManager().sync()

        XCTAssertEqual(repository.preserved.count, 2, "one copy per version, not one per sync")
        XCTAssertEqual(conflictCopies.count, 2, "both versions are kept")
        XCTAssertTrue(conflictCopies.contains { $0.floors[0].rooms[0].name == "Edited after the copy" })
    }
}

// MARK: - A tombstone written while a sync runs (S11.22, from S11.21)

/// A state store that runs a hook once: after its first save (a home deleted between two of a
/// running sync's actions), or inside its Nth `load()` before returning (a home deleted during
/// one of the sync's awaits, which the sync only sees at its next read). Synchronous, as the
/// real deletion is on the main actor, so it lands at exactly that point.
///
/// A sync reads the sidecar in this order: 1 the tombstone snapshot, 2 the state after
/// `GET /homes`, then for each action 3 before it and 4 in its `persist`, and so on.
private final class InterleavingStateStore: SyncStateStore {
    private var state: SyncState
    private var loadCount = 0
    var afterSave: ((InterleavingStateStore) -> Void)?
    var onLoad: (number: Int, hook: (InterleavingStateStore) -> Void)?

    init(_ state: SyncState = .empty) { self.state = state }

    func load() -> SyncState {
        loadCount += 1
        if let pending = onLoad, pending.number == loadCount {
            onLoad = nil
            pending.hook(self)
        }
        return state
    }

    func save(_ state: SyncState) throws {
        self.state = state
        if let hook = afterSave {
            afterSave = nil
            hook(self)
        }
    }

    /// What `HomeDocumentSyncRepository.homeWasDeletedLocally` writes, without counting a load.
    func writeTombstone(for homeID: String, at date: Date) {
        state.markDeleted(localHomeID: homeID, at: date)
    }
}

@MainActor
final class SyncMidRunDeletionTests: XCTestCase {

    private var backend: FakeCloudBackend!
    private var repository: InMemoryHomeRepository!
    private var stateStore: InterleavingStateStore!
    private var base: HomeModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        AuthStubURLProtocol.reset()
        backend = FakeCloudBackend()
        backend.install()
        stateStore = InterleavingStateStore()
        base = try Fixtures.load("bungalow")
        repository = InMemoryHomeRepository([base.renamedCopy(homeID: "home-a"),
                                             base.renamedCopy(homeID: "home-b")])
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        backend = nil
        repository = nil
        stateStore = nil
        super.tearDown()
    }

    private func makeManager() -> SyncManager {
        SyncManager(
            client: CloudHomesClient(baseURL: URL(string: "https://backend.example.com")!,
                                     session: AuthStubURLProtocol.makeSession()),
            repository: repository,
            stateStore: stateStore,
            tokenProvider: { makeTestToken(subject: "alice") },
            now: { Date(timeIntervalSince1970: 1_800_000) })
    }

    /// "Your homes" → Delete: the file goes, then the tombstone is written to the sidecar.
    private func deletion(of homeID: String,
                          at date: Date = Date(timeIntervalSince1970: 1_750_000))
        -> (InterleavingStateStore) -> Void {
        { [repository] store in
            repository?.delete(homeID: homeID)
            store.writeTombstone(for: homeID, at: date)
        }
    }

    private func deleteOnThisDevice(_ homeID: String) {
        stateStore.afterSave = deletion(of: homeID)
    }

    /// home-b is deleted after home-a's action: its planned upload must not happen, and the
    /// run's later writes must keep its tombstone.
    func testAHomeDeletedMidSyncIsNotUploadedAndKeepsItsTombstone() async throws {
        deleteOnThisDevice("home-b")
        await makeManager().sync()

        XCTAssertNotNil(backend.record(withLocalHomeID: "home-a"))
        XCTAssertNil(backend.record(withLocalHomeID: "home-b"), "a home deleted mid-sync must not be uploaded")
        XCTAssertNotNil(stateStore.load().deletions["home-b"], "the running sync dropped the tombstone")
        XCTAssertNil(stateStore.load().record(for: "home-b"))
    }

    /// home-a is deleted right after it was uploaded. The tombstone (with Alice as owner)
    /// must survive the run, so the NEXT sync removes it from the account instead of pulling
    /// it back.
    func testAHomeDeletedAfterItsUploadIsRemovedFromTheAccountNextSync() async throws {
        deleteOnThisDevice("home-a")
        await makeManager().sync()

        let tombstone = try XCTUnwrap(stateStore.load().deletions["home-a"],
                                      "the running sync dropped the tombstone")
        XCTAssertEqual(tombstone.ownerUserID, "alice", "the claim it released is kept on the tombstone")
        XCTAssertNil(stateStore.load().homeOwners["home-a"])
        XCTAssertNil(stateStore.load().record(for: "home-a"))
        XCTAssertNotNil(backend.record(withLocalHomeID: "home-a"), "it was uploaded before the delete")

        await makeManager().sync()

        XCTAssertNil(repository.homes["home-a"], "the deleted home must not be downloaded again")
        XCTAssertNil(backend.record(withLocalHomeID: "home-a"), "and its account copy goes")
    }

    /// Deleted while `GET /homes` is in flight: the library was already read, so the plan still
    /// lists the home. It must not be uploaded, and its tombstone must survive (review finding).
    func testAHomeDeletedDuringTheListIsNotUploadedOrBroughtBack() async throws {
        repository = InMemoryHomeRepository([base.renamedCopy(homeID: "home-a")])
        let delete = deletion(of: "home-a")
        repository.afterLoadAllHomes = { [stateStore] in stateStore.map(delete) }

        await makeManager().sync()

        XCTAssertNil(backend.record(withLocalHomeID: "home-a"), "deleted during the list, then uploaded")
        XCTAssertNotNil(stateStore.load().deletions["home-a"], "the tombstone was read as stale")

        await makeManager().sync()
        XCTAssertNil(repository.homes["home-a"], "the deleted home came back")
    }

    /// Deleted during its own first upload: the sidecar has no owner for it yet, so the
    /// tombstone must take the owner this run just claimed, or its account copy is never
    /// removed (review finding).
    func testAHomeDeletedDuringItsFirstUploadIsStillRemovedFromTheAccount() async throws {
        repository = InMemoryHomeRepository([base.renamedCopy(homeID: "home-a")])
        // Load 4 is the persist right after home-a's push, before the claim reaches the file.
        stateStore.onLoad = (4, deletion(of: "home-a"))

        await makeManager().sync()

        XCTAssertEqual(stateStore.load().deletions["home-a"]?.ownerUserID, "alice")
        XCTAssertNotNil(backend.record(withLocalHomeID: "home-a"), "it was uploaded before the delete")

        await makeManager().sync()
        XCTAssertNil(backend.record(withLocalHomeID: "home-a"), "an ownerless tombstone left it in the account")
    }

    /// A home with an old tombstone is back on disk, so this run clears the tombstone; then the
    /// user deletes it again before its action. The new tombstone has a new date and must stop
    /// the upload (review finding).
    func testAHomeDeletedAgainAfterItsOldTombstoneWasClearedIsNotUploaded() async throws {
        repository = InMemoryHomeRepository([base.renamedCopy(homeID: "home-a")])
        var state = SyncState(userID: "alice")
        state.markDeleted(localHomeID: "home-a", at: Date(timeIntervalSince1970: 1_600_000))
        stateStore = InterleavingStateStore(state)
        // Load 3 is just before home-a's action.
        stateStore.onLoad = (3, deletion(of: "home-a"))

        await makeManager().sync()

        XCTAssertNil(backend.record(withLocalHomeID: "home-a"), "the re-deleted home was uploaded")
        XCTAssertEqual(stateStore.load().deletions["home-a"]?.deletedAt,
                       Date(timeIntervalSince1970: 1_750_000))
    }

    /// The tombstones a sync clears on purpose (a home back on disk) are not put back by the
    /// merge.
    func testATombstoneTheSyncClearedOnPurposeStaysCleared() async throws {
        var state = SyncState(userID: "alice")
        state.markDeleted(localHomeID: "home-a", at: Date(timeIntervalSince1970: 1_600_000))
        stateStore = InterleavingStateStore(state)

        await makeManager().sync()

        XCTAssertNil(stateStore.load().deletions["home-a"], "home-a is on disk again")
        XCTAssertNotNil(backend.record(withLocalHomeID: "home-a"))
    }
}
