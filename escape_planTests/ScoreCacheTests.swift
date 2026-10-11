//  ScoreCacheTests.swift
//  escape_planTests
//
//  Tests for ScoreCache fingerprinting, savedAt timestamps, path traversal prevention,
//  and responder snapshot stale-score omission (X-01, A07-02, A10-01, A07-05, A10-05).

import Foundation
import XCTest
@testable import escape_plan

final class ScoreCacheTests: XCTestCase {
    private var tempDir: URL!
    private var cache: ScoreCache!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScoreCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cache = try ScoreCache(fileManager: .default)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    private func makeScore(homeID: String = "test-home-1", scoreValue: Int = 85) -> ScoreBreakdown {
        ScoreBreakdown(
            home_id: homeID,
            home_name: "Test Home",
            score: scoreValue,
            sub_scores: ["fire": scoreValue],
            basis: nil,
            components: [],
            checklist: []
        )
    }

    private func makeHome(id: String = "test-home-1") throws -> HomeModel {
        try FixtureLoader.load(.bungalow)
    }

    // MARK: - Fingerprint & Timestamping (X-01 / A07-02 / A10-01)

    func testScoreCacheStoresFingerprintAndTimestamp() throws {
        let home = try makeHome(id: "home-fp-test")
        let homeID = home.id
        defer { cache.remove(homeID: homeID) }

        let score = makeScore(homeID: homeID, scoreValue: 92)
        let fingerprint = ScoreCache.fingerprint(of: home)
        let savedDate = Date(timeIntervalSince1970: 1700000000)

        cache.save(score, for: homeID, homeFingerprint: fingerprint, savedAt: savedDate)

        let entry = try XCTUnwrap(cache.loadEntry(homeID: homeID))
        XCTAssertEqual(entry.score.score, 92)
        XCTAssertEqual(entry.homeFingerprint, fingerprint)
        XCTAssertEqual(entry.savedAt?.timeIntervalSince1970 ?? 0, savedDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(entry.matchStatus(against: fingerprint), .match)
        XCTAssertTrue(entry.isMatch(for: home))
    }

    func testScoreCacheDetectsMismatchWhenHomeModelChanges() throws {
        var home = try makeHome(id: "home-mismatch-test")
        let homeID = home.id
        defer { cache.remove(homeID: homeID) }

        let originalFingerprint = ScoreCache.fingerprint(of: home)
        cache.save(makeScore(homeID: homeID, scoreValue: 88), for: homeID,
                   homeFingerprint: originalFingerprint, savedAt: Date())

        // Edit the home model by modifying room geometry
        home.floors[0].rooms[0].name = "Renovated Master Suite"
        let editedFingerprint = ScoreCache.fingerprint(of: home)
        XCTAssertNotEqual(originalFingerprint, editedFingerprint, "Model fingerprint must change after an edit")

        let loaded = try XCTUnwrap(cache.loadEntry(homeID: homeID))
        XCTAssertEqual(loaded.matchStatus(against: editedFingerprint), .mismatch(cached: originalFingerprint))
        XCTAssertFalse(loaded.isMatch(for: home), "Cache entry must not match edited home model")
        XCTAssertNil(cache.load(homeID: homeID, matchingFingerprint: editedFingerprint))
    }

    // MARK: - Backward Compatibility with Legacy Cache Files

    func testLegacyCacheWithoutEnvelopeStillLoadsAsUnknown() throws {
        let homeID = "home-legacy-compat-\(UUID().uuidString.prefix(8))"
        defer { cache.remove(homeID: homeID) }

        // Write raw legacy ScoreBreakdown directly to file without envelope
        let legacyScore = makeScore(homeID: homeID, scoreValue: 77)
        let legacyData = try HomeModel.encoder().encode(legacyScore)
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let legacyFile = caches.appendingPathComponent("ScoreCache/\(homeID).json")
        try legacyData.write(to: legacyFile)

        // Must still load via legacy load(homeID:)
        XCTAssertEqual(cache.load(homeID: homeID)?.score, 77)

        // loadEntry must report unknown match status
        let entry = try XCTUnwrap(cache.loadEntry(homeID: homeID))
        XCTAssertEqual(entry.score.score, 77)
        XCTAssertNil(entry.homeFingerprint)
        XCTAssertNil(entry.savedAt)
        XCTAssertEqual(entry.matchStatus(against: "any-current-fingerprint"), .unknown)
    }

    // MARK: - Path Traversal Prevention (A07-05)

    func testPathTraversalHomeIDsAreRejected() {
        XCTAssertThrowsError(try cache.write(makeScore(), for: "../evil"))
        XCTAssertThrowsError(try cache.write(makeScore(), for: "foo/bar"))
        XCTAssertNil(cache.load(homeID: "../evil"))
        XCTAssertNil(cache.loadEntry(homeID: "../evil"))
    }

    // MARK: - Responder Snapshot Omission on Mismatch (X-01 / A10-01)

    func testResponderSnapshotOmitsScoreWhenFingerprintMismatches() throws {
        let storeDir = tempDir.appendingPathComponent("Homes", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let store = try HomeDocumentStore(directory: storeDir)

        var home = try makeHome(id: "h-snapshot-test")
        let homeID = home.id
        _ = try store.save(model: home)
        defer { cache.remove(homeID: homeID) }

        let originalFingerprint = ScoreCache.fingerprint(of: home)
        let cachedScore = ScoreBreakdown(
            home_id: homeID,
            home_name: home.name,
            score: 95,
            sub_scores: ["fire": 95],
            basis: nil,
            components: [],
            checklist: [
                ChecklistItem(id: "alarm.smoke.installed", category: .smoke_alarm, title: "Smoke Alarm",
                              detail: "Installed", done: true, source_citation: nil, scoring: true)
            ]
        )

        // Save with matching fingerprint
        cache.save(cachedScore, for: homeID, homeFingerprint: originalFingerprint, savedAt: Date())

        let exporter = EscapePlanExporter(store: store)
        let preview = try exporter.preview(homeID: homeID)

        // Case 1: Fingerprint matches -> snapshot embeds the score
        let matchURLs = try exporter.writeResponderSnapshot(preview: preview, consent: .acknowledgedNow())
        let jsonURL = try XCTUnwrap(matchURLs.first(where: { $0.pathExtension == "json" }))
        let jsonData = try Data(contentsOf: jsonURL)
        let matchJSON = try JSONDecoder().decode(ResponderSnapshotJSON.self, from: jsonData)
        XCTAssertEqual(matchJSON.readinessScore, 95, "Snapshot should embed matching score")

        // Case 2: Home is edited -> fingerprint changes -> snapshot omits stale score
        home.floors[0].rooms[0].name = "Modified Room"
        _ = try store.save(model: home)
        let editedPreview = try exporter.preview(homeID: homeID)

        let staleURLs = try exporter.writeResponderSnapshot(preview: editedPreview, consent: .acknowledgedNow())
        let staleJSONURL = try XCTUnwrap(staleURLs.first(where: { $0.pathExtension == "json" }))
        let staleJSONData = try Data(contentsOf: staleJSONURL)
        let staleJSON = try JSONDecoder().decode(ResponderSnapshotJSON.self, from: staleJSONData)
        XCTAssertNil(staleJSON.readinessScore, "Snapshot must omit stale score after home edit")
        XCTAssertTrue(staleJSON.hazardSummary.isEmpty, "Snapshot must omit stale hazard summary after home edit")
    }
}
