//  CloudHomesClientTests.swift — the /homes wire contract, from the client side.
//
//  These run in the SwiftPM package (no simulator needed) because `CloudHomesClient` takes its
//  URLSession as a dependency, the same arrangement `AuthClient` uses. That is the entire
//  reason it does: without it, the only code that talks to the cloud endpoints would be
//  another body of Swift waiting on a device to be checked.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class CloudHomesClientTests: XCTestCase {

    private var client: CloudHomesClient!
    private var token: AccessToken!
    private var home: HomeModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        AuthStubURLProtocol.reset()
        client = CloudHomesClient(baseURL: URL(string: "https://backend.example.com")!,
                                  session: AuthStubURLProtocol.makeSession())
        token = makeTestToken()
        home = try Fixtures.load("bungalow")
    }

    override func tearDown() {
        AuthStubURLProtocol.reset()
        client = nil
        super.tearDown()
    }

    private func storedJSON(id: String = "srv-1", revision: Int = 1) throws -> String {
        let homeJSON = String(decoding: try HomeModel.encoder().encode(home), as: UTF8.self)
        return """
        {"id":"\(id)","user_id":"u-1","home":\(homeJSON),"revision":\(revision),\
        "created_at":"2026-09-16T05:33:58.567000Z","updated_at":"2026-09-16T06:00:00Z"}
        """
    }

    // MARK: - The request

    func testListHitsTheHomesRouteWithTheJWT() async throws {
        AuthStubURLProtocol.respond(status: 200, json: "[]")
        _ = try await client.list(token: token)

        let request = try XCTUnwrap(AuthStubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/homes")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token.raw)")
    }

    func testPushSendsTheHomeAsJSONWithNoRevisionField() async throws {
        AuthStubURLProtocol.respond(status: 201, json: try storedJSON())
        _ = try await client.push(home, remoteID: nil, token: token)

        let request = try XCTUnwrap(AuthStubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/homes")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = AuthStubURLProtocol.capturedBody(request)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(object["home"])
        // `revision` is server-owned. Sending one would be rejected outright — the backend's
        // HomeSyncRequest sets extra="forbid" — so this is a 422 waiting to happen, not a
        // harmless extra key.
        XCTAssertNil(object["revision"])
    }

    /// Creating must OMIT `home_id` rather than send `null`. Both validate against the
    /// backend today, but the omission is what the contract describes and the difference is
    /// free to get right.
    func testCreatingOmitsTheHomeIDKeyEntirely() async throws {
        AuthStubURLProtocol.respond(status: 201, json: try storedJSON())
        _ = try await client.push(home, remoteID: nil, token: token)

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: AuthStubURLProtocol.capturedBody(AuthStubURLProtocol.lastRequest)) as? [String: Any])
        XCTAssertFalse(object.keys.contains("home_id"))
    }

    func testUpdatingSendsTheServerRecordID() async throws {
        AuthStubURLProtocol.respond(status: 201, json: try storedJSON(id: "srv-42", revision: 6))
        let stored = try await client.push(home, remoteID: "srv-42", token: token)

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: AuthStubURLProtocol.capturedBody(AuthStubURLProtocol.lastRequest)) as? [String: Any])
        XCTAssertEqual(object["home_id"] as? String, "srv-42")
        XCTAssertEqual(stored.revision, 6, "the revision must come from the server, not the client")
    }

    /// The body must be the home the caller handed over, byte-for-byte in VALUE — a client
    /// that quietly re-stamped `meta.modified` before sending would break last-write-wins.
    func testTheBodyCarriesTheHomeUnchanged() async throws {
        AuthStubURLProtocol.respond(status: 201, json: try storedJSON())
        _ = try await client.push(home, remoteID: nil, token: token)

        struct Sent: Decodable { let home: HomeModel }
        let sent = try HomeModel.decoder.decode(
            Sent.self, from: AuthStubURLProtocol.capturedBody(AuthStubURLProtocol.lastRequest))
        XCTAssertEqual(sent.home, home)
    }

    // MARK: - The response

    func testListDecodesTheServersPlainIDNotMongosUnderscoreID() async throws {
        AuthStubURLProtocol.respond(status: 200, json: "[\(try storedJSON(id: "srv-7", revision: 3))]")
        let homes = try await client.list(token: token)

        XCTAssertEqual(homes.count, 1)
        XCTAssertEqual(homes[0].id, "srv-7")
        XCTAssertEqual(homes[0].revision, 3)
        XCTAssertEqual(homes[0].localHomeID, home.home_id,
                       "the schema home_id is what local and remote are matched on")
        XCTAssertEqual(homes[0].home, home)
    }

    func testAnEmptyLibraryDecodesAsNoHomesRatherThanFailing() async throws {
        AuthStubURLProtocol.respond(status: 200, json: "[]")
        let homes = try await client.list(token: token)
        XCTAssertTrue(homes.isEmpty)
    }

    /// If the backend ever regresses to serialising by alias, decoding fails HERE with a
    /// readable error rather than silently producing empty ids that match nothing.
    func testAResponseKeyedByUnderscoreIDFailsLoudly() async throws {
        let homeJSON = String(decoding: try HomeModel.encoder().encode(home), as: UTF8.self)
        AuthStubURLProtocol.respond(status: 200, json: """
        [{"_id":"srv-1","user_id":"u-1","home":\(homeJSON),"revision":1,\
        "created_at":"2026-09-16T05:33:58Z","updated_at":"2026-09-16T06:00:00Z"}]
        """)
        await assertFails(kind: .unreadableResponse) { try await self.client.list(token: self.token) }
    }

    // MARK: - Failures

    func testUnauthorizedIsASessionExpiryNotAWrongPassword() async throws {
        AuthStubURLProtocol.respond(status: 401)
        await assertFails(kind: .sessionExpired) { try await self.client.list(token: self.token) }
    }

    func testTheSessionExpiryCaseIsTheOnlyOneThatDemandsReauthentication() {
        XCTAssertTrue(SyncFailure(statusCode: 401).requiresReauthentication)
        for status in [404, 422, 500, 503] {
            XCTAssertFalse(SyncFailure(statusCode: status).requiresReauthentication, "\(status)")
        }
    }

    func testAnUnknownHomeIDIsReportedAsAMissingHome() async throws {
        AuthStubURLProtocol.respond(status: 404)
        await assertFails(kind: .homeMissing) {
            try await self.client.push(self.home, remoteID: "srv-gone", token: self.token)
        }
    }

    func testAnUnconfiguredDeploymentIsNotReportedAsBusy() async throws {
        AuthStubURLProtocol.respond(status: 503)
        await assertFails(kind: .cloudSyncUnavailable) { try await self.client.list(token: self.token) }
        // Retrying forever will not set MONGODB_URI on someone else's server.
        XCTAssertFalse(SyncFailure(statusCode: 503).isRetryable)
    }

    func testARejectedHomeIsNotRetryable() {
        XCTAssertEqual(SyncFailure(statusCode: 422).kind, .rejectedByServer)
        XCTAssertFalse(SyncFailure(statusCode: 422).isRetryable)
    }

    func testBeingOfflineSaysTheHomesAreStillSafe() async throws {
        AuthStubURLProtocol.fail(with: URLError(.notConnectedToInternet))
        await assertFails(kind: .offline) { try await self.client.list(token: self.token) }
    }

    /// Render's free tier sleeps; the first request after an idle period can take most of a
    /// minute. Telling that user they are offline sends them to fix their wifi.
    func testATimeoutIsItsOwnCaseAndIsRetryable() async throws {
        AuthStubURLProtocol.fail(with: URLError(.timedOut))
        await assertFails(kind: .timedOut) { try await self.client.list(token: self.token) }
        XCTAssertTrue(SyncFailure(transport: URLError(.timedOut)).isRetryable)
    }

    func testAnUnexpectedStatusIsCarriedThroughWithItsCode() async throws {
        AuthStubURLProtocol.respond(status: 500)
        await assertFails(kind: .server(statusCode: 500)) { try await self.client.list(token: self.token) }
    }

    // MARK: - Helper

    private func assertFails(kind: SyncFailure.Kind,
                             file: StaticString = #filePath,
                             line: UInt = #line,
                             _ work: @escaping () async throws -> Any) async {
        do {
            _ = try await work()
            XCTFail("expected \(kind)", file: file, line: line)
        } catch let failure as SyncFailure {
            XCTAssertEqual(failure.kind, kind, file: file, line: line)
        } catch {
            XCTFail("expected a SyncFailure, got \(error)", file: file, line: line)
        }
    }
}
