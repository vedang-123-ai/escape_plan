// APIClient+Score.swift
// POST /score (S3.5). First of the APIClient+<Endpoint>.swift extensions — APIClient.swift
// itself stays a thin core (config + authenticatedRequest); endpoint methods live in
// per-endpoint extension files like this one.
//
// Uses URLSession.shared rather than APIClient's injected session: `session` is `private`
// (file-scoped in Swift) inside APIClient.swift, which this session must not edit, and the
// default init uses `.shared` anyway so runtime behavior is identical.

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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        guard http.statusCode == 200 else {
            throw APIClientError.unexpectedResponse(statusCode: http.statusCode)
        }
        return try HomeModel.decoder.decode(ScoreBreakdown.self, from: data)
    }
}
