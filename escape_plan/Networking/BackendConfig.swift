//
//  BackendConfig.swift
//  Networking
//
//  Clean Release Build Behavior & Backend Configuration Lifecycle:
//  -------------------------------------------------------------
//  In a clean clone or production Release build, `BackendConfig.local.json` is
//  intentionally absent from the application bundle (excluded via synchronized
//  root group membership exceptions to avoid bundling secrets into IPAs, A14-02).
//
//  When the configuration is absent:
//  1. No Crash: The application launches and initializes cleanly without throwing or crashing.
//  2. Local-First Capabilities: All client-side features remain fully functional:
//     - 3D dollhouse modeling, manual room/wall/door/window editing
//     - SceneKit rendering, camera manipulation, room inspection
//     - Offline readiness checklists and progress tracking
//     - PDF export and first responder summary sheet generation
//     - Evacuation walk simulations based on local geometry
//  3. Clear Unconfigured Behavior: Authenticated remote endpoints (/score, /routes,
//     /convert, /chat, /build, /evacuate) detect the absent token (`bearerToken == nil` or empty).
//     The client reports an honest status ("Backend is not configured on this build")
//     without misleading error loops or crashes.
//  4. Debug Builds: On developer machines, `BackendConfig.local.json` is copied into
//     the bundle during Debug builds only via the "Copy BackendConfig for Debug" phase,
//     or can be provided via UI-test launch arguments / Settings overrides.
//

import Foundation

public struct BackendConfig: Equatable, Sendable {
    public let bearerToken: String?
    public let baseURL: URL?

    public init(bearerToken: String? = nil, baseURL: URL? = nil) {
        self.bearerToken = bearerToken
        self.baseURL = baseURL
    }

    /// True if a non-empty bearer token is configured for authenticated backend calls.
    public var isConfigured: Bool {
        guard let token = bearerToken else { return false }
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// User-facing status description explaining backend readiness.
    public var statusDescription: String {
        if isConfigured {
            return "Backend configured."
        } else {
            return Self.unconfiguredMessage
        }
    }

    /// Standard user-facing message when no backend credentials are provisioned in the build.
    public static let unconfiguredMessage = "Backend is not configured on this build. Local planning and 3D editing features remain fully functional."

    /// Loads the configuration from the specified bundle (defaults to Bundle.main).
    /// If the configuration file is absent or malformed, returns an unconfigured instance.
    public static func load(from bundle: Bundle = .main) -> BackendConfig {
        guard let url = bundle.url(forResource: "BackendConfig.local", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return BackendConfig(bearerToken: nil, baseURL: nil)
        }

        let token = json["bearer_token"] as? String
        let urlString = json["base_url"] as? String
        let parsedURL = urlString.flatMap { URL(string: $0) }

        return BackendConfig(bearerToken: token, baseURL: parsedURL)
    }

    /// Shared convenience accessor loading current configuration.
    public static var current: BackendConfig {
        load()
    }
}
