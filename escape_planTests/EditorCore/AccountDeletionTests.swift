//  AccountDeletionTests.swift — S11.7's "delete my account and data", both halves.
//
//  Apple requires in-app account deletion wherever accounts exist. The rule this file exists
//  to defend is the OTHER half of that promise: deleting the account must not touch the homes
//  on this device. They predate the account, they work signed out, and erasing a user's floor
//  plans because they closed a backup account would be the worst failure this layer could
//  have — so `deleteAccount()` never goes near the document store, and the test below asserts
//  it through the only seam it has: what it does to the token store and the session.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class AccountDeletionTests: XCTestCase {

    private var store: InMemoryTokenStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var token: String!

    override func setUp() {
        super.setUp()
        AuthStubURLProtocol.reset()
        store = InMemoryTokenStore()
        suiteName = "deletion.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        token = Self.mintToken()
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil; store = nil; suiteName = nil; token = nil
        super.tearDown()
    }

    /// Minted, never pasted — see the note in `AuthSessionTests`: a literal token carries a
    /// fixed `exp` and schedules the suite to go red on a particular morning.
    private static func mintToken(expiresIn: TimeInterval = 3600) -> String {
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = base64URL(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let claims: [String: Any] = [
            "sub": "user-abc-123",
            "iat": Int(Date().timeIntervalSince1970),
            "exp": Int(Date().addingTimeInterval(expiresIn).timeIntervalSince1970),
        ]
        let payload = base64URL(try! JSONSerialization.data(withJSONObject: claims))
        return "\(header).\(payload).not-a-real-signature"
    }

    private static let userJSON = #"""
    {"id":"u-1","email":"ada@example.com","created_at":"2026-09-16T05:33:58.567000Z"}
    """#

    private func makeSession() -> AuthSession {
        AuthSession(client: AuthClient(baseURL: URL(string: "https://backend.example.com")!,
                                       session: AuthStubURLProtocol.makeSession()),
                    store: store,
                    defaults: defaults)
    }

    /// A session that has already signed in, so deletion has something to delete.
    private func signedInSession() async -> AuthSession {
        defaults.set(true, forKey: AuthSession.hasLaunchedKey)
        let token = self.token!
        AuthStubURLProtocol.respond { request in
            request.url?.path == "/auth/login"
                ? .init(statusCode: 200,
                        body: Data(#"{"access_token":"\#(token)","token_type":"bearer"}"#.utf8),
                        error: nil)
                : .init(statusCode: 200, body: Data(Self.userJSON.utf8), error: nil)
        }
        let session = makeSession()
        await session.signIn(email: "ada@example.com", password: "a-good-password")
        XCTAssertTrue(session.state.isSignedIn, "setup failed, not the test")
        return session
    }

    // MARK: - The wire contract

    func testTheClientSendsDeleteToAuthMeWithTheBearerToken() async throws {
        AuthStubURLProtocol.respond(status: 204, json: "")
        let client = AuthClient(baseURL: URL(string: "https://backend.example.com")!,
                                session: AuthStubURLProtocol.makeSession())
        try await client.deleteAccount(token: AccessToken(raw: token))

        let request = try XCTUnwrap(AuthStubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/auth/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token!)")
    }

    /// 204 carries no body. A client that decoded one would fail on every successful deletion
    /// and tell the user their account is still there.
    func testAnEmptyBodyOn204IsASuccess() async throws {
        AuthStubURLProtocol.respond(status: 204, json: "")
        let client = AuthClient(baseURL: URL(string: "https://backend.example.com")!,
                                session: AuthStubURLProtocol.makeSession())
        try await client.deleteAccount(token: AccessToken(raw: token))
    }

    func testAServerErrorIsAnAuthFailure() async {
        AuthStubURLProtocol.respond(status: 503, json: #"{"detail":"cloud sync off"}"#)
        let client = AuthClient(baseURL: URL(string: "https://backend.example.com")!,
                                session: AuthStubURLProtocol.makeSession())
        do {
            try await client.deleteAccount(token: AccessToken(raw: token))
            XCTFail("a 503 must not read as a deleted account")
        } catch let failure as AuthFailure {
            XCTAssertEqual(failure.kind, .cloudSyncUnavailable)
        } catch {
            XCTFail("expected an AuthFailure, got \(error)")
        }
    }

    // MARK: - The session transition

    func testDeletingEndsTheSessionAndErasesTheStoredToken() async {
        let session = await signedInSession()
        AuthStubURLProtocol.respond(status: 204, json: "")

        let deleted = await session.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertNil(session.token)
        XCTAssertNil(store.load(), "the token outlived the account it belonged to")
        XCTAssertNil(defaults.data(forKey: AuthSession.cachedUserKey))
        XCTAssertNil(session.failure)
        XCTAssertFalse(session.isWorking)
    }

    /// Same rule as `signOut()`, for the same reason: `shouldPresentGate` drives a root-level
    /// view swap, so re-arming it would tear down the whole app subtree and drop someone on a
    /// welcome screen the instant their deletion succeeded.
    func testDeletingDoesNotReArmTheAuthGate() async {
        let session = await signedInSession()
        AuthStubURLProtocol.respond(status: 204, json: "")

        _ = await session.deleteAccount()
        XCTAssertFalse(session.shouldPresentGate)
    }

    /// The user is being told their data is gone. "It probably worked" is not good enough, so
    /// a failure must leave them signed in, with a message, and nothing erased.
    func testAFailedDeletionKeepsTheSessionAndSaysWhy() async {
        let session = await signedInSession()
        AuthStubURLProtocol.respond(status: 503, json: #"{"detail":"cloud sync off"}"#)

        let deleted = await session.deleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertTrue(session.state.isSignedIn)
        XCTAssertEqual(session.failure?.kind, .cloudSyncUnavailable)
        XCTAssertEqual(store.load(), token, "a failed deletion must not drop the token")
    }

    func testAnOfflineDeletionFailsRatherThanPretending() async {
        let session = await signedInSession()
        AuthStubURLProtocol.fail(with: URLError(.notConnectedToInternet))

        let deleted = await session.deleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertTrue(session.state.isSignedIn)
        XCTAssertEqual(session.failure?.kind, .offline)
    }

    /// A 401 means the account is already gone — deleted from another device, or the token
    /// aged out. There is nothing left to delete, so ending the session locally is the right
    /// outcome, not an error the user can do nothing about.
    func testA401ReadsAsAlreadyDeleted() async {
        let session = await signedInSession()
        AuthStubURLProtocol.respond(status: 401,
                                    json: #"{"detail":"Could not validate credentials"}"#)

        let deleted = await session.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertFalse(session.state.isSignedIn)
        XCTAssertNil(store.load())
        XCTAssertNil(session.failure, "there is nothing for the user to fix")
    }

    func testDeletingWhileSignedOutDoesNothing() async {
        defaults.set(true, forKey: AuthSession.hasLaunchedKey)
        AuthStubURLProtocol.respond(status: 204, json: "")
        let session = makeSession()

        let deleted = await session.deleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertTrue(AuthStubURLProtocol.capturedRequests.isEmpty,
                      "a signed-out session must not call the server")
    }

    /// Double-tapping the button must delete once. The second call has no token left even if
    /// it did get through, but the guard is what stops two DELETEs racing.
    func testDeletingTwiceOnlyCallsTheServerOnce() async {
        let session = await signedInSession()
        AuthStubURLProtocol.respond(status: 204, json: "")

        _ = await session.deleteAccount()
        _ = await session.deleteAccount()

        let deletes = AuthStubURLProtocol.capturedRequests.filter { $0.httpMethod == "DELETE" }
        XCTAssertEqual(deletes.count, 1)
    }

    /// A reply that lands after the account is gone must not put the session back.
    ///
    /// Note what this does NOT pin: the `generation` bump inside `deleteAccount()`. Removing
    /// that bump leaves this test green, because `refresh()`'s own `state.isSignedIn` guard
    /// already rejects the late reply. Written down rather than dressed up — a test whose
    /// comment claims more than it checks is how a guard gets deleted in six months.
    func testALateRefreshCannotResurrectADeletedAccount() async {
        let session = await signedInSession()
        AuthStubURLProtocol.respond(status: 204, json: "")
        _ = await session.deleteAccount()

        // The server would 401 now, but pretend the old /auth/me reply arrives late.
        AuthStubURLProtocol.respond(status: 200, json: Self.userJSON)
        await session.refresh()

        XCTAssertFalse(session.state.isSignedIn)
    }
}
