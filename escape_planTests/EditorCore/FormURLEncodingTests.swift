//  FormURLEncodingTests.swift — the /auth/login body, byte for byte.
//
//  The expected strings below are not hand-written. Each one was produced by this encoder and
//  then fed to Python's `urllib.parse.parse_qsl` — the parser Starlette uses for
//  `application/x-www-form-urlencoded` — and confirmed to decode back to the original email
//  and password (2026-09-15). So these literals are a recorded cross-language contract, not
//  someone's idea of what percent-encoding should look like.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class FormURLEncodingTests: XCTestCase {

    private func encoded(username: String, password: String) -> String {
        String(decoding: FormURLEncoding.body([("username", username),
                                               ("password", password)]), as: UTF8.self)
    }

    /// The field is `username`, not `email` — OAuth2PasswordRequestForm names it that, and
    /// sending `email=` is a 422 whose body never mentions the actual problem.
    func testLoginFieldIsCalledUsername() {
        XCTAssertTrue(encoded(username: "a@b.co", password: "x").hasPrefix("username=a%40b.co&"))
    }

    /// The bug this file exists to prevent: "+" must survive as "+", not arrive as a space.
    /// URLComponents.query does not escape it, which is why this encoder is hand-rolled.
    func testPlusInPasswordIsEscapedNotTreatedAsSpace() {
        XCTAssertEqual(encoded(username: "plus+user@example.com", password: "p+ssw0rd with spaces"),
                       "username=plus%2Buser%40example.com&password=p%2Bssw0rd%20with%20spaces")
    }

    func testFormDelimitersInAPasswordAreEscaped() {
        XCTAssertEqual(encoded(username: "a.b-c_d~e@sub.example.co.uk", password: #"&=?#%/\"#),
                       "username=a.b-c_d~e%40sub.example.co.uk&password=%26%3D%3F%23%25%2F%5C")
    }

    /// Unreserved characters stay literal (RFC 3986). Over-escaping is harmless but makes the
    /// body unreadable in a proxy log, and "~" in particular is escaped by several encoders.
    func testUnreservedCharactersAreLeftAlone() {
        XCTAssertEqual(FormURLEncoding.escape("a.b-c_d~e"), "a.b-c_d~e")
    }

    func testNonASCIIIsUTF8PercentEncoded() {
        XCTAssertEqual(encoded(username: "unicode@exämple.com", password: "pä§§wörd🔥"),
                       "username=unicode%40ex%C3%A4mple.com"
                     + "&password=p%C3%A4%C2%A7%C2%A7w%C3%B6rd%F0%9F%94%A5")
    }

    func testControlCharactersAreEscaped() {
        XCTAssertEqual(encoded(username: "x@y.co", password: "tabs\tand\nnewlines"),
                       "username=x%40y.co&password=tabs%09and%0Anewlines")
    }

    func testFieldOrderIsPreserved() {
        let body = String(decoding: FormURLEncoding.body([("b", "1"), ("a", "2")]), as: UTF8.self)
        XCTAssertEqual(body, "b=1&a=2")
    }

    func testEmptyPasswordStillProducesTheField() {
        XCTAssertEqual(encoded(username: "a@b.co", password: ""), "username=a%40b.co&password=")
    }
}
