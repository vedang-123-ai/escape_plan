//  AuthValidation.swift
//  escape_plan — S8.3 auth
//
//  The same rules the server applies, applied before the request leaves.
//
//  This is a convenience, never a security boundary: the backend validates independently
//  (`normalise_email` and `Field(min_length=8)` in backend/app/cloud_models.py and
//  api_auth.py), and a client check that disagreed would only ever mean a confusing 422.
//  Its job is to say "that isn't an email address" instantly instead of after a round trip
//  to a server that may be cold-starting for fifty seconds.
//
//  Mirrored from the backend deliberately — if the rule there changes, change it here too.

import Foundation

enum AuthValidation {

    /// Mirrors `Field(min_length=8, max_length=1024)`. Eight is a floor, not a policy: Argon2
    /// has no length cap and NIST advises against composition rules, so length is the only
    /// constraint either side imposes.
    static let minimumPasswordLength = 8
    static let maximumPasswordLength = 1024

    /// Lowercased and trimmed, matching `normalise_email`. Addresses are case-insensitive in
    /// practice and the server stores them normalised, so sending "Ada@Example.com" and then
    /// "ada@example.com" must reach the same account.
    static func normalise(email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The Swift half of `_EMAIL_RE` in backend/app/cloud_models.py — one "@", something either
    /// side, a dot in the domain, no whitespace anywhere. Spelled out rather than written as a
    /// regex literal because this file is compiled in Swift 5 language mode (the SwiftPM
    /// package matches the Xcode target's SWIFT_VERSION), where bare `/.../` literals need an
    /// opt-in flag. Deliberately permissive: real address validation is RFC 5322 and a rabbit
    /// hole, and the authoritative check is sending mail, which this project does not do.
    static func isValid(email: String) -> Bool {
        let normalised = normalise(email: email)
        guard normalised.count <= 254 else { return false }  // the server's max_length
        guard !normalised.contains(where: \.isWhitespace) else { return false }

        let parts = normalised.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }

        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex else { return false }
        return domain.index(after: dot) != domain.endIndex
    }

    static func isValid(password: String) -> Bool {
        (minimumPasswordLength...maximumPasswordLength).contains(password.count)
    }

    /// The first thing wrong with these credentials, or nil if nothing is. Email is checked
    /// first so the message points at the first field on the form.
    static func problem(email: String, password: String) -> AuthFailure? {
        if !isValid(email: email) {
            return AuthFailure(localProblem: "That doesn't look like an email address.")
        }
        if password.count < minimumPasswordLength {
            return AuthFailure(
                localProblem: "Your password needs at least \(minimumPasswordLength) characters.")
        }
        if password.count > maximumPasswordLength {
            return AuthFailure(localProblem: "That password is too long.")
        }
        return nil
    }
}
