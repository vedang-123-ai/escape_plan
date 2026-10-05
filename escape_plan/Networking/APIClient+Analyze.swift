// APIClient+Analyze.swift
// POST /analyze (S3.2, wired in S4.1's onboarding flow). Follows the APIClient+<Endpoint>.swift
// pattern: APIClient.swift stays a thin core, endpoint methods live in per-endpoint extensions,
// all sending through the client's injected `session`.

import Foundation

extension APIClient {
    /// Runs the server-side agentic safety inspection over `home`.
    /// 
    /// Note (S11.39): The AI inspector (/analyze, /explain) is NOT wired into the app
    /// and this method has had no callers since dac8673. This client extension and its 
    /// models are kept dormant because OnboardingTests still references AnalysisResult.
    ///
    /// 502 means the agent couldn't produce a validated result (including an unset
    /// ANTHROPIC_API_KEY on the server) — routes and score still work without it.
    func analyze(home: HomeModel) async throws -> AnalysisResult {
        var request = try authenticatedRequest(path: "analyze", method: "POST")
        request.httpBody = try HomeModel.encoder().encode(AnalyzeRequest(home: home))
        // Render cold start plus the full agent tool-use loop; 90 s matches /routes' margin.
        request.timeoutInterval = 90
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        guard http.statusCode == 200 else {
            throw APIClientError.forStatus(http.statusCode, body: data)
        }
        return try HomeModel.decoder.decode(AnalysisResult.self, from: data)
    }
}
