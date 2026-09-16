//  TokenStore.swift
//  escape_plan — S8.3 auth
//
//  Where the access token lives, behind a protocol.
//
//  The protocol is not ceremony. The real implementation is the iOS Keychain, which cannot be
//  exercised from the `tools/editorcore` SwiftPM package — a macOS unit-test bundle has no
//  keychain-access entitlement, so SecItemAdd fails there for reasons that say nothing about
//  whether the code is right. Splitting it this way means `AuthSession`'s whole state machine
//  (restore, sign in, sign out, first-launch purge) is testable on this machine against
//  `InMemoryTokenStore`, and only the ~60 lines that actually talk to Security stay
//  device-gated. See docs/decisions.md, 2026-09-15.

import Foundation

protocol TokenStore: AnyObject {
    /// The stored token, or nil if there isn't one. Reads must not throw: a keychain that
    /// cannot be read is indistinguishable from "not signed in" as far as the app can act.
    func load() -> String?
    func save(_ token: String) throws
    /// Must succeed when there is nothing to delete — signing out twice is not an error.
    func delete() throws
}

/// Test double. NOT a production fallback — `escape_planApp` always constructs a
/// `KeychainTokenStore`, and silently degrading a credential store to one that forgets
/// everything on quit would be worse than failing loudly.
final class InMemoryTokenStore: TokenStore {
    private var token: String?

    /// Counts writes so a test can prove the session is not re-saving a token it just loaded.
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    init(token: String? = nil) { self.token = token }

    func load() -> String? { token }

    func save(_ token: String) throws {
        self.token = token
        saveCount += 1
    }

    func delete() throws {
        token = nil
        deleteCount += 1
    }
}

/// A store that fails every write, so the app's behaviour when the Keychain is unavailable is
/// something we have actually tested rather than assumed.
final class FailingTokenStore: TokenStore {
    struct Unavailable: Error {}

    func load() -> String? { nil }
    func save(_ token: String) throws { throw Unavailable() }
    func delete() throws { throw Unavailable() }
}

/// Holds a token but cannot read it back — the `errSecInteractionNotAllowed` shape.
///
/// A real Keychain item stored `AfterFirstUnlock` is unreadable during a background launch
/// before the device's first unlock, and `KeychainTokenStore.load()` reports that as nil, the
/// same as "no token". This double exists so the difference between "absent" and "unreadable"
/// is something the session is tested against: a transient read failure must never delete.
final class UnreadableTokenStore: TokenStore {
    private(set) var storedToken: String?
    private(set) var deleteCount = 0

    init(token: String?) { storedToken = token }

    func load() -> String? { nil }
    func save(_ token: String) throws { storedToken = token }
    func delete() throws {
        deleteCount += 1
        storedToken = nil
    }
}
