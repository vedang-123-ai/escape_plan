//  AuthModels.swift
//  escape_plan — S8.3 auth
//
//  The wire shapes of the S8.2 endpoints, and the one account type the app carries around.
//
//  Pure Foundation on purpose: this whole directory is symlinked into the `tools/editorcore`
//  SwiftPM package (`Sources/EditorCore/Auth`) so it compiles and TESTS on a machine with no
//  iOS simulator. Adding a SwiftUI or UIKit import here breaks that and silently removes the
//  only coverage this layer has. See docs/decisions.md, 2026-09-15.

import Foundation

/// A signed-in account, as the app knows it. Mirrors the backend's `UserPublic`
/// (`backend/app/cloud_models.py`), which by construction has nowhere to put a password hash.
struct AuthenticatedUser: Equatable, Codable, Sendable {
    let id: String
    let email: String
    let createdAt: Date
}

// MARK: - Wire shapes

/// `POST /auth/register` request. JSON — unlike login, which is form-encoded (see
/// `FormURLEncoding`). The backend's `RegisterRequest` sets `extra="forbid"`, so an
/// extra key here is a 422, not a warning.
struct RegisterRequestBody: Encodable, Sendable {
    let email: String
    let password: String
}

/// `POST /auth/register` and `GET /auth/me` response.
///
/// Decoded with `HomeModel.decoder` (the house convention for every other endpoint). Its
/// `.iso8601` strategy handles BOTH forms pydantic emits for `created_at` —
/// `2026-09-16T05:33:58.567000Z` when there are microseconds and `2026-09-15T18:22:31Z` when
/// there are not. Both are pinned in `AuthModelsTests`; note that a bare
/// `ISO8601DateFormatter()` parses only the second, so do not "simplify" this to one of those.
struct UserPublicResponse: Decodable, Sendable {
    let id: String
    let email: String
    let created_at: Date

    var asUser: AuthenticatedUser {
        AuthenticatedUser(id: id, email: email, createdAt: created_at)
    }
}

/// `POST /auth/login` response. `token_type` is always "bearer"; it is decoded rather than
/// assumed so a backend change shows up here instead of as a silent 401 later.
struct TokenResponse: Decodable, Sendable {
    let access_token: String
    let token_type: String
}
