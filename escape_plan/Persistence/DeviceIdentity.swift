//
//  DeviceIdentity.swift
//  escape_plan — S2.4 persistence
//

import Foundation

/// The anonymous per-install identifier the backend sees instead of an account.
///
/// Scope lock: no user accounts. This is a random UUID generated on first launch
/// and kept in UserDefaults — it is not `identifierForVendor`, carries no device
/// or personal information, and is not correlatable across apps. Deleting the app
/// discards it.
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
