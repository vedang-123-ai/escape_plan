//  HomeIDTests.swift — S11.41 (AUD-012): the rule a `home_id` must pass before it is a file name.
//
//  Two halves, and both matter. The rejections are the security fix. The acceptances are the
//  promise that no home already on someone's phone stops loading because of it: every id format
//  the app or its tests produce today is listed here by where it comes from.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class HomeIDTests: XCTestCase {

    // MARK: - Every id in use today passes

    func testEveryBundledFixtureIDIsValid() throws {
        for fixture in HomeFixture.allCases {
            let home = try FixtureLoader.load(fixture)
            XCTAssertTrue(HomeID.isValid(home.home_id), "\(fixture): \(home.home_id)")
        }
    }

    func testEveryIDFormatTheAppProducesIsValid() {
        let ids = [
            UUID().uuidString.lowercased(),            // FixtureSeeder, duplicate, import
            UUID().uuidString,                         // HouseScreen.blankHome, HomeModelStore.newHome
            HomeModelStore.newHome(name: "x").home_id, // the real call, not a copy of it
            "TEST-DEMO-HOME-1234",                     // escape_planApp's DEBUG UI-test seed
            "9a5e6d34-2c3f-4a1b-8d70-empty-123",       // twostory-empty fixture, not a UUID
            "preserved-\(UUID().uuidString.lowercased())-12", // sync test double's copies
            "home-1", "existing-home", "seed-test", "home-alice", "h_bounds", "h",
        ]
        for id in ids {
            XCTAssertTrue(HomeID.isValid(id), id)
            XCTAssertNoThrow(try HomeID.validate(id), id)
        }
    }

    func testSixtyFourCharactersIsTheLongestAccepted() {
        XCTAssertTrue(HomeID.isValid(String(repeating: "a", count: 64)))
        XCTAssertFalse(HomeID.isValid(String(repeating: "a", count: 65)))
    }

    // MARK: - Anything that is not a plain file name is refused

    func testPathTraversalAndSeparatorsAreRejected() {
        let hostile = [
            "", ".", "..", "../x", "../../Library/Preferences/x", "a/b", "/abs", "a\\b",
            ".hidden", "a.b", "home id", "home\u{0}id", "home\nid",
            "caf\u{E9}",       // non-ASCII letter
            "\u{FF0E}\u{FF0E}", // full-width dots
        ]
        for id in hostile {
            XCTAssertFalse(HomeID.isValid(id), "accepted \(id.debugDescription)")
            XCTAssertThrowsError(try HomeID.validate(id), id.debugDescription) { error in
                XCTAssertEqual(error as? InvalidHomeID, InvalidHomeID(homeID: id))
            }
        }
    }
}
