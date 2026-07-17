//  APIClient.swift
//  escape_plan
//
//  Thin stub over the S1.6 FastAPI backend (/health, /routes, /convert, /analyze, /explain,
//  /chat, /score land incrementally). Base URL + bearer token are configurable at runtime
//  (Settings screen) rather than hardcoded, since the deploy target flips from local dev to
//  the Render URL once S1.6's human step lands (see docs/decisions.md).
//
//  The Anthropic API key never appears here — it's server-side only. This client only ever
//  talks to our own backend over the shared bearer token.

import Foundation
import Observation

enum APIClientError: Error {
    case invalidBaseURL
    case unexpectedResponse(statusCode: Int)
}

@Observable
final class APIClient {
    private static let baseURLDefaultsKey = "APIClient.baseURL"
    private static let bearerTokenDefaultsKey = "APIClient.bearerToken"

    /// Local dev default; swap for the deployed Render URL once available (Settings screen).
    static let developmentDefaultBaseURL = URL(string: "http://localhost:8000")!

    private let session: URLSession
    private let defaults: UserDefaults

    var baseURL: URL {
        didSet { defaults.set(baseURL.absoluteString, forKey: Self.baseURLDefaultsKey) }
    }

    var bearerToken: String {
        didSet { defaults.set(bearerToken, forKey: Self.bearerTokenDefaultsKey) }
    }

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        if let stored = defaults.string(forKey: Self.baseURLDefaultsKey),
           let url = URL(string: stored) {
            baseURL = url
        } else {
            baseURL = Self.developmentDefaultBaseURL
        }
        bearerToken = defaults.string(forKey: Self.bearerTokenDefaultsKey) ?? ""
    }

    /// Hits the unauthenticated /health endpoint (S1.6) as a connectivity check.
    func checkHealth() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let (_, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        return http.statusCode == 200
    }

    /// Builds an authenticated request against a backend path (e.g. "routes", "convert").
    /// Every endpoint besides /health requires the shared bearer token (backend fails closed
    /// if unset) — see .claude/rules/vendors/anthropic.md and backend/README.md.
    func authenticatedRequest(path: String, method: String = "GET") throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}
