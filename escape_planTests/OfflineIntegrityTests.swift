//  OfflineIntegrityTests.swift
//  The architectural claim, under test: routing is deterministic and the AI layer is
//  separable, so the app degrades honestly with the network off instead of dead-ending.
//
//  Four things are asserted here, and each one is a bug the app actually had:
//
//  1. A connection-class failure serves the last-good `/routes` plan, so a drill or an export
//     still has a route to walk. (Only HouseScreen did this; the old DrillScreen dead-ended.)
//  2. A 401 or a 422 is NEVER masked by that cache. Falling back on a server *answer* would
//     hide a wrong bearer token behind a stale plan that looks like it worked.
//  3. A 502 (an operator must act — no credit, bad key) offers no Retry, while a 503 (busy)
//     does. Three screens flattened `BackendFailure` to `.message` and lost that distinction.
//  4. The offline notice names *when* the cached plan was saved, so nobody mistakes a
//     three-week-old plan for a fresh one.
//
//  The transport is stubbed at `URLProtocol`, which `URLSession.shared` consults — the same
//  session `APIClient+Routes` uses. Serialized, because that registration is process-global.
//
//  What is deliberately NOT here: any assertion that the app produces a route, a score or a
//  timeline while offline. It cannot, and must not pretend to.

import Foundation
import Testing

@testable import escape_plan

/// Intercepts every request while a responder is installed. Absent a responder it declines,
/// so an escaped registration can never silently swallow another suite's traffic.
final class OfflineStubProtocol: URLProtocol {
    /// Serialized suite + install/remove in the same test body, so this is only ever touched
    /// by one test at a time.
    static var responder: ((URLRequest) -> Result<(HTTPURLResponse, Data), Error>)?

    static func install(_ responder: @escaping (URLRequest) -> Result<(HTTPURLResponse, Data), Error>) {
        Self.responder = responder
        URLProtocol.registerClass(Self.self)
    }

    static func remove() {
        URLProtocol.unregisterClass(Self.self)
        responder = nil
    }

    /// Answers `status` with `body` for any request.
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

@Suite("Offline integrity", .serialized)
struct OfflineIntegrityTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // escape_planTests/
        .deletingLastPathComponent()  // repo root

    /// A real `/routes` response, committed as a sample. Never a hand-written plan: the cache
    /// is only ever allowed to hold engine output.
    private func samplePlan() throws -> RoutePlan {
        let url = Self.repoRoot
            .appendingPathComponent("docs/route-samples/twostory.routeplan.json")
        return try HomeModel.decoder.decode(RoutePlan.self, from: Data(contentsOf: url))
    }

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineIntegrity-\(UUID().uuidString)", isDirectory: true)
    }

    /// An APIClient on a throwaway defaults suite, so a test never rewrites the real
    /// base URL or bearer token.
    private func makeClient() -> APIClient {
        let defaults = UserDefaults(suiteName: "OfflineIntegrityTests-\(UUID().uuidString)")!
        let client = APIClient(defaults: defaults)
        client.baseURL = URL(string: "https://offline-integrity.test")!
        client.bearerToken = "test-token"
        return client
    }

    // MARK: - 1. The cache carries the deterministic half through an outage

    @Test("A connection failure serves the last-good plan instead of a dead end")
    func cachedPlanServedWhenOffline() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let plan = try samplePlan()
        let savedAt = Date(timeIntervalSince1970: 1_770_000_000)
        try cache.save(plan, now: savedAt)

        let home = try FixtureLoader.load(.twostory)
        OfflineStubProtocol.installFailure(URLError(.notConnectedToInternet))
        defer { OfflineStubProtocol.remove() }

        let result = try await makeClient().fetchRoutesCached(home: home, cache: cache)
        guard case .cached(let cached) = result else {
            Issue.record("expected the cached plan, got a live one")
            return
        }
        #expect(cached.plan.rooms.count == plan.rooms.count)
        #expect(cached.savedAt.timeIntervalSince1970 == savedAt.timeIntervalSince1970)
    }

    @Test("An empty cache offline rethrows — it never invents a plan")
    func emptyCacheOfflineRethrows() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)

        OfflineStubProtocol.installFailure(URLError(.notConnectedToInternet))
        defer { OfflineStubProtocol.remove() }

        await #expect(throws: URLError.self) {
            _ = try await self.makeClient().fetchRoutesCached(home: home, cache: cache)
        }
    }

    @Test("A live fetch fills the cache, so the NEXT outage has something real to serve")
    func liveFetchPopulatesCache() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let plan = try samplePlan()
        let body = try HomeModel.encoder().encode(plan)

        let home = try FixtureLoader.load(.twostory)
        OfflineStubProtocol.installStatus(200, body: body)
        defer { OfflineStubProtocol.remove() }

        let result = try await makeClient().fetchRoutesCached(home: home, cache: cache)
        guard case .live(let live) = result else {
            Issue.record("a 200 must produce a live plan")
            return
        }
        #expect(live.home_id == plan.home_id)
        #expect(cache.load(homeID: plan.home_id)?.plan.rooms.count == plan.rooms.count,
                "the cache is filled only from real /routes responses")
    }

    // MARK: - 2. A server ANSWER is never masked by the cache

    @Test("A 401 is not masked by a populated cache")
    func unauthorizedIsNotMasked() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        try cache.save(try samplePlan(), now: Date())

        let home = try FixtureLoader.load(.twostory)
        OfflineStubProtocol.installStatus(401)
        defer { OfflineStubProtocol.remove() }

        do {
            _ = try await makeClient().fetchRoutesCached(home: home, cache: cache)
            Issue.record("a 401 must surface — falling back would hide a bad bearer token")
        } catch APIClientError.unexpectedResponse(let statusCode) {
            #expect(statusCode == 401)
        }
    }

    @Test("A 422 is not masked by a populated cache")
    func rejectedInputIsNotMasked() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        try cache.save(try samplePlan(), now: Date())

        let home = try FixtureLoader.load(.twostory)
        OfflineStubProtocol.installStatus(422)
        defer { OfflineStubProtocol.remove() }

        do {
            _ = try await makeClient().fetchRoutesCached(home: home, cache: cache)
            Issue.record("a 422 means the model we sent is unusable — a stale plan hides that")
        } catch APIClientError.unexpectedResponse(let statusCode) {
            #expect(statusCode == 422)
        }
    }

    @Test("Only connection-class errors are eligible for the fallback")
    func fallbackEligibility() {
        #expect(APIClient.isConnectionFailure(URLError(.notConnectedToInternet)))
        #expect(APIClient.isConnectionFailure(URLError(.dnsLookupFailed)))
        #expect(APIClient.isConnectionFailure(APIClientError.unexpectedResponse(statusCode: 401))
                == false)
        #expect(APIClient.isConnectionFailure(APIClientError.unexpectedResponse(statusCode: 502))
                == false)
    }

    // MARK: - 3. 502 vs 503, on every operation a screen actually uses

    @Test("502 never offers Retry, on any operation")
    func operatorMustActIsNotRetryable() {
        let operations: [BackendFailure.Operation] =
            [.routes, .scanConversion, .score, .analysis, .assistant, .simulation, .houseBuilder]
        for operation in operations {
            let failure = BackendFailure(
                APIClientError.unexpectedResponse(statusCode: 502), while: operation)
            #expect(failure.kind == .aiUnavailable)
            #expect(failure.isRetryable == false,
                    "502 means a human must change something; Retry provably cannot help")
        }
    }

    @Test("503 always offers Retry, on any operation")
    func serverBusyIsRetryable() {
        let operations: [BackendFailure.Operation] =
            [.routes, .scanConversion, .score, .analysis, .assistant, .simulation, .houseBuilder]
        for operation in operations {
            let failure = BackendFailure(
                APIClientError.unexpectedResponse(statusCode: 503), while: operation)
            #expect(failure.kind == .serverBusy)
            #expect(failure.isRetryable, "503 is exactly the case where retrying is right")
        }
    }

    @Test("The new operations say honestly what still works when they fail")
    func newOperationsNameTheirFallback() {
        let simulation = BackendFailure(
            APIClientError.unexpectedResponse(statusCode: 502), while: .simulation)
        #expect(simulation.message.contains("saved escape routes are unchanged"))

        let builder = BackendFailure(
            APIClientError.unexpectedResponse(statusCode: 502), while: .houseBuilder)
        #expect(builder.message.contains("3D editor"),
                "the editor is entirely local, so it is an honest thing to point at")

        // …and routing itself has nothing to promise, so it promises nothing.
        let routes = BackendFailure(
            APIClientError.unexpectedResponse(statusCode: 502), while: .routes)
        #expect(routes.message.contains("still") == false)
    }

    // MARK: - 4. The offline notice is specific about age

    @Test("The cached-routes notice names when the plan was saved")
    func cachedNoticeNamesItsDate() {
        let savedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let failure = BackendFailure.showingCachedRoutes(savedAt: savedAt)

        #expect(failure.kind == .offline)
        #expect(failure.isOfflineFlavoured)
        // The exact string is locale-dependent; what matters is that the stamp is IN it, so a
        // three-week-old plan can never read as a fresh one.
        let stamp = savedAt.formatted(date: .abbreviated, time: .shortened)
        #expect(failure.message.contains(stamp))
        #expect(failure.isRetryable, "the user can still try for live routes")
    }

    @Test("Offline is a state, not a fault — and it says what still works")
    func offlineReadsAsAState() {
        let failure = BackendFailure(URLError(.notConnectedToInternet), while: .routes)
        #expect(failure.isOfflineFlavoured)
        #expect(failure.symbol == "wifi.slash")

        // The capability note is the honest inventory shown beside such a banner. The editor,
        // saved homes and the printable plan have no APIClient anywhere in their path. The fire
        // drill is the `/evacuate` simulation since trim 2 (2026-10-03), so it needs the server
        // and must not be promised offline.
        #expect(OfflineCapabilityNote.worksOffline.contains("printable escape plan"))
        #expect(!OfflineCapabilityNote.worksOffline.contains("drill"))
        #expect(OfflineCapabilityNote.needsServer.contains("fire drill"))
        #expect(OfflineCapabilityNote.needsServer.contains("escape routes"))
        #expect(OfflineCapabilityNote.needsServer.contains("preparedness score"))
        #expect(OfflineCapabilityNote.needsServer.contains("assistant"))
    }
}
