//
//  DeviceIdentity.swift
//  escape_plan — S2.4 persistence
//

import Foundation

/// The anonymous per-install identifier the backend sees for a device with no account.
///
/// A random UUID generated on first launch and kept in UserDefaults — it is not
/// `identifierForVendor`, carries no device or personal information, and is not
/// correlatable across apps. Deleting the app discards it.
///
/// **The "no user accounts" scope lock this was written under was lifted 2026-09-14**, when
/// the owner approved the S8 Cloud Sync arc. This is NOT obsolete: the app is local-first and
/// "Continue without an account" is a supported way to use it (see `AuthSession`), so an
/// unauthenticated device still needs an identifier. What changed is that it is no longer the
/// *only* identity the backend can see — a signed-in device also carries a JWT, and
/// `StoredHomeModel.user_id` keys off the account, never off this value.
enum DeviceIdentity {
    static let defaultsKey = "escape_plan.device_id"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: defaultsKey)
        return generated
    }

    /// Test/reset hook — a new id is minted on the next `current()`.
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
