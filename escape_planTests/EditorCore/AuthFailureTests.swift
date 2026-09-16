//  AuthFailureTests.swift — status codes and real error bodies become sentences.
//
//  The 422 bodies below are verbatim captures from the project's own backend via
//  `fastapi.testclient` on 2026-09-15, not invented. FastAPI returns two different shapes
//  under the same `detail` key — a String for HTTPException, a list of objects for a
//  validation error — and code that assumes the String shape throws on the one status where
//  the body is actually worth reading.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class AuthFailureTests: XCTestCase {

    // MARK: - Status codes

    /// 401 must NOT say "check your token in Settings" the way BackendFailure does. On a login
    /// form the token is not the problem and Settings cannot help.
    func testWrongPasswordIsNotRetryableAndDoesNotMentionSettings() {
        let failure = AuthFailure(statusCode: 401)
        XCTAssertEqual(failure.kind, .invalidCredentials)
        XCTAssertFalse(failure.isRetryable)
        XCTAssertFalse(failure.message.lowercased().contains("settings"))
    }

    func testDuplicateEmailPointsAtSigningInInstead() {
        let failure = AuthFailure(statusCode: 409)
        XCTAssertEqual(failure.kind, .emailAlreadyRegistered)
        XCTAssertTrue(failure.message.lowercased().contains("signing in"))
        XCTAssertFalse(failure.isRetryable)
    }

    /// The real body a login gets when the server has no MONGODB_URI, captured 2026-09-15:
    /// {"detail": "Cloud sync is not configured on this server."}
    ///
    /// This must not be retryable and must not claim the server is "busy" — no amount of
    /// retrying sets an environment variable. It must also reassure, because the app is
    /// fully usable without an account.
    func testUnconfiguredCloudSyncIsExplainedNotDisguisedAsBusy() {
        let failure = AuthFailure(statusCode: 503)
        XCTAssertEqual(failure.kind, .cloudSyncUnavailable)
        XCTAssertFalse(failure.isRetryable)
        XCTAssertFalse(failure.message.lowercased().contains("busy"))
        XCTAssertTrue(failure.message.lowercased().contains("keeps working"))
    }

    func testUnknownStatusIsRetryableAndNamesTheCode() {
        let failure = AuthFailure(statusCode: 500)
        XCTAssertEqual(failure.kind, .server(statusCode: 500))
        XCTAssertTrue(failure.isRetryable)
        XCTAssertTrue(failure.message.contains("500"))
    }

    // MARK: - 422, with the bodies the server really sends

    private static let badEmailBody = Data(#"""
    {"detail":[{"type":"value_error","loc":["body","email"],
     "msg":"Value error, not a usable email address: 'not-an-email'",
     "input":"not-an-email","ctx":{"error":{}}}]}
    """#.utf8)

    private static let shortPasswordBody = Data(#"""
    {"detail":[{"type":"string_too_short","loc":["body","password"],
     "msg":"String should have at least 8 characters","input":"short",
     "ctx":{"min_length":8}}]}
    """#.utf8)

    private static let bothBadBody = Data(#"""
    {"detail":[{"type":"value_error","loc":["body","email"],
     "msg":"Value error, not a usable email address: 'nope'","input":"nope","ctx":{"error":{}}},
    {"type":"string_too_short","loc":["body","password"],
     "msg":"String should have at least 8 characters","input":"x","ctx":{"min_length":8}}]}
    """#.utf8)

    func testBadEmailBodyBecomesAnEmailMessage() {
        let failure = AuthFailure(statusCode: 422, body: Self.badEmailBody)
        XCTAssertEqual(failure.kind, .rejectedInput)
        XCTAssertEqual(failure.message, "That doesn't look like an email address.")
    }

    func testShortPasswordBodyBecomesAPasswordMessage() {
        let failure = AuthFailure(statusCode: 422, body: Self.shortPasswordBody)
        XCTAssertTrue(failure.message.contains("8 characters"))
    }

    /// When both fields are wrong the server lists email first. Follow that order, so the user
    /// is sent to the first field on the form rather than the last one we happened to check.
    func testBothFieldsWrongReportsTheFirstOneTheServerListed() {
        XCTAssertEqual(AuthFailure(statusCode: 422, body: Self.bothBadBody).message,
                       "That doesn't look like an email address.")
    }

    /// The pydantic error objects carry an `input` key echoing the rejected value — for a
    /// password error that IS the password. Nothing we show may contain it.
    func testRejectionMessageNeverEchoesTheSubmittedValue() {
        for body in [Self.badEmailBody, Self.shortPasswordBody, Self.bothBadBody] {
            let message = AuthFailure(statusCode: 422, body: body).message
            XCTAssertFalse(message.contains("not-an-email"))
            XCTAssertFalse(message.contains("short"), "leaked the submitted password")
            XCTAssertFalse(message.contains("nope"))
        }
    }

    /// A 422 whose body we cannot read must still produce a sentence, not a crash.
    func testUnreadable422StillProducesAMessage() {
        for body in [nil, Data(), Data("not json".utf8),
                     Data(#"{"detail":"a plain string, the other FastAPI shape"}"#.utf8)] {
            let failure = AuthFailure(statusCode: 422, body: body)
            XCTAssertEqual(failure.kind, .rejectedInput)
            XCTAssertFalse(failure.message.isEmpty)
        }
    }

    // MARK: - Transport

    /// Render's free tier sleeps, so the first request after an idle period can take most of a
    /// minute. Calling that "you're offline" sends the user to go fix their wifi.
    func testTimeoutIsNotReportedAsBeingOffline() {
        let failure = AuthFailure(transport: URLError(.timedOut))
        XCTAssertEqual(failure.kind, .timedOut)
        XCTAssertTrue(failure.isRetryable)
        XCTAssertFalse(failure.message.lowercased().contains("offline"))
        XCTAssertTrue(failure.message.lowercased().contains("waking up"))
    }

    /// Being offline is the one case worth saying what still works, because it all still does.
    func testOfflineSaysWhatStillWorks() {
        for code: URLError.Code in [.notConnectedToInternet, .networkConnectionLost,
                                    .cannotConnectToHost, .dataNotAllowed, .cannotFindHost] {
            let failure = AuthFailure(transport: URLError(code))
            XCTAssertEqual(failure.kind, .offline, "\(code)")
            XCTAssertTrue(failure.message.contains("escape routes still work"))
        }
    }

    func testUnrecognisedTransportErrorFallsBackToReachability() {
        let failure = AuthFailure(transport: URLError(.badServerResponse))
        XCTAssertEqual(failure.kind, .server(statusCode: -1))
        XCTAssertTrue(failure.isRetryable)
    }
}
