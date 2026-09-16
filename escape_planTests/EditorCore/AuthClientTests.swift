//  AuthClientTests.swift — the /auth wire contract, from the client side.
//
//  These run in the SwiftPM package (no simulator needed) because AuthClient takes its
//  URLSession as a dependency. That is the entire reason it does, and why this layer is not
//  another body of Swift waiting on a device to be checked.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class AuthClientTests: XCTestCase {

    private var client: AuthClient!

    override func setUp() {
        super.setUp()
        AuthStubURLProtocol.reset()
        client = AuthClient(baseURL: URL(string: "https://backend.example.com")!,
                            session: AuthStubURLProtocol.makeSession())
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    private static let userJSON = #"""
    {"id":"u-1","email":"ada@example.com","created_at":"2026-09-16T05:33:58.567000Z"}
    """#

    private static let tokenJSON = #"""
    {"access_token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLWFiYy0xMjMiLCJpYXQiOjE3ODk1MzcxNDEsImV4cCI6MTc4OTU0MDc0MX0.1jeLV6so2LE7_DrvW62MJ2RmMm_QkWBUkAxzK_-HHPk","token_type":"bearer"}
    """#

    // MARK: - register

    func testRegisterPostsJSONToTheRightPath() async throws {
        AuthStubURLProtocol.respond(status: 201, json: Self.userJSON)
        _ = try await client.register(email: "ada@example.com", password: "a-good-password")

        let request = try XCTUnwrap(AuthStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/auth/register")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: AuthStubURLProtocol.capturedBody(request)) as? [String: Any])
        XCTAssertEqual(body["email"] as? String, "ada@example.com")
        XCTAssertEqual(body["password"] as? String, "a-good-password")
    }

    /// Register answers 201, not 200. A `== 200` check would turn every successful signup into
    /// an error, and it is the kind of thing that looks right in review.
    func testRegisterAccepts201() async throws {
        AuthStubURLProtocol.respond(status: 201, json: Self.userJSON)
        let user = try await client.register(email: "ada@example.com", password: "a-good-password")
        XCTAssertEqual(user.email, "ada@example.com")
        XCTAssertEqual(user.id, "u-1")
    }

    /// The shared BACKEND_BEARER_TOKEN guards the deterministic endpoints; the cloud endpoints
    /// use a per-user JWT and api_auth.py deliberately does not layer the two. Sending a
    /// bearer header here would work today and break when that stops being true.
    func testRegisterDoesNotSendAnAuthorizationHeader() async throws {
        AuthStubURLProtocol.respond(status: 201, json: Self.userJSON)
        _ = try await client.register(email: "ada@example.com", password: "a-good-password")
        XCTAssertNil(AuthStubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testRegisterMapsDuplicateEmailTo409() async {
        AuthStubURLProtocol.respond(status: 409,
                                    json: #"{"detail":"That email address is already registered."}"#)
        await assertFails(kind: .emailAlreadyRegistered) {
            _ = try await self.client.register(email: "ada@example.com", password: "a-good-password")
        }
    }

    func testRegisterMapsValidationErrorTo422() async {
        AuthStubURLProtocol.respond(status: 422, json: #"""
        {"detail":[{"type":"string_too_short","loc":["body","password"],
         "msg":"String should have at least 8 characters","input":"short","ctx":{"min_length":8}}]}
        """#)
        await assertFails(kind: .rejectedInput) {
            _ = try await self.client.register(email: "ada@example.com", password: "short")
        }
    }

    // MARK: - login

    /// The whole reason FormURLEncoding exists, asserted end to end through the client.
    func testLoginSendsFormEncodedBodyWithUsernameField() async throws {
        AuthStubURLProtocol.respond(status: 200, json: Self.tokenJSON)
        _ = try await client.login(email: "ada@example.com", password: "a+password")

        let request = try XCTUnwrap(AuthStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/auth/login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        XCTAssertEqual(AuthStubURLProtocol.lastBodyString,
                       "username=ada%40example.com&password=a%2Bpassword")
    }

    func testLoginReturnsAParsedToken() async throws {
        AuthStubURLProtocol.respond(status: 200, json: Self.tokenJSON)
        let token = try await client.login(email: "ada@example.com", password: "pw")
        XCTAssertEqual(token.subject, "user-abc-123")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 1789540741))
        XCTAssertTrue(token.raw.hasPrefix("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."))
    }

    func testLoginMapsWrongPasswordTo401() async {
        AuthStubURLProtocol.respond(status: 401,
                                    json: #"{"detail":"Could not validate credentials"}"#)
        await assertFails(kind: .invalidCredentials) {
            _ = try await self.client.login(email: "ada@example.com", password: "wrong")
        }
    }

    /// What a login gets from a deployment with no MONGODB_URI — captured from the real
    /// backend, 2026-09-15.
    func testLoginMapsUnconfiguredServerTo503() async {
        AuthStubURLProtocol.respond(status: 503,
                                    json: #"{"detail":"Cloud sync is not configured on this server."}"#)
        await assertFails(kind: .cloudSyncUnavailable) {
            _ = try await self.client.login(email: "ada@example.com", password: "pw")
        }
    }

    // MARK: - me

    func testMeSendsTheBearerTokenVerbatim() async throws {
        AuthStubURLProtocol.respond(status: 200, json: Self.userJSON)
        let raw = "header.payload.signature"
        _ = try await client.me(token: AccessToken(raw: raw))

        let request = try XCTUnwrap(AuthStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.path, "/auth/me")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(raw)")
    }

    func testMeMapsRejectedTokenTo401() async {
        AuthStubURLProtocol.respond(status: 401,
                                    json: #"{"detail":"Could not validate credentials"}"#)
        await assertFails(kind: .invalidCredentials) {
            _ = try await self.client.me(token: AccessToken(raw: "stale.token.here"))
        }
    }

    // MARK: - Transport and malformed responses

    func testOfflineBecomesAnOfflineFailure() async {
        AuthStubURLProtocol.fail(with: URLError(.notConnectedToInternet))
        await assertFails(kind: .offline) {
            _ = try await self.client.login(email: "a@b.co", password: "pw")
        }
    }

    func testTimeoutBecomesATimeoutFailure() async {
        AuthStubURLProtocol.fail(with: URLError(.timedOut))
        await assertFails(kind: .timedOut) {
            _ = try await self.client.login(email: "a@b.co", password: "pw")
        }
    }

    /// A 200 whose body is not what we expect must surface as a failure the user can see —
    /// never a crash, and never a silently empty account.
    func testSuccessWithAnUnreadableBodyIsAFailureNotACrash() async {
        AuthStubURLProtocol.respond(status: 200, json: #"{"unexpected":"shape"}"#)
        await assertFails(kind: .server(statusCode: -1)) {
            _ = try await self.client.login(email: "a@b.co", password: "pw")
        }
    }

    /// Every error out of this client is an AuthFailure, so no caller has to interpret a
    /// status code or a URLError itself.
    private func assertFails(kind: AuthFailure.Kind,
                             file: StaticString = #filePath, line: UInt = #line,
                             _ operation: @escaping () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("expected \(kind)", file: file, line: line)
        } catch let failure as AuthFailure {
            XCTAssertEqual(failure.kind, kind, file: file, line: line)
        } catch {
            XCTFail("expected AuthFailure, got \(error)", file: file, line: line)
        }
    }
}
