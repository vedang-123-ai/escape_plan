//  AccessToken.swift
//  escape_plan — S8.3 auth
//
//  A JWT the app is holding, plus the two claims it is willing to read locally.
//
//  ─── READ THIS BEFORE USING IT FOR ANYTHING ───────────────────────────────────────────────
//  The payload is decoded WITHOUT verifying the signature, because the signing secret is
//  server-side and must stay there (backend/app/auth/tokens.py). So nothing here is a security
//  decision. It answers exactly one question — "do we already know this session is dead?" —
//  so the app can show a sign-in screen instead of firing a request that is certain to 401.
//
//  The authority on whether a token is valid is always the server. Every failure mode here
//  falls back to "don't know", which means "send it and let the server decide" — the direction
//  that cannot lock a user out of their own account because of a parsing bug.

import Foundation

struct AccessToken: Equatable, Sendable {

    /// The token exactly as issued. This is what goes in the Authorization header.
    let raw: String

    /// `sub` — the user id the backend put in the token. Advisory only.
    let subject: String?

    /// `exp` — when the server said this expires. `nil` when the token could not be parsed,
    /// which is treated as "unknown", never as "expired".
    let expiresAt: Date?

    init(raw: String) {
        self.raw = raw
        let claims = Self.decodePayload(raw)
        self.subject = claims?["sub"] as? String
        // JWT `exp` is a NumericDate: seconds since the epoch, and permitted to be non-integer.
        if let exp = claims?["exp"] as? NSNumber {
            self.expiresAt = Date(timeIntervalSince1970: exp.doubleValue)
        } else {
            self.expiresAt = nil
        }
    }

    /// Whether the app should stop treating this token as usable.
    ///
    /// `leeway` avoids sending a token that expires mid-flight: a request that leaves with two
    /// seconds left arrives already dead, and the user sees a failure they cannot explain. An
    /// unparseable or absent `exp` returns false — see the note at the top of this file.
    func isExpired(now: Date = Date(), leeway: TimeInterval = 30) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= leeway
    }

    // MARK: - Parsing

    /// Decode the middle segment of `header.payload.signature`.
    ///
    /// Base64URL, not base64: "-" and "_" replace "+" and "/", and the "=" padding is stripped.
    /// `Data(base64Encoded:)` rejects all three of those, which is why this cannot just call it.
    private static func decodePayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))

        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
