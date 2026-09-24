//  ReadinessScanFreshnessStoreTests.swift — the per-home wall-edge snapshot store, following
//  the MeetingPointStore / ChecklistStateStore UserDefaults precedent (S11.5).

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class ReadinessScanFreshnessStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ReadinessScanFreshnessStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRecordedCountIsNilBeforeAnythingIsRecorded() {
        let store = ScanFreshnessStore(defaults: defaults)
        XCTAssertNil(store.recordedWallEdgeCount(homeID: "home-1"))
    }

    func testRecordAndReadBack() {
        let store = ScanFreshnessStore(defaults: defaults)
        store.recordWallEdgeCount(16, homeID: "home-1")
        XCTAssertEqual(store.recordedWallEdgeCount(homeID: "home-1"), 16)
    }

    func testRecordingZeroIsDistinguishableFromNeverRecorded() {
        // The naive `defaults.integer(forKey:)` returns 0 for a missing key too, so a store
        // that didn't check `object(forKey:)` first would conflate "no baseline" with "a home
        // with zero walls" and silently suppress the walls-changed nudge forever.
        let store = ScanFreshnessStore(defaults: defaults)
        store.recordWallEdgeCount(0, homeID: "home-1")
        XCTAssertEqual(store.recordedWallEdgeCount(homeID: "home-1"), 0)
    }

    func testReRecordingOverwritesRatherThanAccumulating() {
        let store = ScanFreshnessStore(defaults: defaults)
        store.recordWallEdgeCount(16, homeID: "home-1")
        store.recordWallEdgeCount(20, homeID: "home-1")
        XCTAssertEqual(store.recordedWallEdgeCount(homeID: "home-1"), 20)
    }

    func testHomesAreIsolatedFromEachOther() {
        let store = ScanFreshnessStore(defaults: defaults)
        store.recordWallEdgeCount(16, homeID: "home-1")
        store.recordWallEdgeCount(24, homeID: "home-2")
        XCTAssertEqual(store.recordedWallEdgeCount(homeID: "home-1"), 16)
        XCTAssertEqual(store.recordedWallEdgeCount(homeID: "home-2"), 24)
    }
}
