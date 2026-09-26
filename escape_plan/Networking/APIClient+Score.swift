// APIClient+Score.swift
// POST /score (S3.5). First of the APIClient+<Endpoint>.swift extensions — APIClient.swift
// itself stays a thin core (config + authenticatedRequest); endpoint methods live in
// per-endpoint extension files like this one, all sending through the client's `session`.

import Foundation

extension APIClient {
    /// Recomputes the preparedness score server-side for `home` with the given checklist
    /// done-state. The backend recomputes the route plan and the full breakdown on every
    /// call, so the returned score always matches the documented weights exactly.
    func score(home: HomeModel, checklistState: [String: Bool]) async throws -> ScoreBreakdown {
        var request = try authenticatedRequest(path: "score", method: "POST")
        request.httpBody = try HomeModel.encoder().encode(
            ScoreRequest(home: home, checklist_state: checklistState)
        )
        // Render's free tier spins down when idle and a cold start comfortably exceeds
        // URLSession's 60 s default; 90 s matches /routes. The Home tab's first score of the
        // day is exactly the request that meets a sleeping server.
        request.timeoutInterval = 90
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        guard http.statusCode == 200 else {
            throw APIClientError.unexpectedResponse(statusCode: http.statusCode)
        }
        return try HomeModel.decoder.decode(ScoreBreakdown.self, from: data)
    }
}
