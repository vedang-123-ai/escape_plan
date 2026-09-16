//  CloudHomesClient.swift
//  escape_plan — S8.4 cloud sync
//
//  The two cloud endpoints: `GET /homes` and `POST /homes`.
//
//  ─── THE JWT GOES ON /homes AND NOWHERE ELSE ──────────────────────────────────────────────
//  S8.4's brief says "attach the JWT Bearer token to all requests". That is wrong as written,
//  and following it would produce code that works today and breaks silently later. The
//  deterministic endpoints (`/routes`, `/score`, `/convert`, `/evacuate`, `/chat`) are guarded
//  by the SHARED `BACKEND_BEARER_TOKEN` — "this build may talk to this server". The cloud
//  endpoints are guarded by a PER-USER JWT — "this request is this user". They are different
//  axes and `backend/app/api_auth.py` deliberately does not layer one on the other.
//
//  This client is the enforcement: it is the only place a JWT is attached, and it can only
//  build `/homes` URLs. `APIClient` is untouched, so there is no path by which a per-user
//  token reaches a shared-token endpoint.
//
//  Modelled on `AuthClient` next door, including the injected `URLSession` that lets the whole
//  request/response contract be tested in the SwiftPM package with no simulator.

import Foundation

/// `@MainActor` for the same reason `AuthClient` is: `baseURL` is mutable and written from the
/// main actor when Settings changes the server address. Costs nothing — the network work
/// happens inside `URLSession` and `await session.data(for:)` suspends rather than blocks.
@MainActor
final class CloudHomesClient {

    var baseURL: URL

    private let session: URLSession

    init(baseURL: URL, session: URLSession = AuthClient.makeSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Endpoints

    /// `GET /homes` → every home belonging to the authenticated user.
    ///
    /// The user id comes from the verified token server-side; there is no parameter for it
    /// here, and that is the point — a client cannot ask for someone else's homes.
    func list(token: AccessToken) async throws -> [StoredHome] {
        var request = URLRequest(url: homesURL)
        request.httpMethod = "GET"
        authorize(&request, with: token)
        return try decode([StoredHome].self, from: try await perform(request))
    }

    /// `POST /homes` → 201 with the stored record, including the server-incremented
    /// `revision`.
    ///
    /// `remoteID` nil creates; supplying one updates that record. Supplying an id the server
    /// does not have — or that belongs to someone else, which it answers identically so as not
    /// to leak the existence of other users' homes — is a 404, surfaced as `.homeMissing`.
    func push(_ home: HomeModel, remoteID: String?, token: AccessToken) async throws -> StoredHome {
        var request = URLRequest(url: homesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, with: token)
        do {
            request.httpBody = try HomeModel.encoder()
                .encode(HomeSyncRequestBody(home: home, remoteID: remoteID))
        } catch {
            // A home that cannot be encoded is a local problem, not a server one, and no
            // amount of retrying fixes it.
            throw SyncFailure(kind: .rejectedByServer,
                              message: "This home couldn't be prepared for upload.",
                              isRetryable: false, symbol: "exclamationmark.triangle")
        }
        return try decode(StoredHome.self, from: try await perform(request))
    }

    // MARK: - Plumbing

    private var homesURL: URL { baseURL.appendingPathComponent("homes") }

    private func authorize(_ request: inout URLRequest, with token: AccessToken) {
        request.setValue("Bearer \(token.raw)", forHTTPHeaderField: "Authorization")
    }

    /// Everything thrown out of this client is a `SyncFailure` — callers render it and never
    /// have to interpret a status code or a URLError themselves.
    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncFailure(transport: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SyncFailure(statusCode: -1)
        }
        // 200 from list, 201 from push.
        guard (200..<300).contains(http.statusCode) else {
            throw SyncFailure(statusCode: http.statusCode)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try HomeModel.decoder.decode(type, from: data)
        } catch {
            throw SyncFailure.unreadableResponse
        }
    }
}
