//  SettingsShareTests.swift
//  AUD-027 (S11.38): "Share with your fire department" in Settings used to package
//  `store.list().first`, the most recently SAVED home, not the one the user is looking at. With
//  two homes, where the newest is not the active one, Settings must package the active home.
//  `SettingsScreen.shareTarget` is what the view hands to `ShareWithFireDepartmentCard`, and the
//  card hands its id to `EscapePlanExporter.preview`, so both steps are asserted.

import Foundation
import XCTest

@testable import escape_plan

/// Answers every request 503, so `ReadinessStore.load` finishes without a network and without
/// a score. Installed on one ephemeral session only, never globally.
private final class SettingsShare503Protocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class SettingsShareTests: XCTestCase {
    private var directory: URL!
    private let activeID = "settings-share-active-\(UUID().uuidString.lowercased())"
    private let newerID = "settings-share-newer-\(UUID().uuidString.lowercased())"

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsShareTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        for id in [activeID, newerID] {
            (try? ScoreCache())?.remove(homeID: id)
            UserDefaults.standard.removeObject(forKey: "checklistState.\(id)")
        }
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsShare503Protocol.self]
        let defaults = UserDefaults(suiteName: "SettingsShareTests.\(UUID().uuidString)")!
        defaults.set("https://settings-share-tests.invalid", forKey: "APIClient.baseURL")
        return APIClient(defaults: defaults, session: URLSession(configuration: configuration))
    }

    private func save(_ id: String, name: String, at seconds: TimeInterval,
                      to store: HomeDocumentStore, draft: Bool = false) throws {
        var model = try Fixtures.load("bungalow")
        model.home_id = id
        model.name = name
        if draft {
            for f in model.floors.indices {
                for r in model.floors[f].rooms.indices {
                    model.floors[f].rooms[r].source = .ai_plan
                    model.floors[f].rooms[r].confidence = 0.5
                }
            }
        }
        try store.save(model: model, now: Date(timeIntervalSince1970: seconds))
    }

    func testSettingsPackagesTheActiveHomeNotTheMostRecentlySaved() async throws {
        let store = try HomeDocumentStore(directory: directory)
        try save(activeID, name: "Grandma's house", at: 1_770_000_000, to: store)
        try save(newerID, name: "Our apartment", at: 1_770_009_999, to: store)
        XCTAssertEqual(store.list().first?.id, newerID,
                       "the precondition: the newest home is the one the old code shared")

        let readiness = ReadinessStore(library: HomeLibrary(store: store))
        await readiness.select(activeID, api: client())
        XCTAssertEqual(readiness.activeHomeID, activeID)

        let target = try XCTUnwrap(SettingsScreen.shareTarget(readiness))
        XCTAssertEqual(target.id, activeID)
        XCTAssertEqual(target.name, "Grandma's house", "the consent sheet names this home")

        let exporter = EscapePlanExporter(store: store, routeCache: nil,
                                          meetingPoints: MeetingPointStore())
        XCTAssertEqual(try exporter.preview(homeID: target.id).home.home_id, activeID)
    }

    func testNothingIsSharedFromAnUnreviewedDraft() async throws {
        let store = try HomeDocumentStore(directory: directory)
        try save(activeID, name: "Draft", at: 1_770_000_000, to: store, draft: true)

        let readiness = ReadinessStore(library: HomeLibrary(store: store))
        await readiness.load(api: client())
        XCTAssertTrue(readiness.needsDraftReview)
        XCTAssertNil(SettingsScreen.shareTarget(readiness))
    }

    func testNothingIsSharedWithNoHome() async throws {
        let store = try HomeDocumentStore(directory: directory)
        let readiness = ReadinessStore(library: HomeLibrary(store: store))
        await readiness.load(api: client())
        XCTAssertNil(readiness.activeHomeID)
        XCTAssertNil(SettingsScreen.shareTarget(readiness))
    }
}
