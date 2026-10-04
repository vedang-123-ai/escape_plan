//  OfflineIntegrityTests.swift
//  The architectural claim, under test: routing is deterministic and the AI layer is
//  separable, so the app degrades honestly with the network off instead of dead-ending.
//
//  Five things are asserted here, and each one is a bug the app actually had:
//
//  1. A connection-class failure serves the last-good `/routes` plan, so House's routes dock
//     or an export still has a route. (The old DrillScreen dead-ended; it was deleted by
//     demo trim 2 on 2026-10-03.)
//  2. A 401 or a 422 is NEVER masked by that cache. Falling back on a server *answer* would
//     hide a wrong bearer token behind a stale plan that looks like it worked.
//  3. A 502 (an operator must act — no credit, bad key) offers no Retry, while a 503 (busy)
//     does. Three screens flattened `BackendFailure` to `.message` and lost that distinction.
//  4. The offline notice names *when* the cached plan was saved, so nobody mistakes a
//     three-week-old plan for a fresh one. Since S11.36 it also names the peril and person.
//  5. (S11.36, AUD-028) The cache was keyed by home alone, so offline it could serve the fire
//     plan for a tornado, another person's route, or a route through rooms since deleted.
//     Now an entry is served only for its own home, peril, person and exact model.
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

    /// Saves `plan` the way a live fetch would for this request: under its key, stamped with
    /// the fingerprint of `home`.
    private func seed(_ cache: RoutePlanCache, _ plan: RoutePlan, home: HomeModel,
                      peril: String? = nil, profileID: String? = nil,
                      now: Date = Date()) throws {
        try cache.save(plan,
                       key: RoutePlanKey(homeID: home.home_id, peril: peril, profileID: profileID),
                       homeFingerprint: RoutePlanCache.fingerprint(of: home), now: now)
    }

    /// The sample plan relabelled, as the engine would label it for that peril and person.
    private func relabelled(_ plan: RoutePlan, peril: String?, profileID: String?) -> RoutePlan {
        var copy = plan
        copy.peril = peril
        copy.profile_id = profileID
        return copy
    }

    /// Runs one offline `fetchRoutesCached`; nil when it rethrew the connection failure.
    private func offlineLookup(_ cache: RoutePlanCache, home: HomeModel,
                               peril: String? = nil, profileID: String? = nil) async throws
        -> CachedRoutePlan? {
        OfflineStubProtocol.installFailure(URLError(.notConnectedToInternet))
        defer { OfflineStubProtocol.remove() }
        do {
            let result = try await makeClient().fetchRoutesCached(
                home: home, peril: peril, profileID: profileID, cache: cache)
            guard case .cached(let cached) = result else {
                Issue.record("offline can only ever produce a cached plan")
                return nil
            }
            return cached
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet, "a miss rethrows the connection failure")
            return nil
        }
    }

    @Test("A connection failure serves the last-good plan instead of a dead end")
    func cachedPlanServedWhenOffline() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let plan = try samplePlan()
        let savedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let home = try FixtureLoader.load(.twostory)
        try seed(cache, plan, home: home, now: savedAt)

        let cached = try #require(try await offlineLookup(cache, home: home),
                                  "an exact match (same home, fire, household, unedited) is a hit")
        #expect(cached.plan.rooms.count == plan.rooms.count)
        #expect(cached.savedAt.timeIntervalSince1970 == savedAt.timeIntervalSince1970)
        // Asking for fire by name is the same request as asking for nothing.
        #expect(try await offlineLookup(cache, home: home, peril: "fire") != nil)
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
        let hit = cache.load(RoutePlanKey(homeID: home.home_id),
                             homeFingerprint: RoutePlanCache.fingerprint(of: home))
        #expect(hit?.plan.rooms.count == plan.rooms.count,
                "the cache is filled only from real /routes responses")
    }

    // MARK: - 1b. S11.36: a cached plan is only ever served for what it was computed for

    @Test("Tornado requested with only a fire plan cached is a miss")
    func otherPerilIsAMiss() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        try seed(cache, try samplePlan(), home: home)  // fire

        #expect(try await offlineLookup(cache, home: home, peril: "tornado") == nil)
        #expect(try await offlineLookup(cache, home: home, peril: "earthquake") == nil)
    }

    @Test("Each peril keeps its own plan, and a live fetch for one never overwrites another")
    func perilsDoNotShareAnEntry() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        let fire = try samplePlan()
        let tornado = relabelled(fire, peril: "tornado", profileID: nil)

        OfflineStubProtocol.installStatus(200, body: try HomeModel.encoder().encode(fire))
        _ = try await makeClient().fetchRoutesCached(home: home, cache: cache)
        OfflineStubProtocol.installStatus(200, body: try HomeModel.encoder().encode(tornado))
        _ = try await makeClient().fetchRoutesCached(home: home, peril: "tornado", cache: cache)
        OfflineStubProtocol.remove()

        #expect(try await offlineLookup(cache, home: home)?.plan.peril == "fire")
        #expect(try await offlineLookup(cache, home: home, peril: "tornado")?.plan.peril == "tornado")
    }

    @Test("Another person's plan is a miss, and so is the household's when only a person is cached")
    func otherPersonIsAMiss() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        let sam = relabelled(try samplePlan(), peril: "fire", profileID: "sam")
        try seed(cache, sam, home: home, profileID: "sam")

        #expect(try await offlineLookup(cache, home: home, profileID: "sam") != nil,
                "the same person is a hit")
        #expect(try await offlineLookup(cache, home: home, profileID: "leo") == nil,
                "a wheelchair user must never be handed someone else's route through stairs")
        #expect(try await offlineLookup(cache, home: home) == nil,
                "Sam's route is not the household's")

        try seed(cache, try samplePlan(), home: home)  // the household
        #expect(try await offlineLookup(cache, home: home, profileID: "leo") == nil)
        #expect(try await offlineLookup(cache, home: home)?.plan.profile_id == nil)
    }

    @Test("A plan computed before an edit is a miss: no route through rooms that are gone")
    func editedHomeIsAMiss() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        try seed(cache, try samplePlan(), home: home)
        #expect(try await offlineLookup(cache, home: home) != nil)

        var edited = home
        edited.floors[0].rooms.removeFirst()
        #expect(try await offlineLookup(cache, home: edited) == nil)

        // Editing it back restores the model the plan was computed from.
        #expect(try await offlineLookup(cache, home: home) != nil)
    }

    @Test("Saving the home does not lose its plan: the printout finds what House just fetched")
    func savedHomeKeepsItsPlan() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory.appendingPathComponent("routes"))
        let store = try HomeDocumentStore(directory: directory.appendingPathComponent("homes"))

        // House's model as the editor leaves it: `meta.modified` stamped with sub-second
        // precision on the last edit. Routes are fetched (and cached) from this model...
        var inMemory = try FixtureLoader.load(.twostory)
        inMemory.meta.modified = Date(timeIntervalSince1970: 1_770_000_000.375)
        try seed(cache, try samplePlan(), home: inMemory)
        // ...and autosave writes it with the store's own clock, in whole seconds.
        try store.save(model: inMemory, now: Date(timeIntervalSince1970: 1_770_000_042.9))
        let onDisk = try store.load(homeID: inMemory.home_id, as: HomeModel.self)
        #expect(onDisk.meta.modified != inMemory.meta.modified, "the precondition: meta differs")

        let exporter = EscapePlanExporter(store: store, routeCache: cache,
                                          meetingPoints: MeetingPointStore())
        #expect(try exporter.preview(homeID: inMemory.home_id).hasRoutes,
                "a timestamp is not an edit: the routes still describe this home")
    }

    @Test("A plan whose own peril or person differs from the key's is refused, whatever the file")
    func tamperedEntryIsAMiss() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        let fingerprint = RoutePlanCache.fingerprint(of: home)
        let fireKey = RoutePlanKey(homeID: home.home_id)
        let tornadoKey = RoutePlanKey(homeID: home.home_id, peril: "tornado")
        let samKey = RoutePlanKey(homeID: home.home_id, profileID: "sam")
        let fire = try samplePlan()

        // The fire file copied into the tornado and Sam slots: right fingerprint, wrong peril
        // and person, both inside the file and in the plan it holds.
        try seed(cache, fire, home: home)
        try FileManager.default.copyItem(at: cache.url(for: fireKey), to: cache.url(for: tornadoKey))
        try FileManager.default.copyItem(at: cache.url(for: fireKey), to: cache.url(for: samKey))
        #expect(cache.load(tornadoKey, homeFingerprint: fingerprint) == nil)
        #expect(cache.load(samKey, homeFingerprint: fingerprint) == nil)

        // A tornado-labelled plan saved under the fire key (a caller bug) is refused too.
        try cache.save(relabelled(fire, peril: "tornado", profileID: nil),
                       key: fireKey, homeFingerprint: fingerprint)
        #expect(cache.load(fireKey, homeFingerprint: fingerprint) == nil)

        // And so is a plan for a different home.
        var other = fire
        other.home_id = "someone-elses-home"
        try cache.save(other, key: fireKey, homeFingerprint: fingerprint)
        #expect(cache.load(fireKey, homeFingerprint: fingerprint) == nil)
    }

    @Test("Old single-key cache files are never served, and are cleaned up")
    func oldFormatFileIsIgnored() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let home = try FixtureLoader.load(.twostory)
        let plan = try samplePlan()

        // Exactly what the pre-S11.36 cache wrote: `<home_id>.routeplan.json`, a plan and a date.
        struct LegacyEntry: Encodable { var plan: RoutePlan; var savedAt: Date }
        let legacy = directory.appendingPathComponent("\(home.home_id).routeplan.json")
        try HomeModel.encoder().encode(LegacyEntry(plan: plan, savedAt: Date())).write(to: legacy)

        #expect(try await offlineLookup(cache, home: home) == nil,
                "the old file names no key, so it must not stand in for the fire plan")

        // The old shape in a new-format slot cannot decode: it has no fingerprint.
        try FileManager.default.copyItem(
            at: legacy, to: cache.url(for: RoutePlanKey(homeID: home.home_id)))
        #expect(try await offlineLookup(cache, home: home) == nil)

        // The next launch removes it; the new-format file is left alone.
        _ = try RoutePlanCache(directory: directory)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(
            atPath: cache.url(for: RoutePlanKey(homeID: home.home_id)).path))
    }

    @Test("A synced home or profile id cannot write outside the cache or collide with another")
    func hostileIDsStayInsideTheCache() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        let plan = try samplePlan()

        let hostile = RoutePlanKey(homeID: "../../x/y", peril: "fire", profileID: "../p.q")
        let url = cache.url(for: hostile)
        #expect(url.deletingLastPathComponent().standardizedFileURL
                == directory.standardizedFileURL)
        var stored = plan
        stored.home_id = hostile.homeID
        stored.profile_id = hostile.profileID
        try cache.save(stored, key: hostile, homeFingerprint: "fp")
        #expect(cache.load(hostile, homeFingerprint: "fp") != nil)

        // `a.b` + household and `a` + a person called `b` are different entries.
        #expect(cache.url(for: RoutePlanKey(homeID: "a.b"))
                != cache.url(for: RoutePlanKey(homeID: "a", profileID: "b")))
        #expect(cache.url(for: RoutePlanKey(homeID: "h", profileID: "household"))
                != cache.url(for: RoutePlanKey(homeID: "h")),
                "a person whose id is \"household\" is not the household")
    }

    // MARK: - 1c. The printable plan reads the same cache by the same rules

    private func exporter(_ cache: RoutePlanCache, _ root: URL) throws
        -> (EscapePlanExporter, HomeDocumentStore) {
        let store = try HomeDocumentStore(directory: root.appendingPathComponent("homes"))
        return (EscapePlanExporter(store: store, routeCache: cache,
                                   meetingPoints: MeetingPointStore()), store)
    }

    @Test("The printout carries only the household's fire routes for the home as saved")
    func printablePlanUsesTheKey() throws {
        let root = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = try RoutePlanCache(directory: root.appendingPathComponent("routes"))
        let (exporter, store) = try exporter(cache, root)
        let fixture = try FixtureLoader.load(.twostory)
        try store.save(model: fixture)
        let plan = try samplePlan()

        // The fingerprint of the model after a trip through the document store is the one
        // House stamped on the plan: a printout is not a miss merely for having been saved.
        let home = try store.load(homeID: fixture.home_id, as: HomeModel.self)

        #expect(try exporter.preview(homeID: home.home_id).hasRoutes == false, "nothing cached")

        // Another peril and one person's route are not the household's fire plan.
        try seed(cache, relabelled(plan, peril: "tornado", profileID: nil), home: home,
                 peril: "tornado")
        try seed(cache, relabelled(plan, peril: "fire", profileID: "sam"), home: home,
                 profileID: "sam")
        #expect(try exporter.preview(homeID: home.home_id).hasRoutes == false)

        try seed(cache, plan, home: home)
        #expect(try exporter.preview(homeID: home.home_id).hasRoutes)

        // Edit the home on disk: the routes were computed for a house that no longer exists.
        var edited = home
        edited.floors[0].rooms.removeFirst()
        try store.save(model: edited)
        #expect(try exporter.preview(homeID: home.home_id).hasRoutes == false)
    }


    // MARK: - 2. A server ANSWER is never masked by the cache

    @Test("A 401 is not masked by a populated cache")
    func unauthorizedIsNotMasked() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try RoutePlanCache(directory: directory)
        try seed(cache, try samplePlan(), home: try FixtureLoader.load(.twostory))

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
        try seed(cache, try samplePlan(), home: try FixtureLoader.load(.twostory))

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
        let failure = BackendFailure.showingCachedRoutes(savedAt: savedAt, peril: "fire",
                                                         personName: nil)

        #expect(failure.kind == .offline)
        #expect(failure.isOfflineFlavoured)
        // The exact string is locale-dependent; what matters is that the stamp is IN it, so a
        // three-week-old plan can never read as a fresh one.
        let stamp = savedAt.formatted(date: .abbreviated, time: .shortened)
        #expect(failure.message.contains(stamp))
        #expect(failure.isRetryable, "the user can still try for live routes")
    }

    @Test("The cached-routes notice names the peril and the person the plan is for")
    func cachedNoticeNamesPerilAndPerson() {
        let savedAt = Date(timeIntervalSince1970: 1_770_000_000)
        let stamp = savedAt.formatted(date: .abbreviated, time: .shortened)

        let sam = BackendFailure.showingCachedRoutes(savedAt: savedAt, peril: "tornado",
                                                     personName: "Sam")
        #expect(sam.message == "You're offline — showing your last saved tornado routes for Sam "
                             + "from \(stamp).")

        let everyone = BackendFailure.showingCachedRoutes(savedAt: savedAt, peril: "fire",
                                                          personName: nil)
        #expect(everyone.message == "You're offline — showing your last saved fire routes for "
                                  + "everyone from \(stamp).")
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
