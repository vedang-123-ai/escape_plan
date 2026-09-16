//  AuthSessionTests.swift — every transition that changes who is signed in.
//
//  This is the file that keeps S8.3 from being another body of unverified Swift. All of the
//  session's decision-making lives in AuthSession rather than in the views, so these run here,
//  on a machine with no simulator, against a stubbed transport and an in-memory token store.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class AuthSessionTests: XCTestCase {

    private var store: InMemoryTokenStore!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        AuthStubURLProtocol.reset()
        store = InMemoryTokenStore()
        suiteName = "auth.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        liveToken = Self.mintToken()
        expiredToken = Self.mintToken(expiresIn: -300)
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil; store = nil; suiteName = nil
        liveToken = nil; expiredToken = nil
        super.tearDown()
    }

    // MARK: - Tokens, minted fresh

    /// Tokens are built at test time, NOT pasted as literals.
    ///
    /// A pasted token carries a fixed `exp`, and `AuthSession.restore()` checks expiry against
    /// the real clock with no seam to inject one. The first version of this file pinned a real
    /// backend-signed token whose `exp` was **2026-09-16T06:39:01Z** — so the suite was
    /// scheduled to go permanently red that morning, silently, in the one file whose entire
    /// purpose is to keep S8.3 verified. Minting relative to `Date()` removes the cliff.
    ///
    /// The signature is deliberately junk: `AccessToken` never verifies one (it cannot — the
    /// secret is server-side), it only base64url-decodes the payload. The claim names and the
    /// NumericDate encoding are the parts that must match the backend, and those are pinned
    /// against genuinely backend-signed tokens in `AccessTokenTests`.
    private var liveToken: String!
    private var expiredToken: String!

    private static func mintToken(sub: String = "user-abc-123",
                                  expiresIn: TimeInterval = 3600,
                                  now: Date = Date()) -> String {
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let claims: [String: Any] = [
            "sub": sub,
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(expiresIn).timeIntervalSince1970),
        ]
        let payload = base64URL(try! JSONSerialization.data(withJSONObject: claims))
        return "\(header).\(payload).signature-is-never-verified-client-side"
    }

    private static let userJSON = #"""
    {"id":"u-1","email":"ada@example.com","created_at":"2026-09-16T05:33:58.567000Z"}
    """#

    private func makeSession(store overrideStore: TokenStore? = nil) -> AuthSession {
        AuthSession(client: AuthClient(baseURL: URL(string: "https://backend.example.com")!,
                                       session: AuthStubURLProtocol.makeSession()),
                    store: overrideStore ?? store,
                    defaults: defaults)
    }

    /// Marks the install as "has run before", so a test that is not about the first-launch
    /// purge is not silently wiped by it.
    private func markNotFirstLaunch() {
        defaults.set(true, forKey: AuthSession.hasLaunchedKey)
    }

    // MARK: - The gate is an invitation, not a wall

    func testGateIsPresentedWhenNobodyIsSignedIn() {
        markNotFirstLaunch()
        let session = makeSession()
        session.restore()
        XCTAssertTrue(session.shouldPresentGate)
    }

    /// "Continue without an account" must be remembered, or the gate nags on every launch and
    /// people learn to dismiss it without reading.
    func testContinuingWithoutAnAccountIsRememberedAcrossLaunches() {
        markNotFirstLaunch()
        let first = makeSession()
        first.continueWithoutAccount()
        XCTAssertFalse(first.shouldPresentGate)

        let relaunched = makeSession()
        relaunched.restore()
        XCTAssertFalse(relaunched.shouldPresentGate, "the choice did not survive a relaunch")
    }

    /// Signing out is a request to be asked again.
    func testSigningOutBringsTheGateBack() async {
        markNotFirstLaunch()
        let session = makeSession()
        session.continueWithoutAccount()
        session.signOut()
        XCTAssertTrue(session.shouldPresentGate)
    }

    // MARK: - Restore

    func testRestoreSignsInFromTheKeychainWithoutTouchingTheNetwork() async throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()

        // No stub installed: any request at all would fail the test by failing the restore.
        let session = makeSession()
        session.restore()

        XCTAssertEqual(session.state.user?.email, "ada@example.com")
        XCTAssertEqual(session.token?.raw, liveToken)
        XCTAssertFalse(session.shouldPresentGate)
        XCTAssertTrue(AuthStubURLProtocol.capturedRequests.isEmpty,
                      "restore must be offline-safe — the first screen cannot wait on a server")
    }

    func testRestoreDiscardsAnExpiredTokenRatherThanShowingADeadSession() async throws {
        markNotFirstLaunch()
        try store.save(expiredToken)
        try seedCachedUser()

        let session = makeSession()
        session.restore()

        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertNil(store.load(), "an expired token should not be left lying in the Keychain")
    }

    /// A token we cannot attribute to anyone is not something to show a signed-in screen for.
    func testRestoreWithNoCachedIdentityStartsClean() throws {
        markNotFirstLaunch()
        try store.save(liveToken)

        let session = makeSession()
        session.restore()

        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertNil(store.load())
    }

    /// On iOS a Keychain item outlives the app that wrote it: delete the app, reinstall, and
    /// the old token is still there. Without the purge, a reinstall silently resumes a session
    /// the user may have deleted the app to get out of.
    func testFirstLaunchAfterReinstallPurgesAnInheritedToken() throws {
        try store.save(liveToken)
        try seedCachedUser()
        // UserDefaults does NOT survive deletion, so the flag being absent is the signal.
        XCTAssertFalse(defaults.bool(forKey: AuthSession.hasLaunchedKey))

        let session = makeSession()
        session.restore()

        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertNil(store.load(), "an inherited Keychain token must be purged on first launch")
        XCTAssertTrue(defaults.bool(forKey: AuthSession.hasLaunchedKey))
    }

    func testSecondLaunchDoesNotPurge() throws {
        let first = makeSession()
        first.restore()                       // sets the flag

        try store.save(liveToken)
        try seedCachedUser()

        let second = makeSession()
        second.restore()
        XCTAssertTrue(second.state.isSignedIn, "the purge must happen once, not every launch")
    }

    // MARK: - Sign in

    func testSignInStoresTheTokenAndTheIdentity() async {
        markNotFirstLaunch()
        let token = liveToken!
        AuthStubURLProtocol.respond { request in
            request.url?.path == "/auth/login"
                ? .init(statusCode: 200,
                        body: Data(#"{"access_token":"\#(token)","token_type":"bearer"}"#.utf8),
                        error: nil)
                : .init(statusCode: 200, body: Data(Self.userJSON.utf8), error: nil)
        }

        let session = makeSession()
        await session.signIn(email: "  ADA@Example.com ", password: "a-good-password")

        XCTAssertEqual(session.state.user?.email, "ada@example.com")
        XCTAssertEqual(store.load(), liveToken)
        XCTAssertNil(session.failure)
        XCTAssertFalse(session.isWorking)
        XCTAssertFalse(session.shouldPresentGate)
    }

    /// The address is normalised before it is sent, so "Ada@Example.com" reaches the same
    /// account the server stored as "ada@example.com".
    func testSignInNormalisesTheEmailBeforeSending() async {
        markNotFirstLaunch()
        AuthStubURLProtocol.respond(status: 200, json: Self.userJSON)
        let session = makeSession()
        await session.signIn(email: "  ADA@Example.com ", password: "a-good-password")

        let loginBody = AuthStubURLProtocol.capturedRequests
            .first { $0.url?.path == "/auth/login" }
        XCTAssertTrue(AuthStubURLProtocol.capturedBody(loginBody)
            .starts(with: Data("username=ada%40example.com".utf8)))
    }

    func testWrongPasswordLeavesTheUserSignedOutWithAMessage() async {
        markNotFirstLaunch()
        AuthStubURLProtocol.respond(status: 401,
                                    json: #"{"detail":"Could not validate credentials"}"#)
        let session = makeSession()
        await session.signIn(email: "ada@example.com", password: "wrong-password")

        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertEqual(session.failure?.kind, .invalidCredentials)
        XCTAssertNil(store.load())
        XCTAssertTrue(session.shouldPresentGate, "a failed sign-in must not dismiss the gate")
    }

    /// Caught before the request leaves, so there is no round trip to a cold-starting server
    /// just to be told the address has no "@" in it.
    func testInvalidEmailIsRejectedWithoutAnyRequest() async {
        markNotFirstLaunch()
        let session = makeSession()
        await session.signIn(email: "not-an-email", password: "a-good-password")

        XCTAssertEqual(session.failure?.kind, .rejectedInput)
        XCTAssertTrue(AuthStubURLProtocol.capturedRequests.isEmpty)
    }

    func testShortPasswordIsRejectedWithoutAnyRequest() async {
        markNotFirstLaunch()
        let session = makeSession()
        await session.signIn(email: "ada@example.com", password: "short")

        XCTAssertEqual(session.failure?.kind, .rejectedInput)
        XCTAssertTrue(AuthStubURLProtocol.capturedRequests.isEmpty)
    }

    /// Signed in for this launch, but the session will not survive a restart — a different
    /// thing from a failure, and worth saying rather than letting the app appear to forget.
    func testKeychainFailureStillSignsInButWarns() async {
        markNotFirstLaunch()
        let token = liveToken!
        AuthStubURLProtocol.respond { request in
            request.url?.path == "/auth/login"
                ? .init(statusCode: 200,
                        body: Data(#"{"access_token":"\#(token)","token_type":"bearer"}"#.utf8),
                        error: nil)
                : .init(statusCode: 200, body: Data(Self.userJSON.utf8), error: nil)
        }

        let session = makeSession(store: FailingTokenStore())
        await session.signIn(email: "ada@example.com", password: "a-good-password")

        XCTAssertTrue(session.state.isSignedIn)
        XCTAssertNil(session.failure)
        XCTAssertNotNil(session.persistenceWarning)
    }

    // MARK: - Register

    /// /auth/register answers 201 with a UserPublic and NO token, so signing up is
    /// register-then-login. The user object from the first call is reused rather than
    /// fetching /auth/me again.
    func testRegisterCreatesTheAccountThenLogsInWithoutCallingMe() async {
        markNotFirstLaunch()
        let token = liveToken!
        AuthStubURLProtocol.respond { request in
            switch request.url?.path {
            case "/auth/register":
                return .init(statusCode: 201, body: Data(Self.userJSON.utf8), error: nil)
            case "/auth/login":
                return .init(statusCode: 200,
                             body: Data(#"{"access_token":"\#(token)","token_type":"bearer"}"#.utf8),
                             error: nil)
            default:
                return .init(statusCode: 500, body: Data(), error: nil)
            }
        }

        let session = makeSession()
        await session.register(email: "ada@example.com", password: "a-good-password")

        XCTAssertEqual(session.state.user?.id, "u-1")
        XCTAssertEqual(store.load(), liveToken)
        XCTAssertEqual(AuthStubURLProtocol.capturedRequests.compactMap { $0.url?.path },
                       ["/auth/register", "/auth/login"])
    }

    func testDuplicateEmailIsReportedAndNothingIsStored() async {
        markNotFirstLaunch()
        AuthStubURLProtocol.respond(status: 409,
                                    json: #"{"detail":"That email address is already registered."}"#)
        let session = makeSession()
        await session.register(email: "ada@example.com", password: "a-good-password")

        XCTAssertEqual(session.failure?.kind, .emailAlreadyRegistered)
        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertNil(store.load())
    }

    // MARK: - Refresh

    /// The backend re-reads the user on every request, so a deleted account stops working
    /// immediately. This is how the app finds out.
    func testRefreshSignsOutWhenTheServerRejectsTheToken() async throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()
        let session = makeSession()
        session.restore()
        XCTAssertTrue(session.state.isSignedIn)

        AuthStubURLProtocol.respond(status: 401,
                                    json: #"{"detail":"Could not validate credentials"}"#)
        await session.refresh()

        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertNil(store.load())
    }

    /// Being offline must NOT sign anyone out. Losing your session because a train went into a
    /// tunnel is the kind of thing people never forgive an app for.
    func testRefreshKeepsTheSessionWhenTheNetworkIsDown() async throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()
        let session = makeSession()
        session.restore()

        for error in [URLError(.notConnectedToInternet), URLError(.timedOut)] {
            AuthStubURLProtocol.fail(with: error)
            await session.refresh()
            XCTAssertTrue(session.state.isSignedIn, "signed out on \(error.code)")
            XCTAssertEqual(store.load(), liveToken)
        }
    }

    /// A 500 is the server's problem, not a reason to throw away a valid session.
    func testRefreshKeepsTheSessionOnAServerError() async throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()
        let session = makeSession()
        session.restore()

        AuthStubURLProtocol.respond(status: 500, json: #"{"detail":"boom"}"#)
        await session.refresh()
        XCTAssertTrue(session.state.isSignedIn)
    }

    func testRefreshPicksUpAChangedEmail() async throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()
        let session = makeSession()
        session.restore()

        AuthStubURLProtocol.respond(status: 200, json: #"""
        {"id":"u-1","email":"ada.lovelace@example.com","created_at":"2026-09-16T05:33:58.567000Z"}
        """#)
        await session.refresh()
        XCTAssertEqual(session.state.user?.email, "ada.lovelace@example.com")
    }

    func testRefreshDoesNothingWhenSignedOut() async {
        markNotFirstLaunch()
        let session = makeSession()
        session.restore()
        await session.refresh()
        XCTAssertTrue(AuthStubURLProtocol.capturedRequests.isEmpty)
    }

    // MARK: - Sign out

    func testSignOutClearsEverything() async throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()
        let session = makeSession()
        session.restore()

        session.signOut()

        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertNil(session.token)
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.data(forKey: AuthSession.cachedUserKey))
    }

    /// A relaunch after signing out must not resurrect the account.
    func testSignOutSurvivesARelaunch() async throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()
        let session = makeSession()
        session.restore()
        session.signOut()

        let relaunched = makeSession()
        relaunched.restore()
        XCTAssertFalse(relaunched.state.isSignedIn)
    }

    // MARK: -

    private func seedCachedUser() throws {
        let user = AuthenticatedUser(id: "u-1", email: "ada@example.com",
                                     createdAt: Date(timeIntervalSince1970: 1789536838))
        defaults.set(try JSONEncoder.authCache.encode(user), forKey: AuthSession.cachedUserKey)
    }
}

// MARK: - Restoring at construction

/// `AuthSession` restores in its initialiser so the first frame a view renders is already the
/// right one — restoring from `.task` runs after that frame, and a signed-in user would watch
/// the gate cross-fade away on every launch. These pin the two properties that makes rely on.
extension AuthSessionTests {

    func testConstructionAloneRestoresTheSession() throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()

        // No restore() call. If this fails, RootView's first frame shows the wrong screen.
        let session = makeSession()

        XCTAssertTrue(session.state.isSignedIn)
        XCTAssertFalse(session.shouldPresentGate)
    }

    /// Construction restores, and the tests (and any caller) may still call restore()
    /// explicitly. Doing both must not purge, sign anyone out, or double-count a write.
    func testRestoreIsIdempotent() throws {
        markNotFirstLaunch()
        try store.save(liveToken)
        try seedCachedUser()

        let session = makeSession()
        let savesAfterConstruction = store.saveCount
        session.restore()
        session.restore()

        XCTAssertTrue(session.state.isSignedIn)
        XCTAssertEqual(session.token?.raw, liveToken)
        XCTAssertEqual(store.saveCount, savesAfterConstruction,
                       "restore() must not write the token back")
    }

    /// The first-launch purge still fires exactly once even though construction now restores.
    func testPurgeStillHappensOnceWhenConstructionRestores() throws {
        try store.save(liveToken)
        try seedCachedUser()

        let session = makeSession()          // purges during init
        XCTAssertFalse(session.state.isSignedIn)

        try store.save(liveToken)       // a later, legitimate sign-in
        try seedCachedUser()
        session.restore()
        XCTAssertTrue(session.state.isSignedIn, "the purge must not fire a second time")
    }
}
