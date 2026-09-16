//  KeychainTokenStore.swift
//  escape_plan — S8.3 auth
//
//  The access token in the iOS Keychain. The first Keychain use anywhere in this project —
//  the shared backend bearer token lives in UserDefaults (Networking/APIClient.swift), which
//  is fine for a value that ships in the build and is not a per-user credential. A JWT that
//  authenticates one person's account is not that, so it does not go in UserDefaults.
//
//  NOT covered by the SwiftPM package tests: a macOS unit-test bundle has no keychain-access
//  entitlement, so exercising it there would fail for reasons unrelated to correctness. The
//  logic that USES this is tested through `TokenStore` — see that file. This class is on the
//  device-verification list in docs/tracker/BLOCKERS.md.

import Foundation
import Security

final class KeychainTokenStore: TokenStore {

    private let service: String
    private let account: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.escapeplan.app") + ".auth",
         account: String = "access_token") {
        self.service = service
        self.account = account
    }

    /// The attributes that IDENTIFY the item. Must be byte-identical on every call or a
    /// lookup silently misses and the user appears signed out.
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Use the modern, app-sandbox-scoped keychain rather than the legacy file-based
            // one. On iOS this is the only behaviour; naming it explicitly keeps the item
            // identical if this type is ever compiled for macOS, where the default differs.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func load() -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)

        // Update first, then add. SecItemAdd on an existing item returns errSecDuplicateItem
        // rather than overwriting, so "add, and if that fails update" would leave a stale
        // token in place on every re-login.
        let updated = SecItemUpdate(query as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError(status: updated) }

        var insert = query
        insert[kSecValueData as String] = data
        // AfterFirstUnlock, not WhenUnlocked: S8.4 will sync in the background, and a
        // WhenUnlocked item is unreadable while the phone is locked in a pocket.
        // Not ...ThisDeviceOnly, and not synchronizable — see below.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // A JWT is issued to a device session, not to a person's iCloud. Syncing it would
        // hand the same token to every device on the account and make signing out on one
        // of them meaningless. Stated explicitly rather than left to the default.
        insert[kSecAttrSynchronizable as String] = false

        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        // Signing out when already signed out is not a failure.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: Error, Equatable {
    let status: OSStatus

    var localizedDescription: String {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(detail)"
    }
}
