//  ReadinessStoreTests.swift
//  AUD-023 (S11.17): an unreviewed AI draft is never scored. `ReadinessStore` must not send
//  /score for a home with any `ai_plan` element (House's own `hasAIDraftContent` predicate), must
//  not show a score cached for it, and must score it as soon as the draft is confirmed.
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

@MainActor
final class ReadinessStoreTests: XCTestCase {
    private var directory: URL!
    private var homeID: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadinessStoreTests-\(UUID().uuidString)", isDirectory: true)
        homeID = "readiness-test-\(UUID().uuidString.lowercased())"
        ScoreSpyProtocol.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        if let caches = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: false) {
            try? FileManager.default.removeItem(at: caches.appendingPathComponent("ScoreCache/\(homeID!).json"))
        }
    }

    // MARK: - Helpers

    private func spyClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScoreSpyProtocol.self]
        let defaults = UserDefaults(suiteName: "ReadinessStoreTests.\(UUID().uuidString)")!
        defaults.set("https://readiness-tests.invalid", forKey: "APIClient.baseURL")
        return APIClient(defaults: defaults, session: URLSession(configuration: configuration))
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
}
