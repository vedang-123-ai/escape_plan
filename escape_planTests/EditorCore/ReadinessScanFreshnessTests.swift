//  ReadinessScanFreshnessTests.swift — scan-age display and the re-scan nudge (S11.5), the
//  Home tab's answer to the firefighter's "remodels make stored layouts stale" warning.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class ReadinessScanFreshnessTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - daysSince / age text

    func testDaysSinceUsesLastScannedWhenPresent() {
        let scanned = now.addingTimeInterval(-10 * 86400)
        let modified = now.addingTimeInterval(-1 * 86400)
        XCTAssertEqual(ScanFreshness.daysSince(lastScanned: scanned, modified: modified, now: now), 10)
    }

    func testDaysSinceFallsBackToModifiedWhenNeverScanned() {
        let modified = now.addingTimeInterval(-42 * 86400)
        XCTAssertEqual(ScanFreshness.daysSince(lastScanned: nil, modified: modified, now: now), 42)
    }

    func testDaysSinceIsNilForAFutureReference() {
        let future = now.addingTimeInterval(3600)
        XCTAssertNil(ScanFreshness.daysSince(lastScanned: future, modified: now, now: now))
    }

    func testScanAgeTextSaysBuiltByHandWithNoScanAtAll() {
        XCTAssertEqual(ScanFreshness.scanAgeText(lastScanned: nil, modified: now, now: now),
                       "Built by hand — not yet scanned.")
    }

    func testScanAgeTextSingularVsPlural() {
        let today = now
        let yesterday = now.addingTimeInterval(-86400)
        let lastWeek = now.addingTimeInterval(-7 * 86400)
        XCTAssertEqual(ScanFreshness.scanAgeText(lastScanned: today, modified: today, now: now),
                       "Scanned today.")
        XCTAssertEqual(ScanFreshness.scanAgeText(lastScanned: yesterday, modified: yesterday, now: now),
                       "Scanned 1 day ago.")
        XCTAssertEqual(ScanFreshness.scanAgeText(lastScanned: lastWeek, modified: lastWeek, now: now),
                       "Scanned 7 days ago.")
    }

    // MARK: - Staleness by age

    func testIsStaleByAgeExactlyAtThresholdIsNotYetStale() {
        XCTAssertFalse(ScanFreshness.isStaleByAge(days: ScanFreshness.staleThresholdDays))
        XCTAssertTrue(ScanFreshness.isStaleByAge(days: ScanFreshness.staleThresholdDays + 1))
    }

    func testIsStaleByAgeIsFalseForNilDays() {
        XCTAssertFalse(ScanFreshness.isStaleByAge(days: nil))
    }

    // MARK: - Wall-edge counting

    func testWallEdgeCountSumsEveryRoomPolygonAcrossFloors() throws {
        let home = try Fixtures.load("bungalow")
        let expected = home.floors.reduce(0) { $0 + $1.rooms.reduce(0) { $0 + $1.polygon.count } }
        XCTAssertEqual(ScanFreshness.wallEdgeCount(home), expected)
        // Known shape of the fixture: four rectangular rooms, four edges each.
        XCTAssertEqual(ScanFreshness.wallEdgeCount(home), 16)
    }

    func testWallsChangedIsFalseWithNoRecordedBaseline() {
        XCTAssertFalse(ScanFreshness.wallsChanged(currentEdgeCount: 20, recordedEdgeCount: nil))
    }

    func testWallsChangedDetectsAnyDifference() {
        XCTAssertTrue(ScanFreshness.wallsChanged(currentEdgeCount: 20, recordedEdgeCount: 16))
        XCTAssertTrue(ScanFreshness.wallsChanged(currentEdgeCount: 12, recordedEdgeCount: 16))
        XCTAssertFalse(ScanFreshness.wallsChanged(currentEdgeCount: 16, recordedEdgeCount: 16))
    }

    // MARK: - Nudge reason & wording

    func testWallsEditedTakesPriorityOverStaleness() {
        XCTAssertEqual(ScanFreshness.nudgeReason(daysSinceScan: 400, wallsChanged: true), .wallsEdited)
    }

    func testStaleAloneIsReportedWhenWallsHaveNotChanged() {
        XCTAssertEqual(ScanFreshness.nudgeReason(daysSinceScan: 200, wallsChanged: false), .stale)
    }

    func testNoNudgeWhenFreshAndUnchanged() {
        XCTAssertNil(ScanFreshness.nudgeReason(daysSinceScan: 5, wallsChanged: false))
    }

    func testNudgeMessagesAreHonestAboutResidentMaintenance() {
        for reason in [ScanFreshness.NudgeReason.stale, .wallsEdited] {
            let message = ScanFreshness.nudgeMessage(reason)
            XCTAssertTrue(message.contains("resident-maintained"),
                          "the nudge must never imply the plan was verified: \(message)")
        }
    }
}
