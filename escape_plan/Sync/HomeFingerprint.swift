//  HomeFingerprint.swift
//  escape_plan — S8.4 cloud sync
//
//  "Has this home changed since we last synced it?", answered in 16 characters.
//
//  ─── WHY THIS IS NOT JUST A HASH OF THE FILE ──────────────────────────────────────────────
//  A home that has been through the server differs from the local one BY BYTES but not BY
//  VALUE. pydantic serialises absent optionals as explicit `null` and fills `objects: []` —
//  measured at 21 extra keys on `bungalow.json`, 2026-09-16. A dirty-check that hashes the
//  stored JSON would therefore mark every synced home permanently modified, and the app would
//  re-upload every home on every sync forever.
//
//  So the fingerprint is taken over the CANONICAL RE-ENCODING OF THE DECODED MODEL, never
//  over received or stored bytes. `HomeModel`'s decoder collapses both spellings to the same
//  value (`objects` is non-optional and decodes absent-or-null to `[]`; every other optional
//  decodes absent-or-null to nil), and the canonical encoder then writes one spelling for it.
//  Two `HomeModel`s that are `==` always fingerprint identically, and that is the property
//  `HomeFingerprintTests` pins with the real server-shaped JSON.
//
//  It is a change detector, not a security primitive. Nothing trusts it against an adversary,
//  so a non-cryptographic digest is the right tool; it avoids a CryptoKit import in a
//  directory that must stay pure Foundation.

import Foundation

enum HomeFingerprint {

    /// Byte-for-byte stable JSON for a `HomeModel`: keys sorted, slashes unescaped, dates
    /// ISO-8601. Sorted keys matter — without them the digest depends on property declaration
    /// order, so reordering a struct's fields would silently invalidate every stored
    /// fingerprint and trigger a full re-upload of the user's library.
    static func canonicalJSON(of home: HomeModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(home)
    }

    /// A short, stable digest of a home's VALUE. Equal models give equal fingerprints.
    static func of(_ home: HomeModel) -> String {
        guard let data = try? canonicalJSON(of: home) else {
            // Encoding a HomeModel cannot fail in practice — every field is a plain Codable
            // value and there are no non-conforming floats in a validated model. If it ever
            // did, returning a value that can never match a stored one degrades to
            // "always dirty": the home gets pushed again. That is the safe direction; the
            // alternative is a home that silently never syncs.
            return "unfingerprintable-\(UUID().uuidString)"
        }
        return hex(fnv1a64(data))
    }

    // MARK: - FNV-1a, 64-bit

    /// FNV-1a: two lines, no dependencies, and well-distributed over JSON-shaped bytes.
    /// `&*` and `&^` are the wrapping operators the algorithm is defined in terms of —
    /// overflow here is the arithmetic, not a bug.
    private static func fnv1a64(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "%016llx", value)
    }
}
