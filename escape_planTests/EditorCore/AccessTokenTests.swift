//  AccessTokenTests.swift — reading a real backend JWT locally.
//
//  Every token literal below was signed by the project's OWN backend
//  (`app.auth.tokens.create_access_token`, PyJWT, HS256) on 2026-09-15, not hand-assembled.
//  That matters: the claim names, the NumericDate encoding and the base64url alphabet are all
//  things a hand-made fixture would get plausibly-but-subtly wrong, and then the test would be
//  pinning our own misunderstanding rather than the server's behaviour.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class AccessTokenTests: XCTestCase {

    /// sub "user-abc-123", iat 1789537141, exp 1789540741.
    private static let valid =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
      + "eyJzdWIiOiJ1c2VyLWFiYy0xMjMiLCJpYXQiOjE3ODk1MzcxNDEsImV4cCI6MTc4OTU0MDc0MX0."
      + "1jeLV6so2LE7_DrvW62MJ2RmMm_QkWBUkAxzK_-HHPk"

    /// Same subject, issued already expired (exp 1789536841).
    private static let expired =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
      + "eyJzdWIiOiJ1c2VyLWFiYy0xMjMiLCJpYXQiOjE3ODk1MzcxNDEsImV4cCI6MTc4OTUzNjg0MX0."
      + "m20FaQJiN6vYFyvT2PXRJWx-8_Ansd1ql1krHk-1ZyM"

    private static let issuedAt = Date(timeIntervalSince1970: 1789537141)

    func testReadsSubjectAndExpiry() {
        let token = AccessToken(raw: Self.valid)
        XCTAssertEqual(token.subject, "user-abc-123")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 1789540741))
    }

    func testRawIsPreservedExactly() {
        // This is what goes in the Authorization header — any normalisation here is a 401.
        XCTAssertEqual(AccessToken(raw: Self.valid).raw, Self.valid)
    }

    func testFreshTokenIsNotExpired() {
        XCTAssertFalse(AccessToken(raw: Self.valid).isExpired(now: Self.issuedAt))
    }

    func testPastExpiryIsExpired() {
        XCTAssertTrue(AccessToken(raw: Self.expired).isExpired(now: Self.issuedAt))
    }

    /// A token with seconds left is treated as already gone, so a request cannot leave with a
    /// live token and arrive with a dead one.
    func testTokenInsideTheLeewayCountsAsExpired() {
        let token = AccessToken(raw: Self.valid)
        let tenSecondsBeforeExpiry = Date(timeIntervalSince1970: 1789540731)
        XCTAssertTrue(token.isExpired(now: tenSecondsBeforeExpiry, leeway: 30))
        XCTAssertFalse(token.isExpired(now: tenSecondsBeforeExpiry, leeway: 0))
    }

    /// Payload segment "…Pz4_Pngi…" — a real token whose base64 contains the URL-safe "_".
    /// `Data(base64Encoded:)` returns nil for this without the alphabet swap, which would
    /// present as "the app randomly forgets who you are" for some fraction of accounts.
    func testDecodesBase64URLAlphabet() {
        let urlSafe =
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
          + "eyJzdWIiOiJ1c2VyPz4_PngiLCJpYXQiOjE3ODk1MzcxNTQsImV4cCI6MTc4OTU0MDc1NH0."
          + "Z8YRzsAptqCeMdcnysaf6JW6fXh76zohQz4WXtCZ2b0"
        XCTAssertEqual(AccessToken(raw: urlSafe).subject, "user?>?>x")
    }

    // MARK: - Every failure falls back to "don't know", never to "expired"

    /// Locking someone out because of a parsing bug is far worse than sending one request the
    /// server then rejects. All four of these must be usable, not blocked.
    func testUnparseableTokensAreNotTreatedAsExpired() {
        for junk in ["", "not-a-jwt", "only.two", "a.!!!not-base64!!!.c"] {
            let token = AccessToken(raw: junk)
            XCTAssertNil(token.expiresAt, "\(junk) should have no known expiry")
            XCTAssertFalse(token.isExpired(now: Self.issuedAt),
                           "\(junk) must fall back to 'send it and let the server decide'")
        }
    }

    /// A well-formed token that simply carries no `exp`. The backend refuses to ISSUE one
    /// (`require: [exp, iat, sub]` in app/auth/tokens.py), so this only arrives if something
    /// upstream changes — and the client's job is still to ask the server, not to guess.
    func testTokenWithoutExpiryIsUsable() {
        // {"sub":"u1"} — base64url, unpadded.
        let noExp = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1MSJ9.sig"
        let token = AccessToken(raw: noExp)
        XCTAssertEqual(token.subject, "u1")
        XCTAssertNil(token.expiresAt)
        XCTAssertFalse(token.isExpired(now: Self.issuedAt))
    }
}
