//  TokenStoreTests.swift — the contract every TokenStore must satisfy.
//
//  `assertTokenStoreContract` is deliberately written against the protocol rather than against
//  InMemoryTokenStore, so the SAME assertions can be pointed at the real Keychain during the
//  device pass. `KeychainTokenStoreTests` in the app target does exactly that; it cannot run
//  here, because a macOS unit-test bundle has no keychain-access entitlement.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

/// Shared by the in-memory double here and the Keychain on a device.
func assertTokenStoreContract(_ store: TokenStore,
                              file: StaticString = #filePath,
                              line: UInt = #line) throws {
    try store.delete()
    XCTAssertNil(store.load(), "a cleared store must read back empty", file: file, line: line)

    try store.save("first.token.value")
    XCTAssertEqual(store.load(), "first.token.value", file: file, line: line)

    // Re-saving must overwrite, not duplicate or silently keep the old value — this is the
    // bug that makes a user appear signed in as whoever they were LAST time.
    try store.save("second.token.value")
    XCTAssertEqual(store.load(), "second.token.value",
                   "saving over an existing token must replace it", file: file, line: line)

    try store.delete()
    XCTAssertNil(store.load(), file: file, line: line)

    // Signing out twice is not an error.
    XCTAssertNoThrow(try store.delete(), file: file, line: line)
}

final class TokenStoreTests: XCTestCase {

    func testInMemoryStoreSatisfiesTheContract() throws {
        try assertTokenStoreContract(InMemoryTokenStore())
    }

    func testInMemoryStoreCanBeSeeded() {
        XCTAssertEqual(InMemoryTokenStore(token: "seeded").load(), "seeded")
    }

    /// Long JWTs and the base64url alphabet must survive storage untouched — the token is
    /// compared byte for byte by the server.
    func testRoundTripsATokenVerbatim() throws {
        let store = InMemoryTokenStore()
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
                  + "eyJzdWIiOiJ1c2VyPz4_PngiLCJpYXQiOjE3ODk1MzcxNTQsImV4cCI6MTc4OTU0MDc1NH0."
                  + "Z8YRzsAptqCeMdcnysaf6JW6fXh76zohQz4WXtCZ2b0"
        try store.save(token)
        XCTAssertEqual(store.load(), token)
    }

    func testFailingStoreThrowsOnWriteAndReadsEmpty() {
        let store = FailingTokenStore()
        XCTAssertNil(store.load())
        XCTAssertThrowsError(try store.save("x"))
    }
}
