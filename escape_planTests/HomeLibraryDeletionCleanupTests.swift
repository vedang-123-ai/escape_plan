//  HomeLibraryDeletionCleanupTests.swift
//  escape_planTests
//
//  Tests verifying that deleting a home purges auxiliary data across
//  ChecklistStateStore, MeetingPointStore, ScanFreshnessStore, ScoreCache, and RouteCache (A07-04).

import Foundation
import XCTest
@testable import escape_plan

final class HomeLibraryDeletionCleanupTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "HomeLibraryCleanupTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeLibraryCleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testHomeDeletionCleansUpAllAuxiliaryStores() throws {
        let homeStoreDir = tempDir.appendingPathComponent("Homes", isDirectory: true)
        let store = try HomeDocumentStore(directory: homeStoreDir)
        let library = HomeLibrary(store: store)

        let home = try FixtureLoader.load(.bungalow)
        let homeID = home.id
        _ = try store.save(model: home)

        // Seed auxiliary stores for this home
        let checklistStore = ChecklistStateStore(defaults: defaults)
        checklistStore.save(["alarm.test": .flag(true)], homeID: homeID)
        XCTAssertFalse(checklistStore.load(homeID: homeID).isEmpty)

        let meetingStore = MeetingPointStore(defaults: defaults)
        meetingStore.setMeetingPoint("By the big oak tree", forHomeID: homeID)
        XCTAssertEqual(meetingStore.meetingPoint(forHomeID: homeID), "By the big oak tree")

        defaults.set(14, forKey: "readiness.wallEdgeCount.\(homeID)")
        XCTAssertEqual(defaults.integer(forKey: "readiness.wallEdgeCount.\(homeID)"), 14)

        let scoreCache = try ScoreCache(fileManager: .default)
        let score = ScoreBreakdown(home_id: homeID, home_name: home.name, score: 80, sub_scores: [:], basis: nil, components: [], checklist: [])
        scoreCache.save(score, for: homeID)
        XCTAssertNotNil(scoreCache.load(homeID: homeID))

        // Create a dummy route cache file in <Documents>/RouteCache
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let routeDir = docs.appendingPathComponent("RouteCache", isDirectory: true)
        try FileManager.default.createDirectory(at: routeDir, withIntermediateDirectories: true)
        let routeFile = routeDir.appendingPathComponent("\(homeID).fire.household.routeplan.v2.json")
        try Data("{}".utf8).write(to: routeFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: routeFile.path))

        // Perform cleanup
        HomeLibrary.cleanupAuxiliaryStores(homeID: homeID, defaults: defaults, fileManager: .default)

        // Assert all auxiliary stores are cleanly purged
        XCTAssertTrue(checklistStore.load(homeID: homeID).isEmpty, "ChecklistStateStore must be cleared")
        XCTAssertEqual(meetingStore.meetingPoint(forHomeID: homeID), "", "MeetingPointStore must be cleared")
        XCTAssertNil(defaults.object(forKey: "readiness.wallEdgeCount.\(homeID)"), "Wall edge count must be cleared")
        XCTAssertNil(scoreCache.load(homeID: homeID), "ScoreCache must be removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: routeFile.path), "RouteCache file must be removed")
    }
}
