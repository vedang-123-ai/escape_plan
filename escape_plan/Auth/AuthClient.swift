//  AuthClient.swift
//  escape_plan — S8.3 auth
//
//  The three S8.2 endpoints: POST /auth/register, POST /auth/login, GET /auth/me.
//
//  Two things about this client are different from the `APIClient+*` extensions next door, and
//  both are deliberate:
//
//  1. **It takes its URLSession as an injected dependency**, where every other endpoint calls
//     `URLSession.shared` directly. That is what lets the whole request/response contract be
//     tested in the SwiftPM package on a machine with no simulator. The app-target alternative
//     (`OfflineStubProtocol` in OfflineIntegrityTests.swift) registers a URLProtocol
//     *globally*, which is why that suite has to be `.serialized`.
//  2. **It does not send the shared bearer token.** The backend guards the deterministic
//     endpoints with `BACKEND_BEARER_TOKEN` and the cloud endpoints with a per-user JWT; these
//     are different axes, and `api_auth.py` deliberately does not layer the first on top of
//     the second. Sending both here would work today and break the moment that comment stops
//     being true.
//
//  See docs/decisions.md, 2026-09-15.

import Foundation

/// `@MainActor` because `baseURL` is mutable and written from the main actor (Settings'
/// `setBaseURL`, via `AuthSession.baseURL`). Without isolation the `async` methods here are
/// `nonisolated` and run on the global concurrent executor, so they would read `baseURL` off
/// the main actor while Settings writes it — a torn read of a refcounted struct, not a benign
/// race. It only type-checks today because the SwiftPM package pins Swift 5 language mode.
///
/// Costs nothing: the actual network work happens inside `URLSession`, and `await
/// session.data(for:)` suspends rather than blocking the main actor.
@MainActor
final class AuthClient {

    /// Kept in step with `APIClient.baseURL` by whoever owns both — the auth layer is pure
    /// Foundation and cannot reach into Networking/ to read it.
    var baseURL: URL

    private let session: URLSession

    init(baseURL: URL, session: URLSession = AuthClient.makeSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    /// The deployed backend runs on Render's free tier, which sleeps after inactivity; the
    /// first request after an idle period pays a cold start that can approach a minute. The
    /// default 60s timeout would surface that as a failure on the one request a new user
    /// makes first.
    ///
    /// `waitsForConnectivity` stays false on purpose: with it on, a request made with no
    /// network sits silently until the timeout instead of failing immediately with
    /// `.notConnectedToInternet`, and the user watches a spinner for 90 seconds.
    /// `nonisolated` so it can be a default argument to `init` — it touches no isolated state,
    /// it only configures a URLSession.
    nonisolated static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: - Endpoints

    /// `POST /auth/register` → 201 `UserPublic`.
    ///
    /// Note what this does NOT return: a token. The backend issues one only from /auth/login,
    /// so signing up is register-then-login — see `AuthSession.register`.
    func register(email: String, password: String) async throws -> AuthenticatedUser {
        var request = jsonRequest(path: "auth/register")
        request.httpBody = try JSONEncoder().encode(
            RegisterRequestBody(email: email, password: password))
        let data = try await perform(request)
        return try decode(UserPublicResponse.self, from: data).asUser
    }

    /// `POST /auth/login` → `{access_token, token_type}`.
    ///
    /// Form-encoded, and the email goes in a field called `username`. See `FormURLEncoding`.
    func login(email: String, password: String) async throws -> AccessToken {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/login"))
        request.httpMethod = "POST"
        request.setValue(FormURLEncoding.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = FormURLEncoding.body([("username", email), ("password", password)])
        let data = try await perform(request)
        return AccessToken(raw: try decode(TokenResponse.self, from: data).access_token)
    }

    /// `GET /auth/me` → `UserPublic`.
    ///
    /// The backend re-reads the user from the database on every request, so this is also how
    /// the app finds out that an account was deleted rather than waiting for the token to age
    /// out.
    func me(token: AccessToken) async throws -> AuthenticatedUser {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.raw)", forHTTPHeaderField: "Authorization")
        let data = try await perform(request)
        return try decode(UserPublicResponse.self, from: data).asUser
    }

    // MARK: - Plumbing

    private func jsonRequest(path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Everything thrown out of this client is an `AuthFailure` — callers render it and never
    /// have to interpret a status code or a URLError themselves.
    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthFailure(transport: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthFailure(statusCode: -1)
        }
        // 201 from register, 200 from login and me.
        guard (200..<300).contains(http.statusCode) else {
            throw AuthFailure(statusCode: http.statusCode, body: data)
        }
        return data
    }

    /// A success status with a body we cannot read is still a failure the user must see —
    /// never a crash, and never a silent empty account.
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try HomeModel.decoder.decode(type, from: data)
        } catch {
            throw AuthFailure(statusCode: -1)
        }
    }
}
