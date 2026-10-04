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
    /// Set only when the person typed a token in Settings. A stored token without this flag
    /// (every install that ever tapped "Save changes" before S11.42) is NOT an override, so a
    /// rotated bundled token reaches those installs too (AUD-009).
    private static let tokenOverriddenDefaultsKey = "APIClient.bearerTokenOverridden"

    /// The deployed backend — what a fresh install talks to with zero setup (S4.4 decision;
    /// see docs/decisions.md). The URL is public knowledge; the bearer token is not and is
    /// never in source — see `bundledBearerToken()`.
    static let deployedDefaultBaseURL = URL(string: "https://escape-plan-backend.onrender.com")!
    /// Local dev server, one tap away in Settings' developer section (DEBUG builds only).
    static let localDevBaseURL = URL(string: "http://localhost:8000")!

    /// Internal, not private: the per-endpoint `APIClient+*.swift` extensions send through it,
    /// so a client built with an injected session (a test's `URLProtocol` stub) really is used
    /// for every call. They used to reach for `URLSession.shared` because this was private.
    let session: URLSession
    private let defaults: UserDefaults

    var baseURL: URL {
        didSet { defaults.set(baseURL.absoluteString, forKey: Self.baseURLDefaultsKey) }
    }

    /// Plain, non-persisting: launch arguments and tests assign it freely. Only
    /// `overrideBearerToken(_:)` (a deliberate Settings edit) survives a relaunch.
    var bearerToken: String

    /// True when the in-use token is a person's saved override rather than the bundled one.
    private(set) var isTokenOverridden: Bool

    func overrideBearerToken(_ token: String) {
        bearerToken = token
        isTokenOverridden = true
        defaults.set(token, forKey: Self.bearerTokenDefaultsKey)
        defaults.set(true, forKey: Self.tokenOverriddenDefaultsKey)
    }

    func clearBearerTokenOverride() {
        defaults.removeObject(forKey: Self.bearerTokenDefaultsKey)
        defaults.removeObject(forKey: Self.tokenOverriddenDefaultsKey)
        bearerToken = bundledToken() ?? ""
        isTokenOverridden = false
    }

    /// Back to what a fresh install uses: the deployed address and the bundled token.
    func resetToDefaults() {
        baseURL = Self.deployedDefaultBaseURL
        defaults.removeObject(forKey: Self.baseURLDefaultsKey)
        defaults.removeObject(forKey: Self.bearerTokenDefaultsKey)
        defaults.removeObject(forKey: Self.tokenOverriddenDefaultsKey)
        bearerToken = bundledToken() ?? ""
        isTokenOverridden = false
    }

    private let bundledToken: () -> String?

    /// The configured base URL without having to build an `APIClient` for it.
    ///
    /// Exists for S8.3: `AuthSession` is created at the app entry point and needs the same
    /// address, but the auth layer is pure Foundation (symlinked into the EditorCore package
    /// so it can be tested without a simulator) and cannot import anything from here.
    ///
    /// A stored address must pass `validatedBaseURL`, otherwise the deployed one is used. In a
    /// Release build (`honorOverrides` false) no stored address is used at all: Settings'
    /// Advanced section is DEBUG-only, so a leftover value could not be seen or corrected.
    static func currentBaseURL(defaults: UserDefaults = .standard,
                               honorOverrides: Bool = APIClient.isDebugBuild) -> URL {
        guard honorOverrides,
              let stored = defaults.string(forKey: baseURLDefaultsKey),
              case .success(let url) = validatedBaseURL(stored, allowLocalHTTP: true)
        else { return deployedDefaultBaseURL }
        return url
    }

    /// Precedence for the token: a launch argument (`-APIClient.bearerToken x`, used by UI
    /// tests; never persisted) > a saved override > the bundled token. `launchArguments` and
    /// `bundledToken` are injectable so tests need neither the real argument domain nor the
    /// gitignored config file.
    init(defaults: UserDefaults = .standard,
         session: URLSession = .shared,
         launchArguments: [String: Any] = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
         bundledToken: @escaping () -> String? = APIClient.bundledBearerToken,
         honorOverrides: Bool = APIClient.isDebugBuild) {
        self.defaults = defaults
        self.session = session
        self.bundledToken = bundledToken
        baseURL = Self.currentBaseURL(defaults: defaults, honorOverrides: honorOverrides)
        let stored = defaults.string(forKey: Self.bearerTokenDefaultsKey)
        let overridden = defaults.bool(forKey: Self.tokenOverriddenDefaultsKey) && stored != nil
        if !honorOverrides {
            // Release: only the bundled token. Launch arguments and stored overrides are DEBUG tools.
            bearerToken = bundledToken() ?? ""
            isTokenOverridden = false
        } else if let launch = launchArguments[Self.bearerTokenDefaultsKey] as? String {
            bearerToken = launch
            isTokenOverridden = false
        } else if overridden, let stored {
            bearerToken = stored
            isTokenOverridden = true
        } else {
            bearerToken = bundledToken() ?? ""
            isTokenOverridden = false
        }
    }

    enum ServerAddressError: Error, Equatable {
        case empty, notAWebAddress, needsHTTPS

        var message: String {
            switch self {
            case .empty: "Enter a server address."
            case .notAWebAddress: "That isn't a web address. Start with https:// and include the server name."
            case .needsHTTPS: "The server address must start with https://."
            }
        }
    }

    /// A server address is https with a host. `http://localhost` (and 127.0.0.1) is accepted
    /// only when `allowLocalHTTP` is true, which is DEBUG builds.
    static func validatedBaseURL(_ text: String, allowLocalHTTP: Bool = APIClient.isDebugBuild) -> Result<URL, ServerAddressError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              let url = parts.url
        else { return .failure(.notAWebAddress) }
        switch scheme {
        case "https": return .success(url)
        case "http":
            let local = host == "localhost" || host == "127.0.0.1"
            return allowLocalHTTP && local ? .success(url) : .failure(.needsHTTPS)
        default: return .failure(.notAWebAddress)
        }
    }

    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// The shared bearer token ships via `escape_plan/BackendConfig.local.json` — a gitignored
    /// file a teammate drops in before archiving (`{"bearer_token": "..."}`); the synchronized
    /// project group bundles it automatically. Absent file → empty token → Settings prompts.
    /// This keeps the secret out of source and out of git while letting a demo build work
    /// out of the box.
    static func bundledBearerToken() -> String? {
        guard let url = Bundle.main.url(forResource: "BackendConfig.local", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["bearer_token"] as? String
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
