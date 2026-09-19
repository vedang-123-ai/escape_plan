//  AuthValidationTests.swift — the client rule agrees with the server rule.
//
//  Every address below was run through BOTH this validator and the backend's own
//  `normalise_email` (backend/app/cloud_models.py) on 2026-09-15; the two agreed on all 22,
//  and the expectations here are those recorded verdicts. That is the point of the file: a
//  client check that disagrees with the server is worse than no client check at all, because
//  it either blocks a usable address or promises one the server will then reject.
//
//  Several look wrong and are deliberately accepted — "ada@b..co" and ".ada@b.co" both pass on
//  the server too. The rule is "catch obvious junk", not "implement RFC 5322".

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class AuthValidationTests: XCTestCase {

    /// (address, what the BACKEND says) — recorded, not predicted.
    private static let corpus: [(String, Bool)] = [
        ("ada@example.com", true),
        ("ADA@Example.COM", true),
        ("  ada@example.com  ", true),
        ("a@b.co", true),
        ("first.last+tag@sub.domain.co.uk", true),
        ("ada@example.c", true),
        ("ada@ex.ample.com", true),
        ("üser@exämple.com", true),
        ("a@b.c", true),
        ("ada@b..co", true),
        (".ada@b.co", true),
        ("ada@-b.co", true),
        ("no-at-sign.com", false),
        ("two@@example.com", false),
        ("@example.com", false),
        ("ada@", false),
        ("ada@localhost", false),
        ("ada@.com", false),
        ("ada@com.", false),
        ("ada @example.com", false),
        ("ada@exa mple.com", false),
        ("ada@@b.co", false),
    ]

    func testAgreesWithTheBackendOnEveryRecordedAddress() {
        for (address, serverAccepts) in Self.corpus {
            XCTAssertEqual(AuthValidation.isValid(email: address), serverAccepts,
                           "client and server disagree about \(address.debugDescription)")
        }
    }

    /// The server stores addresses normalised, so signing up as "Ada@Example.com" and later
    /// signing in as "ada@example.com" must reach the same account.
    func testNormalisationMatchesTheServer() {
        XCTAssertEqual(AuthValidation.normalise(email: "  ADA@Example.COM \n"), "ada@example.com")
    }

    func testRejectsAnAddressLongerThanTheServersColumn() {
        let tooLong = String(repeating: "a", count: 250) + "@example.com"
        XCTAssertFalse(AuthValidation.isValid(email: tooLong))
    }

    // MARK: - Passwords

    func testPasswordFloorMatchesTheServersMinLength() {
        XCTAssertEqual(AuthValidation.minimumPasswordLength, 8)
        XCTAssertFalse(AuthValidation.isValid(password: "sevench"))
        XCTAssertTrue(AuthValidation.isValid(password: "eightchr"))
    }

    /// Argon2 has no input length cap, so the server's 1024 is the only limit and there are no
    /// composition rules on either side.
    func testLongPassphrasesAreFine() {
        XCTAssertTrue(AuthValidation.isValid(password: String(repeating: "x", count: 1024)))
        XCTAssertFalse(AuthValidation.isValid(password: String(repeating: "x", count: 1025)))
    }

    // MARK: - Which problem gets reported

    func testEmailIsReportedBeforePasswordJustLikeTheServer() {
        let problem = AuthValidation.problem(email: "nope", password: "x")
        XCTAssertEqual(problem?.message, "That doesn't look like an email address.")
    }

    func testShortPasswordIsReportedWhenTheEmailIsFine() {
        let problem = AuthValidation.problem(email: "ada@example.com", password: "short")
        XCTAssertEqual(problem?.kind, .rejectedInput)
        XCTAssertTrue(problem?.message.contains("8 characters") == true)
    }

    func testGoodCredentialsHaveNoProblem() {
        XCTAssertNil(AuthValidation.problem(email: "ada@example.com", password: "a-good-password"))
    }
}
