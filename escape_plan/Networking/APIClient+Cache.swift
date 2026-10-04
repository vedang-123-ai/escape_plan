// APIClient+Cache.swift
// S4.1: last-good RoutePlan cache so the Plan screen and onboarding degrade to the most
// recently fetched plan instead of a dead end when the backend is unreachable. Follows the
// HomeDocumentStore pattern: one atomic JSON file per entry, no index to corrupt.
//
// Only ever stores plans that came from a real /routes response — this is a cache of the
// deterministic engine's output, never a client-side computation.
//
// S11.36 (AUD-028): the cache used to be keyed by `home_id` alone, so whichever /routes call
// last succeeded won, whatever its peril or person, and however much the home had been edited
// since. An entry is now keyed by (home, peril, person or "household") AND stamped with the
// `HomeFingerprint` of the model it was computed from. A lookup that differs on any of those
// is a miss. A miss is always safe: the caller shows its ordinary offline failure, never a
// route that was computed for something else.

import Foundation

/// What a cached plan was computed for. Two plans with different keys are never
/// interchangeable: a fire plan is not a tornado plan, and a route for someone who can use
/// stairs is not a route for someone who cannot.
struct RoutePlanKey: Hashable {
    /// What `/routes` computes when no peril is sent (`RoutesRequest.peril` defaults to fire
    /// server-side, and `RoutePlan` decodes an absent peril as fire).
    static let defaultPeril = "fire"

    let homeID: String
    /// Always concrete: `nil` is normalised to `defaultPeril`, so "no peril asked" and
    /// "fire asked" are the same key.
    let peril: String
    /// nil means the whole household (no person picked).
    let profileID: String?

    init(homeID: String, peril: String? = nil, profileID: String? = nil) {
        self.homeID = homeID
        self.peril = peril ?? Self.defaultPeril
        self.profileID = profileID
    }
}

/// A cached /routes response, what it was computed for, and when it was fetched (shown in the
/// offline banner).
struct CachedRoutePlan: Codable, Equatable {
    var plan: RoutePlan
    var savedAt: Date
    /// `HomeFingerprint.of` the model sent to `/routes`. Required: a file without it cannot be
    /// proven to match any model, so it fails to decode and reads as a miss.
    var homeFingerprint: String
    /// The key it was saved under, repeated inside the file so a renamed, copied or hand-edited
    /// file still cannot be served for another key.
    var peril: String
    var profileID: String?
}

/// FileManager-backed cache: `<Documents>/RouteCache/<home>.<peril>.<person>.routeplan.v2.json`,
/// atomic writes. A corrupt or missing file reads as nil — the cache must never add a failure
/// mode of its own.
struct RoutePlanCache {
    /// Not `routeplan.json`: the single-key files that extension named could be wrong for
    /// the peril, the person or the model, so no new lookup may ever resolve to one.
    static let fileExtension = "routeplan.v2.json"
    /// What the single-key cache (before S11.36) wrote. Never read; removed on init.
    static let legacyFileExtension = "routeplan.json"

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
        removeLegacyFiles()
    }

    /// Stores `plan` for `key`, stamped with the fingerprint of the model it was computed from.
    func save(_ plan: RoutePlan, key: RoutePlanKey, homeFingerprint: String,
              now: Date = Date()) throws {
        let cached = CachedRoutePlan(plan: plan, savedAt: now, homeFingerprint: homeFingerprint,
                                     peril: key.peril, profileID: key.profileID)
        let encoder = HomeModel.encoder()
        try encoder.encode(cached).write(to: url(for: key), options: .atomic)
    }

    /// The plan saved for exactly `key` from exactly the model whose fingerprint is
    /// `homeFingerprint`; nil otherwise. A miss when: nothing is cached or the file doesn't
    /// decode; the model has changed since (a route through rooms or openings that no longer
    /// exist); or the stored plan is for another home, peril or person than the one asked for
    /// (defence in depth: the file name should already have ruled that out, but `RoutePlan`
    /// says what it is, so we check). Callers treat every miss as "no cache" rather than
    /// surfacing an error.
    func load(_ key: RoutePlanKey, homeFingerprint: String) -> CachedRoutePlan? {
        guard let data = try? Data(contentsOf: url(for: key)),
              let cached = try? HomeModel.decoder.decode(CachedRoutePlan.self, from: data)
        else { return nil }
        guard cached.homeFingerprint == homeFingerprint,
              cached.peril == key.peril,
              cached.profileID == key.profileID,
              cached.plan.home_id == key.homeID,
              (cached.plan.peril ?? RoutePlanKey.defaultPeril) == key.peril,
              cached.plan.profile_id == key.profileID
        else { return nil }
        return cached
    }

    /// The fingerprint a cached plan is stamped with and looked up by: `HomeFingerprint` of the
    /// model with `meta` blanked. `meta` holds only dates and the address, none of which the
    /// engine routes on, and `meta.modified` changes on every save: the editor stamps it on each
    /// edit and `HomeDocumentStore.save` stamps it again with its own clock (ISO-8601, whole
    /// seconds). Fingerprinting it made the model in House and the same model read back from
    /// disk disagree after any edit, so the printed plan never found the routes House had just
    /// fetched (audit of S11.36, 2026-10-03).
    static func fingerprint(of home: HomeModel) -> String {
        var routed = home
        routed.meta = Meta(created: .distantPast, modified: .distantPast)
        return HomeFingerprint.of(routed)
    }

    func url(for key: RoutePlanKey) -> URL {
        let person = key.profileID.map { "p-" + Self.fileSafe($0) } ?? "household"
        let name = [Self.fileSafe(key.homeID), Self.fileSafe(key.peril), person].joined(separator: ".")
        return directory.appendingPathComponent("\(name).\(Self.fileExtension)")
    }

    /// Percent-encodes everything except letters, digits, `-` and `_`. Injective, so two
    /// different ids can never share a file, and `.` and `/` are always escaped, so an id
    /// from a synced home cannot climb out of the directory or fake the `.`-separated parts.
    private static func fileSafe(_ part: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        return part.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// Single-key files from before S11.36 can never be served (the lookups name a different
    /// extension), but they are dead weight and the only copy of someone's old plan, so they
    /// are deleted. Best effort: a file that will not delete is merely ignored.
    private func removeLegacyFiles() {
        let suffix = "." + Self.legacyFileExtension
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasSuffix(suffix) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
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

    /// /routes with the last-good fallback: a successful fetch updates the cache entry for
    /// this (home, peril, person), stamped with the model it was computed from; a
    /// connection-class failure falls back to that same entry, and only if the model has not
    /// changed since. Any other failure, or a connection failure with no matching entry,
    /// rethrows.
    func fetchRoutesCached(home: HomeModel,
                           peril: String? = nil,
                           profileID: String? = nil,
                           cache: RoutePlanCache? = nil) async throws -> CachedRoutesResult {
        let cache = try cache ?? RoutePlanCache()
        let key = RoutePlanKey(homeID: home.home_id, peril: peril, profileID: profileID)
        // Taken before the request: the plan describes the model as it was sent, even if the
        // caller's model moves while the request is in flight.
        let fingerprint = RoutePlanCache.fingerprint(of: home)
        do {
            let plan = try await fetchRoutes(home: home, peril: peril, profileID: profileID)
            try? cache.save(plan, key: key, homeFingerprint: fingerprint)
            return .live(plan)
        } catch where Self.isConnectionFailure(error) {
            if let cached = cache.load(key, homeFingerprint: fingerprint) {
                return .cached(cached)
            }
            throw error
        }
    }
}
