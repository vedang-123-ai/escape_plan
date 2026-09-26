// APIClient+Routes.swift
// POST /routes (S2.3). Follows the APIClient+<Endpoint>.swift pattern established by
// APIClient+Score.swift: APIClient.swift stays a thin core, endpoint methods live in
// per-endpoint extensions, all sending through the client's injected `session`.

import Foundation

extension APIClient {
    /// Fetches the deterministic engine's RoutePlan for `home` — the ONLY source of routes in
    /// the app; nothing client-side ever computes or approximates one.
    ///
    /// `constraints` and `profileID` are mutually exclusive (the backend 422s on both).
    /// S2.3 always calls with neither — the base whole-house plan; S3.4 adds profile UI on
    /// top of the same call.
    func fetchRoutes(home: HomeModel,
                     peril: String? = nil,
                     constraints: RoutingConstraints? = nil,
                     profileID: String? = nil) async throws -> RoutePlan {
        var request = try authenticatedRequest(path: "routes", method: "POST")
        request.httpBody = try HomeModel.encoder().encode(
            RoutesRequest(home: home, peril: peril, constraints: constraints, profile_id: profileID)
        )
        // Render's free tier spins the service down when idle; a cold start comfortably
        // exceeds URLSession's 60 s default.
        request.timeoutInterval = 90
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        guard http.statusCode == 200 else {
            throw APIClientError.unexpectedResponse(statusCode: http.statusCode)
        }
        return try HomeModel.decoder.decode(RoutePlan.self, from: data)
    }
}
