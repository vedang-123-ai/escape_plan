//  SignedOutProofTests.swift — S11.7: the app works with no account and no server.
//
//  The claim this file exists to keep true is on the sign-in screen, in
//  `AccountPrivacy.signedOutSummary`: signed out, your homes are saved only on this iPhone and
//  you never need an account. The soft gate, the pitch and the privacy copy all rest on it.
//
//  Scope, corrected in S11.16 (AUD-050): this proves the SYNC half — no token means no `/homes`
//  request, so nothing is saved to a server. It does NOT prove that nothing leaves the phone,
//  and nothing should claim it does: `/score`, `/routes`, `/evacuate` and `/chat` send the
//  whole home signed in or out. What those requests carry is pinned against the copy in
//  `AccountPrivacyTests`.
//
//  What can be proved HERE is the part that is pure: no token means no sync request, an
//  unreachable server changes a badge and nothing else, and nothing in the auth layer can put
//  itself in front of the app. Whether the SCREENS behave is a simulator question — `SignedOutPathUITests`
//  walks them, and BLOCKERS records that it has not been run on this machine.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class SignedOutProofTests: XCTestCase {

    private var backend: FakeCloudBackend!
    private var repository: InMemoryHomeRepository!
    private var stateStore: InMemorySyncStateStore!
    private var base: HomeModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        AuthStubURLProtocol.reset()
        backend = FakeCloudBackend()
        backend.install()
        base = try Fixtures.load("bungalow")
        repository = InMemoryHomeRepository([base])
        stateStore = InMemorySyncStateStore()
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        backend = nil; repository = nil; stateStore = nil
        super.tearDown()
    }

    private func makeManager(token: AccessToken? = nil) -> SyncManager {
        SyncManager(
            client: CloudHomesClient(baseURL: URL(string: "https://backend.example.com")!,
                                     session: AuthStubURLProtocol.makeSession()),
            repository: repository,
            stateStore: stateStore,
            tokenProvider: { token })
    }

    // MARK: - Nothing is saved to the server

    /// "Saved only on this iPhone", from the sign-in screen. `syncIfSignedIn` is what every
    /// call site in `RootView` uses — launch, sign-in, and returning to the foreground.
    func testASignedOutLaunchSendsNoRequestAtAll() async {
        let manager = makeManager()

        await manager.syncIfSignedIn()
        await manager.syncIfSignedIn()

        XCTAssertEqual(backend.requestCount, 0)
        XCTAssertEqual(manager.status, .signedOut)
    }

    /// Even called directly rather than through the guard. `sync()` is reachable from the
    /// badge, and a user who taps it signed out must not produce an unauthenticated POST
    /// carrying their floor plan.
    func testCallingSyncDirectlyWhileSignedOutSavesNothingToTheServer() async {
        let manager = makeManager()

        await manager.sync()

        XCTAssertEqual(backend.requestCount, 0)
        XCTAssertTrue(backend.storedHomes.isEmpty)
        XCTAssertEqual(manager.status, .signedOut)
    }

    /// Signed out, the sidecar records nothing about the homes on this device — so there is no
    /// account-shaped state sitting on disk for a home that was never in an account.
    func testASignedOutSyncWritesNothingToTheSidecar() async {
        await makeManager().syncIfSignedIn()
        XCTAssertEqual(stateStore.load(), SyncState.empty)
    }

    // MARK: - Nothing is blocked

    /// A signed-out sync must never touch a home document — not read-then-write, not
    /// "helpfully" normalise one.
    func testASignedOutSyncNeverWritesAHomeDocument() async {
        await makeManager().syncIfSignedIn()
        XCTAssertTrue(repository.writes.isEmpty)
        XCTAssertEqual(try? repository.loadAllHomes().count, 1)
    }

    /// With the backend unreachable and a token present, sync fails — and that failure is a
    /// badge, not a dead app. `.failed` is a status the UI renders; nothing else changes.
    func testAnUnreachableServerIsAStatusAndNothingMore() async {
        let manager = makeManager(token: makeTestToken())
        AuthStubURLProtocol.fail(with: URLError(.notConnectedToInternet))

        await manager.sync()

        guard case .failed = manager.status else {
            return XCTFail("expected a failed status, got \(manager.status)")
        }
        XCTAssertEqual(try? repository.loadAllHomes().count, 1,
                       "an offline sync must leave the library exactly as it was")
        XCTAssertTrue(repository.writes.isEmpty)
    }

    // MARK: - The gate is an invitation

    /// `shouldPresentGate` is the ONLY thing in the auth layer that can put itself in front of
    /// the app, and it must be answerable without a network call, a token, or a server.
    func testTheGateIsDismissedOfflineWithNoServerAtAll() {
        let suite = "signedout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AuthSession.hasLaunchedKey)
        AuthStubURLProtocol.fail(with: URLError(.notConnectedToInternet))

        let session = AuthSession(
            client: AuthClient(baseURL: URL(string: "https://backend.example.com")!,
                               session: AuthStubURLProtocol.makeSession()),
            store: InMemoryTokenStore(),
            defaults: defaults)

        XCTAssertTrue(session.shouldPresentGate)
        session.continueWithoutAccount()
        XCTAssertFalse(session.shouldPresentGate)
        XCTAssertTrue(AuthStubURLProtocol.capturedRequests.isEmpty,
                      "getting past the gate must not require reaching a server")
    }

    /// `refresh()` runs from `RootView.task` on every launch. Signed out it must be a no-op —
    /// not a request that fails, not a spinner, nothing.
    func testRefreshDoesNothingWhenSignedOut() async {
        let suite = "signedout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AuthSession.hasLaunchedKey)

        let session = AuthSession(
            client: AuthClient(baseURL: URL(string: "https://backend.example.com")!,
                               session: AuthStubURLProtocol.makeSession()),
            store: InMemoryTokenStore(),
            defaults: defaults)

        await session.refresh()

        XCTAssertTrue(AuthStubURLProtocol.capturedRequests.isEmpty)
        XCTAssertFalse(session.isWorking)
        XCTAssertNil(session.failure)
    }
}
