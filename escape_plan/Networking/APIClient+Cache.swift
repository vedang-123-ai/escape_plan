// APIClient+Cache.swift
// S4.1: last-good RoutePlan cache so the Plan screen and onboarding degrade to the most
// recently fetched plan instead of a dead end when the backend is unreachable. Follows the
// HomeDocumentStore pattern: one atomic JSON file per home, no index to corrupt.
//
// Only ever stores plans that came from a real /routes response — this is a cache of the
// deterministic engine's output, never a client-side computation.

import Foundation

/// A cached /routes response plus when it was fetched (shown in the offline banner).
struct CachedRoutePlan: Codable, Equatable {
    var plan: RoutePlan
    var savedAt: Date
}

/// FileManager-backed cache: `<Documents>/RouteCache/<home_id>.routeplan.json`, atomic
/// writes. A corrupt or missing file reads as nil — the cache must never add a failure
/// mode of its own.
struct RoutePlanCache {
    static let fileExtension = "routeplan.json"

    let directory: URL
    private let fileManager: FileManager

    /// The app's real cache: `<Documents>/RouteCache`.
    init(fileManager: FileManager = .default) throws {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(directory: documents.appendingPathComponent("RouteCache", isDirectory: true),
                      fileManager: fileManager)
    }

    /// Explicit-directory init — used by tests.
    init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(_ plan: RoutePlan, now: Date = Date()) throws {
        let cached = CachedRoutePlan(plan: plan, savedAt: now)
        let encoder = HomeModel.encoder()
        try encoder.encode(cached).write(to: url(for: plan.home_id), options: .atomic)
    }

    /// nil when nothing is cached or the file doesn't decode — callers treat both as "no
    /// cache" rather than surfacing an error.
    func load(homeID: String) -> CachedRoutePlan? {
        guard let data = try? Data(contentsOf: url(for: homeID)) else { return nil }
        return try? HomeModel.decoder.decode(CachedRoutePlan.self, from: data)
    }

    func url(for homeID: String) -> URL {
        directory.appendingPathComponent("\(homeID).\(Self.fileExtension)")
    }
}

// MARK: - Cached fetch

/// What a cache-aware routes fetch produced: a live plan (now cached), the last-good cached
/// plan after a connection-class failure, or a plain failure when there's nothing to fall
/// back on (server errors like 401/422 never fall back — they'd mask a config problem).
enum CachedRoutesResult {
    case live(RoutePlan)
    case cached(CachedRoutePlan)
}

extension APIClient {
    /// True for failures that mean "couldn't reach the backend" (offline, dead URL, timeout)
    /// as opposed to the backend answering with an error status.
    static func isConnectionFailure(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
             .timedOut, .networkConnectionLost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    /// /routes with the last-good fallback: a successful fetch updates the cache; a
    /// connection-class failure falls back to the cached plan for this home (matching
    /// profile selection is not tracked — the cache stores whatever was last shown).
    /// Any other failure, or a connection failure with an empty cache, rethrows.
    func fetchRoutesCached(home: HomeModel,
                           profileID: String? = nil,
                           cache: RoutePlanCache? = nil) async throws -> CachedRoutesResult {
        let cache = try cache ?? RoutePlanCache()
        do {
            let plan = try await fetchRoutes(home: home, profileID: profileID)
            try? cache.save(plan)
            return .live(plan)
        } catch where Self.isConnectionFailure(error) {
            if let cached = cache.load(homeID: home.home_id) {
                return .cached(cached)
            }
            throw error
        }
    }
}
