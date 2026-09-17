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
