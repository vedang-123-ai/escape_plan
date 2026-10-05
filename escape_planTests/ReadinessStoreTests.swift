//  ReadinessStoreTests.swift
//  AUD-023 (S11.17): an unreviewed AI draft is never scored. `ReadinessStore` must not send
//  /score for a home with any `ai_plan` element (House's own `hasAIDraftContent` predicate), must
//  not show a score cached for it, and must score it as soon as the draft is confirmed.
//
//  AUD-014 (S11.23): a score belongs to the home it was asked for. With a stub that holds each
//  /score answer until the test releases it, these reproduce the home-switch race: A's answer
//  arriving after B's, A failing after the switch, a superseded request, and a tick on an item
//  from another home's checklist.
//
//  No seam was added to ReadinessStore: `APIClient` already takes a `URLSession`, so each test
//  hands it an ephemeral session whose only protocol is a spy. Nothing is registered globally, so
//  these tests cannot see or swallow another suite's traffic.

import Foundation
import XCTest

@testable import escape_plan

/// Records every request on the session it is installed in and answers 503, so a request that
/// does go out ends in a failure the store can show, never in a score.
private final class ScoreSpyProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() { lock.withLock { requests = [] } }
    static var scoreRequests: [URLRequest] {
        lock.withLock { requests.filter { $0.url?.lastPathComponent == "score" } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.requests.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Holds every /score request until the test answers it, so a test decides the order responses
/// arrive in. Records the home each request was for, read from the request body.
///
/// Answers are delivered on the thread that called `startLoading`, in its run loop mode (as
/// Apple's CustomHTTPProtocol sample does), so a cancel (`stopLoading`, same thread) and an
/// answer can never interleave.
private final class GatedScoreProtocol: URLProtocol {
    nonisolated(unsafe) private static var started: [GatedScoreProtocol] = []
    private static let lock = NSLock()
    /// Read and written only on `clientThread`.
    private var stopped = false
    private var clientThread: Thread?
    private var clientModes: [String] = [RunLoop.Mode.default.rawValue]
    private(set) var homeID = ""
    /// The request's `checklist_state`, as sent (S11.35).
    private(set) var checklistState: [String: Any] = [:]

    static func reset() { lock.withLock { started = [] } }
    static var requests: [GatedScoreProtocol] { lock.withLock { started } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        clientThread = Thread.current
        if let mode = RunLoop.current.currentMode { clientModes = [mode.rawValue] }
        let json = Self.body(of: request)
        homeID = (json?["home"] as? [String: Any])?["home_id"] as? String ?? ""
        checklistState = json?["checklist_state"] as? [String: Any] ?? [:]
        Self.lock.withLock { Self.started.append(self) }
    }

    override func stopLoading() { stopped = true }

    /// Answers the request, unless it was cancelled first (then nothing can be delivered).
    func respond(status: Int, body: Data = Data()) {
        guard let clientThread else { return }
        perform(#selector(deliver(_:)), on: clientThread, with: [status, body] as NSArray,
                waitUntilDone: false, modes: clientModes)
    }

    @objc private func deliver(_ payload: NSArray) {
        guard !stopped, let status = payload[0] as? Int, let body = payload[1] as? Data else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// URLProtocol sees a POST body as a stream, not `httpBody`.
    private static func body(of request: URLRequest) -> [String: Any]? {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

@MainActor
final class ReadinessStoreTests: XCTestCase {
    private var directory: URL!
    private var homeID: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadinessStoreTests-\(UUID().uuidString)", isDirectory: true)
        homeID = "readiness-test-\(UUID().uuidString.lowercased())"
        ScoreSpyProtocol.reset()
        GatedScoreProtocol.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        for id in [homeID!, homeA, homeB] {
            (try? ScoreCache())?.remove(homeID: id)
            UserDefaults.standard.removeObject(forKey: "checklistState.\(id)")
        }
    }

    private var homeA: String { "\(homeID!)-a" }
    private var homeB: String { "\(homeID!)-b" }

    // MARK: - Helpers

    private func spyClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScoreSpyProtocol.self]
        let defaults = UserDefaults(suiteName: "ReadinessStoreTests.\(UUID().uuidString)")!
        defaults.set("https://readiness-tests.invalid", forKey: "APIClient.baseURL")
        return APIClient(defaults: defaults, session: URLSession(configuration: configuration))
    }

    private func gatedClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatedScoreProtocol.self]
        let defaults = UserDefaults(suiteName: "ReadinessStoreTests.\(UUID().uuidString)")!
        defaults.set("https://readiness-tests.invalid", forKey: "APIClient.baseURL")
        return APIClient(defaults: defaults, session: URLSession(configuration: configuration))
    }

    /// Waits for the store's own re-score (started by a tick, so there is no task to await).
    private func waitUntilScored(_ readiness: ReadinessStore) async throws {
        let deadline = Date().addingTimeInterval(10)
        while readiness.isScoring {
            if Date() > deadline {
                XCTFail("/score never finished")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// The `index`th /score request the gated stub has seen (0-based), once it has arrived.
    private func gatedRequest(_ index: Int) async throws -> GatedScoreProtocol {
        let deadline = Date().addingTimeInterval(10)
        while GatedScoreProtocol.requests.count <= index {
            if Date() > deadline {
                XCTFail("/score request \(index) never arrived")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return GatedScoreProtocol.requests[index]
    }

    /// A /score answer with one checklist item, so a test can tell whose checklist is on screen.
    private func scoreJSON(home: String, score: Int, itemID: String) -> Data {
        Data("""
        {"home_id": "\(home)", "home_name": "\(home)", "score": \(score),
         "sub_scores": {"fire": \(score), "earthquake": \(score), "severe_weather": \(score)},
         "components": [],
         "checklist": [{"id": "\(itemID)", "category": "practice", "title": "Pick a meeting place",
                        "detail": "Outside, in front of the house.", "done": false, "scoring": false}]}
        """.utf8)
    }

    private struct TwoHomes {
        let readiness: ReadinessStore
        /// The home active at launch, and the other one.
        let a: String
        let b: String
        /// Launch's load of A, still waiting on its /score (gated request 0).
        let loadA: Task<Void, Never>
        let requestA: GatedScoreProtocol
    }

    /// Two scorable homes; whichever the library lists first is A. A's /score is held open.
    private func launchWithTwoHomes(api: APIClient) async throws -> TwoHomes {
        let documents = try HomeDocumentStore(directory: directory)
        for id in [homeA, homeB] {
            var model = try Fixtures.load("bungalow")
            model.home_id = id
            _ = try documents.save(model: model)
        }
        let readiness = ReadinessStore(library: HomeLibrary(store: documents))
        let a = try XCTUnwrap(readiness.activeHomeID)
        let b = a == homeA ? homeB : homeA
        let loadA = Task { await readiness.load(api: api) }
        let requestA = try await gatedRequest(0)
        XCTAssertEqual(requestA.homeID, a)
        XCTAssertTrue(readiness.isScoring)
        return TwoHomes(readiness: readiness, a: a, b: b, loadA: loadA, requestA: requestA)
    }

    /// The bungalow with every room and opening marked as an AI draft, the way /build emits it.
    private func draftHome() throws -> HomeModel {
        var model = try Fixtures.load("bungalow")
        model.home_id = homeID
        for f in model.floors.indices {
            for r in model.floors[f].rooms.indices {
                model.floors[f].rooms[r].source = .ai_plan
                model.floors[f].rooms[r].confidence = 0.5
            }
            for o in model.floors[f].openings.indices {
                model.floors[f].openings[o].source = .ai_plan
                model.floors[f].openings[o].confidence = 0.5
            }
        }
        XCTAssertTrue(model.hasAIDraftContent)
        return model
    }

    private func store(with model: HomeModel) throws -> (ReadinessStore, HomeDocumentStore) {
        let documents = try HomeDocumentStore(directory: directory)
        _ = try documents.save(model: model)
        let readiness = ReadinessStore(library: HomeLibrary(store: documents))
        XCTAssertEqual(readiness.activeHomeID, model.home_id)
        return (readiness, documents)
    }

    // MARK: - Tests

    func testUnreviewedDraftIsNeverSentToScore() async throws {
        let (readiness, _) = try store(with: try draftHome())
        let api = spyClient()

        await readiness.load(api: api)

        XCTAssertTrue(readiness.needsDraftReview)
        XCTAssertNil(readiness.breakdown)
        XCTAssertNil(readiness.scoreFailure, "a draft is not a failure; it shows the review state")
        XCTAssertTrue(ScoreSpyProtocol.scoreRequests.isEmpty)

        // The other ways in, each awaited rather than slept on: a re-score (Score's refresh and
        // every Retry), a ticked task, and a changed home (the re-scan diff).
        await readiness.rescore(api: api).value
        XCTAssertTrue(ScoreSpyProtocol.scoreRequests.isEmpty)
        readiness.replaceActiveHome(try draftHome(), api: api)
        await readiness.rescore(api: api).value
        XCTAssertTrue(ScoreSpyProtocol.scoreRequests.isEmpty)
        XCTAssertNil(readiness.breakdown)
        XCTAssertTrue(readiness.items.isEmpty)
    }

    /// Import Plan selects the draft while another home is active (with a failure showing).
    /// Nothing from the previous home may stay on screen for the draft.
    func testSwitchingFromAScoredHomeToADraftClearsEverything() async throws {
        var other = try Fixtures.load("bungalow")
        other.home_id = "\(homeID!)-other"
        let documents = try HomeDocumentStore(directory: directory)
        _ = try documents.save(model: other)
        let readiness = ReadinessStore(library: HomeLibrary(store: documents))
        let api = spyClient()
        await readiness.load(api: api)
        XCTAssertEqual(ScoreSpyProtocol.scoreRequests.count, 1)
        XCTAssertNotNil(readiness.scoreFailure, "the spy answers 503")

        _ = try documents.save(model: try draftHome())
        await readiness.select(homeID, api: api)

        XCTAssertTrue(readiness.needsDraftReview)
        XCTAssertNil(readiness.breakdown)
        XCTAssertNil(readiness.scoreFailure)
        XCTAssertTrue(readiness.items.isEmpty)
        XCTAssertEqual(ScoreSpyProtocol.scoreRequests.count, 1, "no /score for the draft")
    }

    func testScoreCachedBeforeTheFixIsNotShownForADraft() async throws {
        let (readiness, _) = try store(with: try draftHome())
        let cached = try HomeModel.decoder.decode(ScoreBreakdown.self, from: Data("""
        {"home_id": "\(homeID!)", "home_name": "Bungalow", "score": 81,
         "sub_scores": {"fire": 81, "earthquake": 81, "severe_weather": 81},
         "components": [], "checklist": []}
        """.utf8))
        try ScoreCache().save(cached, for: homeID)

        await readiness.load(api: spyClient())

        XCTAssertNil(readiness.breakdown, "a score for a guessed floor plan must not reappear from cache")
        XCTAssertTrue(ScoreSpyProtocol.scoreRequests.isEmpty)
        XCTAssertNil(try ScoreCache().load(homeID: homeID),
                     "the draft-era cache file is deleted, so House and the plan export cannot read it either")
    }

    /// After confirming, the draft-era cache must not stand in for the real score while /score
    /// fails (a cold start, offline): the user would see the guessed plan's number as current.
    func testDraftEraCacheIsNotShownAfterConfirmWhenScoringFails() async throws {
        let (readiness, documents) = try store(with: try draftHome())
        let cached = try HomeModel.decoder.decode(ScoreBreakdown.self, from: Data("""
        {"home_id": "\(homeID!)", "home_name": "Bungalow", "score": 81,
         "sub_scores": {"fire": 81, "earthquake": 81, "severe_weather": 81},
         "components": [], "checklist": []}
        """.utf8))
        try ScoreCache().save(cached, for: homeID)
        let api = spyClient()
        await readiness.load(api: api)

        let editor = try HomeModelStore.testStore(try documents.load(homeID: homeID, as: HomeModel.self))
        XCTAssertTrue(editor.dispatch(.confirmAIDraft).didApply)
        _ = try documents.save(model: editor.model)
        await readiness.load(api: api)

        XCTAssertEqual(ScoreSpyProtocol.scoreRequests.count, 1)
        XCTAssertNil(readiness.breakdown)
        XCTAssertNotNil(readiness.scoreFailure)
    }

    /// The control: the spy does see /score, so the empty counts above mean something. Confirming
    /// through House's own edit action, then reloading as House's autosave does, scores the home.
    func testConfirmedDraftIsScored() async throws {
        let (readiness, documents) = try store(with: try draftHome())
        let api = spyClient()
        await readiness.load(api: api)
        XCTAssertTrue(ScoreSpyProtocol.scoreRequests.isEmpty)

        let editor = try HomeModelStore.testStore(try documents.load(homeID: homeID, as: HomeModel.self))
        XCTAssertTrue(editor.dispatch(.confirmAIDraft).didApply)
        _ = try documents.save(model: editor.model)

        await readiness.load(api: api)

        XCTAssertFalse(readiness.needsDraftReview)
        XCTAssertEqual(ScoreSpyProtocol.scoreRequests.count, 1)
        XCTAssertNotNil(readiness.scoreFailure, "the spy answers 503, so the store reports it")
    }

    // MARK: - AUD-014: a score belongs to the home it was asked for

    /// The audit's race: A's /score is slow (a cold server), the user switches to B, B answers,
    /// then A's answer arrives. B's score and checklist must stay on screen.
    func testPreviousHomesLateScoreNeverLandsOnTheNewHome() async throws {
        let api = gatedClient()
        let homes = try await launchWithTwoHomes(api: api)
        let readiness = homes.readiness

        let loadB = Task { await readiness.select(homes.b, api: api) }
        let requestB = try await gatedRequest(1)
        XCTAssertEqual(requestB.homeID, homes.b)
        requestB.respond(status: 200, body: scoreJSON(home: homes.b, score: 40, itemID: "b.item"))
        await loadB.value
        XCTAssertEqual(readiness.breakdown?.score, 40)

        homes.requestA.respond(status: 200, body: scoreJSON(home: homes.a, score: 90, itemID: "a.item"))
        await homes.loadA.value

        XCTAssertEqual(readiness.activeHomeID, homes.b)
        XCTAssertEqual(readiness.breakdown?.score, 40, "A's late answer landed under B's name")
        XCTAssertEqual(readiness.items.map(\.id), ["b.item"])
        XCTAssertFalse(readiness.isScoring)
        XCTAssertNil(readiness.scoreFailure)
        // The cache stays keyed by the home each score was computed for.
        XCTAssertEqual(try ScoreCache().load(homeID: homes.b)?.score, 40)
        XCTAssertNil(try ScoreCache().load(homeID: homes.a), "A's cancelled request saved nothing")
    }

    /// A failing after the switch must not put a "couldn't reach the server" notice on B, and must
    /// not stop B's spinner while B is still loading.
    func testPreviousHomesFailureAfterSwitchingShowsNothing() async throws {
        let api = gatedClient()
        let homes = try await launchWithTwoHomes(api: api)
        let readiness = homes.readiness

        let loadB = Task { await readiness.select(homes.b, api: api) }
        let requestB = try await gatedRequest(1)
        homes.requestA.respond(status: 503)
        await homes.loadA.value

        XCTAssertNil(readiness.scoreFailure, "A's failure was shown for B")
        XCTAssertTrue(readiness.isScoring, "B is still in flight")
        XCTAssertNil(readiness.breakdown)

        requestB.respond(status: 200, body: scoreJSON(home: homes.b, score: 40, itemID: "b.item"))
        await loadB.value
        XCTAssertEqual(readiness.breakdown?.score, 40)
        XCTAssertFalse(readiness.isScoring)
        XCTAssertNil(readiness.scoreFailure)
    }

    /// Rapid ticks or Retry taps replace the request in flight. The replaced one is cancelled,
    /// which is not a failure, and the spinner belongs to the request that replaced it.
    func testSupersededRequestShowsNoFailureAndKeepsTheSpinner() async throws {
        let api = gatedClient()
        let homes = try await launchWithTwoHomes(api: api)
        let readiness = homes.readiness
        homes.requestA.respond(status: 200, body: scoreJSON(home: homes.a, score: 40, itemID: "a.item"))
        await homes.loadA.value
        XCTAssertEqual(readiness.breakdown?.score, 40)

        let first = readiness.rescore(api: api)
        _ = try await gatedRequest(1)
        let second = readiness.rescore(api: api)
        let secondRequest = try await gatedRequest(2)
        await first.value

        XCTAssertNil(readiness.scoreFailure, "a cancelled request was reported as a failure")
        XCTAssertTrue(readiness.isScoring, "the replacing request is still in flight")
        XCTAssertEqual(readiness.breakdown?.score, 40, "nothing changes until the replacement answers")

        secondRequest.respond(status: 200, body: scoreJSON(home: homes.a, score: 55, itemID: "a.item"))
        await second.value
        XCTAssertEqual(readiness.breakdown?.score, 55)
        XCTAssertFalse(readiness.isScoring)
        XCTAssertNil(readiness.scoreFailure)
    }

    /// Both ways a request reports being cancelled. URLSession throws URLError(.cancelled), which
    /// the shared failure classifier used to read as "couldn't reach the server".
    func testCancellationIsRecognisedInBothForms() {
        XCTAssertTrue(ReadinessStore.isCancellation(CancellationError()))
        XCTAssertTrue(ReadinessStore.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(ReadinessStore.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(ReadinessStore.isCancellation(URLError(.notConnectedToInternet)))
    }

    /// An item from A's checklist (a row still on screen, an open detail sheet) ticked after the
    /// switch to B must not be saved into B's state. B's own items still tick and re-score.
    func testTickingAnotherHomesItemChangesNothing() async throws {
        let api = gatedClient()
        let homes = try await launchWithTwoHomes(api: api)
        let readiness = homes.readiness
        homes.requestA.respond(status: 200, body: scoreJSON(home: homes.a, score: 40, itemID: "a.item"))
        await homes.loadA.value
        let itemOfA = try XCTUnwrap(readiness.items.first)

        let loadB = Task { await readiness.select(homes.b, api: api) }
        try await gatedRequest(1).respond(status: 200, body: scoreJSON(home: homes.b, score: 60, itemID: "b.item"))
        await loadB.value
        XCTAssertEqual(readiness.items.map(\.id), ["b.item"])

        readiness.toggleDone(itemOfA, api: api, animated: false)
        XCTAssertNil(readiness.checklistState[itemOfA.id], "A's item was ticked in B's state")
        XCTAssertNil(ChecklistStateStore().load(homeID: homes.b)[itemOfA.id])
        XCTAssertFalse(readiness.isScoring, "an ignored tick sends no /score")
        XCTAssertEqual(GatedScoreProtocol.requests.count, 2)

        // The control: B's own item ticks, is saved under B, and re-scores B.
        let itemOfB = try XCTUnwrap(readiness.items.first)
        readiness.toggleDone(itemOfB, api: api, animated: false)
        XCTAssertEqual(readiness.checklistState[itemOfB.id], true)
        XCTAssertEqual(ChecklistStateStore().load(homeID: homes.b)[itemOfB.id], true)
        let rescoreB = try await gatedRequest(2)
        XCTAssertEqual(rescoreB.homeID, homes.b)
        rescoreB.respond(status: 200, body: scoreJSON(home: homes.b, score: 65, itemID: "b.item"))
        try await waitUntilScored(readiness)
        XCTAssertEqual(readiness.breakdown?.score, 65)
    }

    /// The active home was deleted: `ensureActiveHome` moves to B, and until `load` runs the store
    /// still holds A's model. A Retry in that window must not send A's model under B's id.
    func testRescoreBeforeTheNewHomeIsLoadedSendsNothing() async throws {
        let api = gatedClient()
        let homes = try await launchWithTwoHomes(api: api)
        let readiness = homes.readiness
        homes.requestA.respond(status: 200, body: scoreJSON(home: homes.a, score: 40, itemID: "a.item"))
        await homes.loadA.value

        XCTAssertTrue(readiness.library.delete(homeID: homes.a))
        readiness.ensureActiveHome()
        XCTAssertEqual(readiness.activeHomeID, homes.b)
        XCTAssertNil(readiness.breakdown, "A's score is not shown under B")

        await readiness.rescore(api: api).value
        XCTAssertFalse(readiness.isScoring)
        XCTAssertEqual(GatedScoreProtocol.requests.count, 1, "A's model was sent for B")
    }

    /// A household saved for another home (Profiles opened before a switch) is not scored here.
    func testReplacingWithAnotherHomesModelIsIgnored() async throws {
        let api = gatedClient()
        let homes = try await launchWithTwoHomes(api: api)
        let readiness = homes.readiness
        homes.requestA.respond(status: 200, body: scoreJSON(home: homes.a, score: 40, itemID: "a.item"))
        await homes.loadA.value

        var other = try Fixtures.load("bungalow")
        other.home_id = homes.b
        readiness.replaceActiveHome(other, api: api)

        XCTAssertEqual(readiness.activeHome?.home_id, homes.a)
        XCTAssertFalse(readiness.isScoring)
        XCTAssertEqual(GatedScoreProtocol.requests.count, 1)
    }

    // MARK: - Recurrence: one clock (S11.35, AUD-026)

    private let drillID = "practice.drill_recent"

    /// A /score answer with the drill item as S11.34 sends it.
    private func drillScoreJSON(home: String, done: Bool, completedAt: String?) -> Data {
        let completed = completedAt.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {"home_id": "\(home)", "home_name": "\(home)", "score": 70,
         "sub_scores": {"fire": 70, "earthquake": 70, "severe_weather": 70},
         "components": [],
         "checklist": [{"id": "\(drillID)", "category": "practice", "title": "Practice a fire drill",
                        "detail": "Twice a year.", "done": \(done), "scoring": false,
                        "recurrence_days": 183, "completed_at": \(completed)}]}
        """.utf8)
    }

    private func scorableStore() throws -> ReadinessStore {
        var model = try Fixtures.load("bungalow")
        model.home_id = homeID
        return try store(with: model).0
    }

    /// The manual acceptance check as a test: a drill done 200 days ago is sent as that date, the
    /// server says it lapsed, and the task shows not done because the RESPONSE says so.
    func testStoredDateIsSentAndTheServersAnswerDecidesDone() async throws {
        let old = Date(timeIntervalSince1970: 1_791_115_200 - 200 * 86_400) // 2026-03-18T12:00:00Z
        ChecklistStateStore().save([drillID: .completed(old)], homeID: homeID)
        let readiness = try scorableStore()
        let api = gatedClient()

        let load = Task { await readiness.load(api: api) }
        let request = try await gatedRequest(0)
        XCTAssertEqual(request.checklistState[drillID] as? String, "2026-03-18T12:00:00Z")
        request.respond(status: 200, body: drillScoreJSON(home: homeID, done: false,
                                                          completedAt: "2026-03-18T12:00:00Z"))
        await load.value

        let item = try XCTUnwrap(readiness.items.first)
        XCTAssertFalse(readiness.isDone(item))
        XCTAssertEqual(readiness.upNext.map(\.id), [drillID], "a lapsed drill is back on the to-do list")
        XCTAssertEqual(ChecklistStateStore().load(homeID: homeID)[drillID], .completed(old),
                       "loading never rewrites the stored date")
    }

    /// A stale local value must never beat the server for a recurring item: a `true` stored on
    /// the phone, a server that says not done. Hypothetical today (S11.34 keeps a bare `true`
    /// done), so it pins the client rule, not the server's answer.
    func testLocalTickNeverOverridesTheServerForARecurringItem() async throws {
        ChecklistStateStore().save([drillID: true], homeID: homeID)
        let readiness = try scorableStore()
        let api = gatedClient()

        let load = Task { await readiness.load(api: api) }
        let request = try await gatedRequest(0)
        XCTAssertEqual(request.checklistState[drillID] as? Bool, true, "a legacy true is sent as is, no date invented")
        request.respond(status: 200, body: drillScoreJSON(home: homeID, done: false, completedAt: nil))
        await load.value

        XCTAssertFalse(readiness.isDone(try XCTUnwrap(readiness.items.first)))
    }

    /// Ticking a recurring item stores the time and sends it; it shows done at once, and once the
    /// answer lands the answer is what shows.
    func testTickingARecurringItemStoresAndSendsTheTime() async throws {
        let readiness = try scorableStore()
        let api = gatedClient()
        let ticked = Date(timeIntervalSince1970: 1_791_117_296) // 2026-10-04T12:34:56Z
        readiness.now = { ticked }

        let load = Task { await readiness.load(api: api) }
        try await gatedRequest(0).respond(status: 200, body: drillScoreJSON(home: homeID, done: false, completedAt: nil))
        await load.value
        let item = try XCTUnwrap(readiness.items.first)
        XCTAssertFalse(readiness.isDone(item))

        readiness.toggleDone(item, api: api, animated: false)
        XCTAssertEqual(readiness.checklistState[drillID], .completed(ticked))
        XCTAssertEqual(ChecklistStateStore().load(homeID: homeID)[drillID], .completed(ticked))
        XCTAssertTrue(readiness.isDone(item), "the tick shows before the answer arrives")
        let rescore = try await gatedRequest(1)
        XCTAssertEqual(rescore.checklistState[drillID] as? String, "2026-10-04T12:34:56Z")

        // The server is the clock: if it says not done, the row says not done.
        rescore.respond(status: 200, body: drillScoreJSON(home: homeID, done: false,
                                                          completedAt: "2026-10-04T12:34:56Z"))
        try await waitUntilScored(readiness)
        XCTAssertFalse(readiness.isDone(try XCTUnwrap(readiness.items.first)))
    }

    /// Offline: a tick, then a same-home reload (House autosave) whose /score fails. The tick stays.
    func testPendingTickSurvivesASameHomeReloadThatFails() async throws {
        let readiness = try scorableStore()
        let api = gatedClient()
        let load = Task { await readiness.load(api: api) }
        try await gatedRequest(0).respond(status: 200, body: drillScoreJSON(home: homeID, done: false, completedAt: nil))
        await load.value
        let item = try XCTUnwrap(readiness.items.first)
        readiness.toggleDone(item, api: api, animated: false)
        // The tick's own re-score must be in flight before the reload starts: if the reload
        // cancels it before it is sent, the reload becomes request 1 and request 2 never comes
        // (flaked in two independent full runs on 2026-10-04).
        _ = try await gatedRequest(1)

        let reload = Task { await readiness.load(api: api) }
        try await gatedRequest(2).respond(status: 503)
        await reload.value
        XCTAssertTrue(readiness.isDone(try XCTUnwrap(readiness.items.first)), "the offline tick vanished on reload")
    }

    func testUntickingARecurringItemStoresFalse() async throws {
        ChecklistStateStore().save([drillID: .completed(Date())], homeID: homeID)
        let readiness = try scorableStore()
        let api = gatedClient()
        let load = Task { await readiness.load(api: api) }
        try await gatedRequest(0).respond(status: 200, body: drillScoreJSON(home: homeID, done: true,
                                                                             completedAt: "2026-10-04T12:00:00Z"))
        await load.value
        let item = try XCTUnwrap(readiness.items.first)
        XCTAssertTrue(readiness.isDone(item))

        readiness.toggleDone(item, api: api, animated: false)
        XCTAssertEqual(readiness.checklistState[drillID], .flag(false))
        XCTAssertFalse(readiness.isDone(item))
        let rescore = try await gatedRequest(1)
        XCTAssertEqual(rescore.checklistState[drillID] as? Bool, false)
    }

    /// The monthly alarm test is ticked by hand (owner, 2026-10-04); the placement items still go
    /// to House. Decided by the server's recurrence_days, not by an id list.
    func testRecurringSmokeAlarmItemIsTickedByHand() {
        let monthly = ChecklistItem(id: "alarm.test_monthly", category: .smoke_alarm, title: "t", detail: "",
                                    done: false, scoring: true, recurrence_days: 30)
        let placement = ChecklistItem(id: "alarm.level.f1", category: .smoke_alarm, title: "t", detail: "",
                                      done: false, scoring: true)
        XCTAssertEqual(TaskDestination(monthly), .toggle)
        XCTAssertTrue(TaskDestination(monthly).isTickedByUser)
        XCTAssertEqual(TaskDestination(placement), .house)
    }

    // MARK: - S11.50: an old cache plus an offline tick; a phone clock that is far off

    /// The drill item as a score cached before S11.35 holds it: no recurrence keys at all.
    private func legacyCachedScore(home: String) throws -> ScoreBreakdown {
        try JSONDecoder().decode(ScoreBreakdown.self, from: Data("""
        {"home_id": "\(home)", "home_name": "\(home)", "score": 70,
         "sub_scores": {"fire": 70, "earthquake": 70, "severe_weather": 70},
         "components": [],
         "checklist": [{"id": "\(drillID)", "category": "practice", "title": "Practice a fire drill",
                        "detail": "Twice a year.", "done": false, "scoring": false}]}
        """.utf8))
    }

    /// Before S11.50 the tick stayed a plain `true`, which the server counts as done forever (it
    /// never lapses). Now, once an answer says the item recurs, the tick gets the time it was made.
    func testAnOfflineTickOverAnOldCacheGetsItsDateOnceTheItemIsKnownToRecur() async throws {
        let cache = try XCTUnwrap(try? ScoreCache())
        cache.save(try legacyCachedScore(home: homeID), for: homeID)
        let readiness = try scorableStore()
        let api = gatedClient()
        let ticked = Date(timeIntervalSince1970: 1_791_117_296) // 2026-10-04T12:34:56Z
        readiness.now = { ticked }

        let load = Task { await readiness.load(api: api) }
        _ = try await gatedRequest(0)                       // the old cache is on screen, no answer yet
        let item = try XCTUnwrap(readiness.items.first)
        XCTAssertNil(item.recurrence_days, "fixture: the cached item does not say it recurs")
        readiness.toggleDone(item, api: api, animated: false)
        XCTAssertEqual(readiness.checklistState[drillID], .flag(true), "nothing says it recurs yet")
        let offline = try await gatedRequest(1)
        XCTAssertEqual(offline.checklistState[drillID] as? Bool, true)
        offline.respond(status: 503)                        // offline
        await load.value
        try await waitUntilScored(readiness)

        // Back online: the answer says the drill recurs and (bare true) counts it done.
        let reload = Task { await readiness.load(api: api) }
        try await gatedRequest(2).respond(status: 200, body: drillScoreJSON(home: homeID, done: true, completedAt: nil))
        await reload.value

        XCTAssertEqual(readiness.checklistState[drillID], .completed(ticked), "the tick got its time")
        XCTAssertEqual(ChecklistStateStore().load(homeID: homeID)[drillID], .completed(ticked), "and it is saved")
        let resend = try await gatedRequest(3)
        XCTAssertEqual(resend.checklistState[drillID] as? String, "2026-10-04T12:34:56Z", "sent again with the date")
        XCTAssertTrue(readiness.isDone(try XCTUnwrap(readiness.items.first)), "still shown done meanwhile")
        resend.respond(status: 200, body: drillScoreJSON(home: homeID, done: true, completedAt: "2026-10-04T12:34:56Z"))
        try await waitUntilScored(readiness)
        XCTAssertTrue(readiness.isDone(try XCTUnwrap(readiness.items.first)))
        XCTAssertEqual(GatedScoreProtocol.requests.count, 4, "one extra request, no loop")
    }

    /// An item that turns out not to recur keeps its plain tick and costs no extra request.
    func testAnUntimedTickOnAnItemThatDoesNotRecurIsLeftAlone() async throws {
        let readiness = try scorableStore()
        let api = gatedClient()
        let load = Task { await readiness.load(api: api) }
        try await gatedRequest(0).respond(status: 200, body: scoreJSON(home: homeID, score: 50, itemID: "practice.meeting_point"))
        await load.value
        readiness.toggleDone(try XCTUnwrap(readiness.items.first), api: api, animated: false)
        try await gatedRequest(1).respond(status: 200, body: scoreJSON(home: homeID, score: 50, itemID: "practice.meeting_point"))
        try await waitUntilScored(readiness)
        XCTAssertEqual(readiness.checklistState["practice.meeting_point"], .flag(true))
        XCTAssertEqual(GatedScoreProtocol.requests.count, 2)
    }

    /// The server refuses a fresh tick's date only when this phone's clock is far off. The row
    /// used to flip back to not done with no reason; now Tasks says why and what to do.
    func testATickRefusedForTheClockSaysToCheckTheDateAndTime() async throws {
        let readiness = try scorableStore()
        let api = gatedClient()
        let wrongClock = Date(timeIntervalSince1970: 1_791_117_296 + 3 * 86_400) // 3 days ahead
        readiness.now = { wrongClock }
        let load = Task { await readiness.load(api: api) }
        try await gatedRequest(0).respond(status: 200, body: drillScoreJSON(home: homeID, done: false, completedAt: nil))
        await load.value
        XCTAssertNil(readiness.tickNotice)

        readiness.toggleDone(try XCTUnwrap(readiness.items.first), api: api, animated: false)
        // The server read the date (it echoes it) and refused it.
        try await gatedRequest(1).respond(status: 200, body: drillScoreJSON(home: homeID, done: false,
                                                                             completedAt: "2026-10-07T12:34:56Z"))
        try await waitUntilScored(readiness)
        XCTAssertFalse(readiness.isDone(try XCTUnwrap(readiness.items.first)))
        let notice = try XCTUnwrap(readiness.tickNotice, "the flip back must be explained")
        XCTAssertTrue(notice.contains("Practice a fire drill"))
        XCTAssertTrue(notice.contains("date and time"))
        XCTAssertTrue(notice.contains("tick it again"))

        // The next answer that refuses nothing clears it; a plain reload is not a new refusal.
        readiness.rescore(api: api)
        try await gatedRequest(2).respond(status: 200, body: drillScoreJSON(home: homeID, done: false,
                                                                             completedAt: "2026-10-07T12:34:56Z"))
        try await waitUntilScored(readiness)
        XCTAssertNil(readiness.tickNotice)
    }

    func testOnlyAFreshTickWhoseOwnDateCameBackRefusedCounts() throws {
        let stamp = Date(timeIntervalSince1970: 1_791_117_296)
        func answer(done: Bool, echoed: String?) throws -> ScoreBreakdown {
            try JSONDecoder().decode(ScoreBreakdown.self, from: drillScoreJSON(home: "h", done: done, completedAt: echoed))
        }
        let sent: [String: ChecklistMark] = [drillID: .completed(stamp)]
        let ticked = [drillID: true]
        XCTAssertEqual(ReadinessStore.refusedTicks(in: try answer(done: false, echoed: "2026-10-04T12:34:56Z"),
                                                   sent: sent, ticked: ticked).map(\.id), [drillID])
        XCTAssertTrue(ReadinessStore.refusedTicks(in: try answer(done: true, echoed: "2026-10-04T12:34:56Z"),
                                                  sent: sent, ticked: ticked).isEmpty, "accepted")
        XCTAssertTrue(ReadinessStore.refusedTicks(in: try answer(done: false, echoed: "2026-01-01T00:00:00Z"),
                                                  sent: sent, ticked: ticked).isEmpty, "not the date we sent")
        XCTAssertTrue(ReadinessStore.refusedTicks(in: try answer(done: false, echoed: "2026-10-04T12:34:56Z"),
                                                  sent: sent, ticked: [:]).isEmpty, "not ticked just now")
        XCTAssertTrue(ReadinessStore.refusedTicks(in: try answer(done: false, echoed: "2026-10-04T12:34:56Z"),
                                                  sent: [drillID: .flag(false)], ticked: ticked).isEmpty, "unticked")
    }
}
