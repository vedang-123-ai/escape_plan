//  ChecklistStateStoreTests.swift
//  escape_planTests
//
//  S3.5's UserDefaults sidecar for per-home checklist done-state. Uses a throwaway
//  UserDefaults suite per test (same pattern as PersistenceTests' DeviceIdentity test) so
//  nothing leaks into the simulator's standard defaults.

import XCTest
@testable import escape_plan

final class ChecklistStateStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ChecklistStateStore!

    override func setUpWithError() throws {
        suiteName = "ChecklistStateStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = ChecklistStateStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLoadWithNothingSavedReturnsEmpty() {
        XCTAssertEqual(store.load(homeID: "home-1"), [:],
                       "missing state means 'nothing done yet', never an error")
    }

    func testSaveLoadRoundTrip() {
        let state = ["alarm.every_level": true, "practice.meeting_point": false]
        store.save(state, homeID: "home-1")
        XCTAssertEqual(store.load(homeID: "home-1"), state)
    }

    func testHomesDoNotCrossContaminate() {
        store.save(["alarm.every_level": true], homeID: "home-1")
        store.save(["practice.meeting_point": true], homeID: "home-2")

        XCTAssertEqual(store.load(homeID: "home-1"), ["alarm.every_level": true])
        XCTAssertEqual(store.load(homeID: "home-2"), ["practice.meeting_point": true])
        XCTAssertEqual(store.load(homeID: "home-3"), [:])
    }

    func testSecondSaveReplacesTheFirstEntirely() {
        store.save(["alarm.every_level": true, "alarm.tested_monthly": true], homeID: "home-1")
        store.save(["practice.meeting_point": true], homeID: "home-1")

        XCTAssertEqual(store.load(homeID: "home-1"), ["practice.meeting_point": true],
                       "save is whole-state replacement, not a merge — the screen owns the full dict")
    }

    func testStateIsStoredUnderTheDocumentedKeyScheme() {
        // The "checklistState.<home_id>" scheme is documented in the source header and in
        // docs/decisions.md (orphan cleanup on home delete depends on it) — pin it.
        store.save(["alarm.every_level": true], homeID: "home-1")
        XCTAssertEqual(defaults.dictionary(forKey: "checklistState.home-1") as? [String: Bool],
                       ["alarm.every_level": true])
        XCTAssertNil(defaults.dictionary(forKey: "checklistState.home-2"))
    }

    func testCorruptStoredValueLoadsAsEmptyInsteadOfCrashing() {
        // Plant a dict whose values aren't Bool — the whole [String: Bool] cast fails and
        // load falls back to [:] (fresh checklist), mirroring ConversationStore's
        // corrupt-file contract.
        defaults.set(["alarm.every_level": "yes"], forKey: "checklistState.home-1")
        XCTAssertEqual(store.load(homeID: "home-1"), [:])

        defaults.set("not a dictionary", forKey: "checklistState.home-2")
        XCTAssertEqual(store.load(homeID: "home-2"), [:])
    }

    func testStateSurvivesRelaunch() {
        store.save(["alarm.every_level": true], homeID: "home-1")

        // A fresh store over the same suite is the unit-level equivalent of an app relaunch.
        let relaunched = ChecklistStateStore(defaults: UserDefaults(suiteName: suiteName)!)
        XCTAssertEqual(relaunched.load(homeID: "home-1"), ["alarm.every_level": true])
    }
}
