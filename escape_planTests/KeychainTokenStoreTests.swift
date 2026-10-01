//  KeychainTokenStoreTests.swift — the real Keychain, on a real device.
//
//  App target only, and it does NOT run in the SwiftPM package: a macOS unit-test bundle has
//  no keychain-access entitlement, so SecItemAdd fails there for reasons that say nothing
//  about whether this code is correct.
//
//  It runs the SAME `assertTokenStoreContract` the in-memory double is held to
//  (escape_planTests/EditorCore/TokenStoreTests.swift), so the device pass is checking the
//  real thing against the real contract rather than a second, weaker set of assertions.
//
//  Uses a throwaway service name, so it can never touch the token belonging to the real app.

import Foundation
import XCTest
@testable import escape_plan

final class KeychainTokenStoreTests: XCTestCase {

    private var store: KeychainTokenStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = KeychainTokenStore(service: "com.escapeplan.tests.\(UUID().uuidString)",
                                   account: "access_token")

        // The gate runs with `CODE_SIGNING_ALLOWED=NO`, and an unsigned test host has no
        // keychain access group, so every SecItem call fails with errSecMissingEntitlement
        // (-34018) for reasons that say nothing about this code. Skip rather than fail, but
        // ONLY for that status: anything else is a real failure and still goes red. An
        // ad-hoc-signed run (`CODE_SIGN_IDENTITY=-`) has the entitlement and runs these for real.
        do {
            try store.save("probe")
            try store.delete()
        } catch let error as KeychainError where error.status == errSecMissingEntitlement {
            throw XCTSkip("Unsigned test host has no keychain entitlement (-34018); "
                        + "run with ad-hoc signing (CODE_SIGN_IDENTITY=-) to exercise the Keychain.")
        }
    }

    override func tearDown() {
        try? store.delete()
        store = nil
        super.tearDown()
    }

    func testKeychainSatisfiesTheTokenStoreContract() throws {
        try assertTokenStoreContract(store)
    }

    /// The overwrite path specifically. SecItemAdd returns errSecDuplicateItem rather than
    /// replacing, so an "add first, update on failure" implementation leaves the OLD token in
    /// place on every re-login — the user signs in as themselves and gets someone else's
    /// session, or their own expired one.
    func testSavingTwiceReplacesRatherThanKeepingTheFirstToken() throws {
        try store.save("token.one")
        try store.save("token.two")
        XCTAssertEqual(store.load(), "token.two")
    }

    /// Two stores naming the same service/account are the same item; different services are
    /// isolated. This is what keeps the test above from touching the shipping token.
    func testDifferentServicesAreIsolated() throws {
        let other = KeychainTokenStore(service: "com.escapeplan.tests.\(UUID().uuidString)",
                                       account: "access_token")
        defer { try? other.delete() }

        try store.save("mine")
        XCTAssertNil(other.load())
        try other.save("theirs")
        XCTAssertEqual(store.load(), "mine")
    }
}
