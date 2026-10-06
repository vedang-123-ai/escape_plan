//  S1157DefectFixTests.swift — the pure halves of the S11.57 fixes, run by both the app suite and
//  `swift test --package-path tools/editorcore`:
//  - S53-2: which home opens (`ActiveHomeMemory`).
//  - S53-5: counts with a noun that agrees ("1 issue", not "1 issues").
//  - Owner decision 2026-10-05: the alarm test stopped recurring; a cached 30-day recurrence and
//    an old stored date both read as a plain one-time tick.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class ActiveHomeMemoryTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "ActiveHomeMemoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testRememberedHomeWinsWhenItStillExists() {
        XCTAssertEqual(ActiveHomeMemory.choose(remembered: "b", available: ["a", "b", "demo"], demoHomeID: "demo"), "b")
    }

    func testDemoHomeOpensWhenNothingIsRemembered() {
        XCTAssertEqual(ActiveHomeMemory.choose(remembered: nil, available: ["a", "b", "demo"], demoHomeID: "demo"), "demo")
    }

    func testDeletedRememberedHomeFallsBackToTheDemoHome() {
        XCTAssertEqual(ActiveHomeMemory.choose(remembered: "gone", available: ["a", "demo"], demoHomeID: "demo"), "demo")
    }

    func testWithNoDemoHomeTheFirstHomeOpens() {
        XCTAssertEqual(ActiveHomeMemory.choose(remembered: "gone", available: ["a", "b"], demoHomeID: "demo"), "a")
        XCTAssertNil(ActiveHomeMemory.choose(remembered: "gone", available: [], demoHomeID: "demo"))
    }

    func testRememberAndForgetRoundTripThroughDefaults() {
        let memory = ActiveHomeMemory(defaults: defaults)
        XCTAssertNil(memory.remembered)
        memory.remember("home-1")
        XCTAssertEqual(ActiveHomeMemory(defaults: defaults).remembered, "home-1", "a new instance reads it back")
        memory.remember(nil)
        XCTAssertNil(ActiveHomeMemory(defaults: defaults).remembered)
    }
}

final class CountPhraseTests: XCTestCase {
    func testSingularOnlyForOne() {
        XCTAssertEqual(CountPhrase.of(1, "issue"), "1 issue")
        XCTAssertEqual(CountPhrase.of(2, "issue"), "2 issues")
        XCTAssertEqual(CountPhrase.of(0, "item"), "0 items")
        XCTAssertEqual(CountPhrase.of(1, "item"), "1 item")
    }

    func testIrregularPlural() {
        XCTAssertEqual(CountPhrase.of(1, "person", plural: "people"), "1 person")
        XCTAssertEqual(CountPhrase.of(3, "person", plural: "people"), "3 people")
    }
}

final class RetiredRecurrenceTests: XCTestCase {
    private func item(id: String) throws -> ChecklistItem {
        try JSONDecoder().decode(ChecklistItem.self, from: Data("""
        {"id": "\(id)", "category": "smoke_alarm", "title": "t", "detail": "d", "done": true,
         "scoring": true, "recurrence_days": 30, "completed_at": "2026-10-01T00:00:00Z"}
        """.utf8))
    }

    func testACachedAlarmTestRecurrenceIsDropped() throws {
        let alarm = try item(id: "alarm.test_monthly")
        XCTAssertNil(alarm.recurrence_days)
        XCTAssertNil(alarm.completed_at)
        XCTAssertNil(alarm.recurrenceLabel(now: Date()), "no 'due in ...' line")
    }

    func testOtherRecurringItemsKeepTheirRecurrence() throws {
        let drill = try item(id: "practice.drill_recent")
        XCTAssertEqual(drill.recurrence_days, 30)
        XCTAssertNotNil(drill.recurrenceLabel(now: Date()))
    }

    func testAnOldStoredAlarmDateIsATick() {
        let date = Date(timeIntervalSince1970: 1_787_659_200)
        XCTAssertEqual(ChecklistMark.completed(date).normalized(forItem: "alarm.test_monthly"), .flag(true))
        XCTAssertEqual(ChecklistMark.completed(date).normalized(forItem: "practice.drill_recent"), .completed(date))
        XCTAssertEqual(ChecklistMark.flag(false).normalized(forItem: "alarm.test_monthly"), .flag(false))
    }
}
