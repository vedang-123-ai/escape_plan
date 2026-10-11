//  Audit_NetworkFallbackTests.swift
//  escape_planTests
//
//  Tests for audit findings X-02 (A10-02/A18-03), A06-02, and A10-05:
//  1. Gateway failures (proxy 502, upstream 502/503/504, timeouts) fall back to cached routes.
//  2. Stale/masked protection: 4xx (401, 403, 422) and empty/invalid cache miss rethrow without masking.
//  3. Cached routes expose savedAt timestamp and model match.
//  4. FastAPI 422 validation array decoding in chat client extracts actionable messages.

import Foundation
import Testing
@testable import escape_plan

final class AuditNetworkStubProtocol: URLProtocol {
    static var responder: ((URLRequest) -> Result<(HTTPURLResponse, Data), Error>)?

    static func install(_ responder: @escaping (URLRequest) -> Result<(HTTPURLResponse, Data), Error>) {
        Self.responder = responder
        URLProtocol.registerClass(Self.self)
    }

    static func remove() {
        URLProtocol.unregisterClass(Self.self)
        responder = nil
    }

    static func installStatus(_ status: Int, body: Data = Data()) {
        install { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return .success((response, body))
        }
    }

    static func installFailure(_ error: Error) {
        install { _ in .failure(error) }
    }

    override class func canInit(with request: URLRequest) -> Bool { responder != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        switch responder(request) {
        case .success(let (response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("Audit Network Fallback Tests", .serialized)
struct Audit_NetworkFallbackTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // escape_planTests/
        .deletingLastPathComponent()  // repo root

    private func samplePlan() throws -> RoutePlan {
        let url = Self.repoRoot
            .appendingPathComponent("docs/route-samples/twostory.routeplan.json")
        return try HomeModel.decoder.decode(RoutePlan.self, from: Data(contentsOf: url))
    }

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AuditNetworkFallback-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeClient() -> APIClient {
        let defaults = UserDefaults(suiteName: "AuditNetworkFallback-\(UUID().uuidString)")!
        let client = APIClient(defaults: defaults)
        client.baseURL = URL(string: "https://audit-network.test")!
        client.bearerToken = "test-token"
        return client
    }

    private func seed(_ cache: RoutePlanCache, _ plan: RoutePlan, home: HomeModel,
                      peril: String? = nil, profileID: String? = nil,
                      now: Date = Date()) throws {
        try cache.save(plan,
                       key: RoutePlanKey(homeID: home.home_id, peril: peril, profileID: profileID),
                       homeFingerprint: RoutePlanCache.fingerprint(of: home), now: now)
    }

    // MARK: - X-02: Classification Tests

    @Test("Classification: connection failure recognizes transport and proxy gateway drops")
    func connectionFailureClassification() {
        #expect(APIClient.isConnectionFailure(URLError(.notConnectedToInternet)))
        #expect(APIClient.isConnectionFailure(URLError(.timedOut)))
        #expect(APIClient.isConnectionFailure(URLError(.cannotConnectToHost)))
        #expect(APIClient.isConnectionFailure(URLError(.dnsLookupFailed)))
        #expect(APIClient.isConnectionFailure(APIClientError.gatewayFailure(statusCode: 502)))

        // Non-connection errors
        #expect(APIClient.isConnectionFailure(APIClientError.unexpectedResponse(statusCode: 401)) == false)
        #expect(APIClient.isConnectionFailure(APIClientError.unexpectedResponse(statusCode: 502)) == false)
        #expect(APIClient.isConnectionFailure(APIClientError.unexpectedResponse(statusCode: 500)) == false)
    }

    @Test("Classification: recoverable route failure includes connection, gateway and overload responses")
    func recoverableRouteFailureClassification() {
        #expect(APIClient.isRecoverableRouteFailure(URLError(.notConnectedToInternet)))
        #expect(APIClient.isRecoverableRouteFailure(URLError(.timedOut)))
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.gatewayFailure(statusCode: 502)))
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.unexpectedResponse(statusCode: 502)))
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.unexpectedResponse(statusCode: 503)))
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.unexpectedResponse(statusCode: 504)))

        // Client and auth errors must never be recoverable for cache fallback
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.unexpectedResponse(statusCode: 400)) == false)
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.unexpectedResponse(statusCode: 401)) == false)
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.unexpectedResponse(statusCode: 403)) == false)
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.unexpectedResponse(statusCode: 422)) == false)
        #expect(APIClient.isRecoverableRouteFailure(APIClientError.unexpectedResponse(statusCode: 500)) == false)
    }

    // MARK: - X-02: Route Cache Fallback on 502, 503, 504

    @Test("Proxy 502 (HTML response) falls back to populated cache")
    func proxy502FallsBackToCache() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        let savedDate = Date(timeIntervalSince1970: 1_770_500_000)
        try seed(cache, try samplePlan(), home: home, now: savedDate)

        AuditNetworkStubProtocol.installStatus(502, body: Data("<html><body>502 Bad Gateway</body></html>".utf8))
        defer { AuditNetworkStubProtocol.remove() }

        let result = try await makeClient().fetchRoutesCached(home: home, cache: cache)
        guard case .cached(let cached) = result else {
            Issue.record("proxy 502 must fall back to cached plan")
            return
        }
        #expect(cached.savedAt == savedDate)
        #expect(cached.plan.home_id == home.home_id)
    }

    @Test("HTTP 503 Service Unavailable falls back to populated cache")
    func http503FallsBackToCache() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        let savedDate = Date(timeIntervalSince1970: 1_770_500_000)
        try seed(cache, try samplePlan(), home: home, now: savedDate)

        AuditNetworkStubProtocol.installStatus(503, body: Data("Service Unavailable".utf8))
        defer { AuditNetworkStubProtocol.remove() }

        let result = try await makeClient().fetchRoutesCached(home: home, cache: cache)
        guard case .cached(let cached) = result else {
            Issue.record("503 must fall back to cached plan")
            return
        }
        #expect(cached.savedAt == savedDate)
    }

    @Test("HTTP 504 Gateway Timeout falls back to populated cache")
    func http504FallsBackToCache() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        let savedDate = Date(timeIntervalSince1970: 1_770_500_000)
        try seed(cache, try samplePlan(), home: home, now: savedDate)

        AuditNetworkStubProtocol.installStatus(504, body: Data("Gateway Timeout".utf8))
        defer { AuditNetworkStubProtocol.remove() }

        let result = try await makeClient().fetchRoutesCached(home: home, cache: cache)
        guard case .cached(let cached) = result else {
            Issue.record("504 must fall back to cached plan")
            return
        }
        #expect(cached.savedAt == savedDate)
    }

    @Test("Proxy 502 with cache miss rethrows gatewayFailure rather than swallowing")
    func proxy502CacheMissRethrows() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)

        AuditNetworkStubProtocol.installStatus(502, body: Data("<html><body>502 Bad Gateway</body></html>".utf8))
        defer { AuditNetworkStubProtocol.remove() }

        do {
            _ = try await makeClient().fetchRoutesCached(home: home, cache: cache)
            Issue.record("cache miss must rethrow proxy error")
        } catch let error as APIClientError {
            guard case .gatewayFailure(502) = error else {
                Issue.record("expected gatewayFailure(502), got \(error)")
                return
            }
        }
    }

    @Test("HTTP 401 and 422 are never masked by route cache")
    func authAndValidationNeverMasked() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        try seed(cache, try samplePlan(), home: home)

        for status in [401, 403, 422] {
            AuditNetworkStubProtocol.installStatus(status)
            defer { AuditNetworkStubProtocol.remove() }

            do {
                _ = try await makeClient().fetchRoutesCached(home: home, cache: cache)
                Issue.record("status \(status) must never fall back to cache")
            } catch APIClientError.unexpectedResponse(let code) {
                #expect(code == status)
            }
        }
    }

    // MARK: - A06-02: FastAPI 422 Detail Decoding Tests

    @Test("FastAPI 422 detail string decodes correctly")
    func decodeStringErrorDetail() {
        let json = Data(#"{"detail": "Conversation is 10,000 characters; send fewer turns."}"#.utf8)
        let detail = APIClient.decodeErrorDetail(from: json)
        #expect(detail == "Conversation is 10,000 characters; send fewer turns.")
    }

    @Test("FastAPI 422 validation array decodes and strips Value error prefix")
    func decodeArrayValidationErrorDetail() {
        let json = Data("""
        {
          "detail": [
            {
              "type": "value_error",
              "loc": ["body", "messages"],
              "msg": "Value error, conversation is 105,000 characters, over the maximum of 100,000. Send fewer earlier turns.",
              "input": {}
            }
          ]
        }
        """.utf8)
        let detail = APIClient.decodeErrorDetail(from: json)
        #expect(detail == "Conversation is 105,000 characters, over the maximum of 100,000. Send fewer earlier turns.")
    }

    @Test("FastAPI 422 standard field validation array decodes first item message")
    func decodeStandardValidationArray() {
        let json = Data("""
        {
          "detail": [
            {
              "type": "missing",
              "loc": ["body", "messages"],
              "msg": "field required"
            }
          ]
        }
        """.utf8)
        let detail = APIClient.decodeErrorDetail(from: json)
        #expect(detail == "Field required")
    }

    @Test("BackendFailure surfaces actionable 422 message for assistant")
    func backendFailureSurfacesDecodedChatDetail() {
        let actionableDetail = "Conversation is 105,000 characters, over the maximum of 100,000. Send fewer earlier turns."
        let chatError = ChatError.unexpectedStatus(statusCode: 422, detail: actionableDetail)
        let failure = BackendFailure(chatError, while: .assistant)

        #expect(failure.kind == .rejectedInput)
        #expect(failure.message == actionableDetail)
        #expect(failure.isRetryable == false)
    }
}
