//  S1157AccessibilityTests.swift — S53-4 and S53-5 (simulator walk 2026-10-05), the parts that
//  are words: what VoiceOver reads and what a chip shows at the largest text sizes. The layout
//  half is pinned by `escape_planUITests/LargestTextUITests.swift`.

import XCTest

@testable import escape_plan

final class S1157AccessibilityTests: XCTestCase {

    /// S53-5: "1 issues" beside Route check and Simulation check.
    func testIssueBadgeAgreesWithItsCount() {
        XCTAssertEqual(HouseSceneAccessibility.issueBadgeLabel(1), "1 issue")
        XCTAssertEqual(HouseSceneAccessibility.issueBadgeLabel(3), "3 issues")
    }

    /// S53-5: "Done, 1 items" on the Tasks group header.
    func testTaskGroupHeaderAgreesWithItsCount() {
        XCTAssertEqual(TaskGroupSpeech.label(title: "Done", count: 1), "Done, 1 item")
        XCTAssertEqual(TaskGroupSpeech.label(title: "To do", count: 39), "To do, 39 items")
        XCTAssertEqual(TaskGroupSpeech.label(title: "Urgent", count: 0), "Urgent, 0 items")
    }

    /// S53-5: the "Who does what" icons exposed `figure.stand`, `arrow.forward`,
    /// `door.left.hand.open`. Every icon now has a spoken word, never a symbol name.
    func testWhoDoesWhatIconsHaveSpokenWordsNotSymbolNames() {
        for icon in PersonLineIcon.allCases {
            XCTAssertNotEqual(icon.spokenLabel, icon.symbol)
            XCTAssertFalse(icon.spokenLabel.contains("."), "\(icon): \(icon.spokenLabel)")
            XCTAssertFalse(icon.spokenLabel.isEmpty)
        }
        XCTAssertEqual(PersonLineIcon.exitDoor.spokenLabel, "Leaves by a door")
        XCTAssertEqual(PersonLineIcon.exitWindow.spokenLabel, "Leaves by a window")
    }

    /// S53-4: at XXXL every floor chip read "…". It shows the floor's number there, and the
    /// name everywhere else (the default look is unchanged).
    func testFloorChipShowsTheNumberOnlyAtAccessibilitySizes() {
        XCTAssertEqual(HouseScreen.floorChipTitle(name: "Ground Floor", number: 1, accessibilitySize: false),
                       "Ground Floor")
        XCTAssertEqual(HouseScreen.floorChipTitle(name: "Upper Floor", number: 2, accessibilitySize: true), "2")
    }
}
