import Foundation
import os

struct CachedScore: Equatable {
    let score: ScoreBreakdown
    let savedAt: Date?
    let homeFingerprint: String?

    enum MatchStatus: Equatable {
        case match
        case mismatch(cached: String)
        case unknown
    }

    func matchStatus(against currentFingerprint: String) -> MatchStatus {
        guard let homeFingerprint else { return .unknown }
        return homeFingerprint == currentFingerprint ? .match : .mismatch(cached: homeFingerprint)
    }

    func isMatch(for home: HomeModel) -> Bool {
        matchStatus(against: ScoreCache.fingerprint(of: home)) == .match
    }
}

private struct CachedScoreEnvelope: Codable {
    let score: ScoreBreakdown
    let savedAt: Date?
    let homeFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case score
        case savedAt = "saved_at"
        case homeFingerprint = "home_fingerprint"
    }
}

struct ScoreCache {
    private static let log = Logger(subsystem: "escape_plan", category: "ScoreCache")
    private let directory: URL

    init(fileManager: FileManager = .default) throws {
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true)
        directory = caches.appendingPathComponent("ScoreCache", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Stable fingerprint of a home model's content for cache validity checks.
    /// `meta` dates are normalized so saving timestamps does not invalidate identical geometry/profiles.
    static func fingerprint(of home: HomeModel) -> String {
        var scored = home
        scored.meta = Meta(created: .distantPast, modified: .distantPast)
        return HomeFingerprint.of(scored)
    }

    private func file(for homeID: String) throws -> URL {
        try HomeID.validate(homeID)
        return directory.appendingPathComponent("\(homeID).json")
    }

    /// Saves score breakdown along with home model fingerprint and timestamp.
    /// Surfaces filesystem / encoding errors to os.Logger.
    func save(_ score: ScoreBreakdown, for homeID: String,
              homeFingerprint: String? = nil, savedAt: Date = Date()) {
        do {
            try write(score, for: homeID, homeFingerprint: homeFingerprint, savedAt: savedAt)
        } catch {
            Self.log.error("Failed to save score cache for home \(homeID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Throwing save helper for callers that handle persistence errors explicitly.
    func write(_ score: ScoreBreakdown, for homeID: String,
               homeFingerprint: String? = nil, savedAt: Date = Date()) throws {
        try HomeID.validate(homeID)
        let envelope = CachedScoreEnvelope(score: score, savedAt: savedAt, homeFingerprint: homeFingerprint)
        let data = try HomeModel.encoder().encode(envelope)
        let targetURL = try file(for: homeID)
        try data.write(to: targetURL, options: Data.WritingOptions.atomic)
    }

    func remove(homeID: String) {
        do {
            try HomeID.validate(homeID)
            let targetURL = try file(for: homeID)
            try? FileManager.default.removeItem(at: targetURL)
        } catch {
            Self.log.error("ScoreCache.remove invalid homeID \(homeID, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads the cached entry with metadata. Existing legacy cache files without an envelope
    /// still decode successfully with nil fingerprint and timestamp (treated as unknown/stale).
    func loadEntry(homeID: String) -> CachedScore? {
        do {
            try HomeID.validate(homeID)
            let targetURL = try file(for: homeID)
            guard FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
            let data = try Data(contentsOf: targetURL)
            let decoder = HomeModel.decoder
            if let envelope = try? decoder.decode(CachedScoreEnvelope.self, from: data) {
                return CachedScore(score: envelope.score, savedAt: envelope.savedAt, homeFingerprint: envelope.homeFingerprint)
            }
            if let legacy = try? decoder.decode(ScoreBreakdown.self, from: data) {
                return CachedScore(score: legacy, savedAt: nil, homeFingerprint: nil)
            }
            return nil
        } catch {
            Self.log.error("Failed to load score cache for home \(homeID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Legacy convenience loader returning just the ScoreBreakdown if available.
    func load(homeID: String) -> ScoreBreakdown? {
        loadEntry(homeID: homeID)?.score
    }

    /// Loads the cached score only if its recorded fingerprint matches the given fingerprint.
    func load(homeID: String, matchingFingerprint fingerprint: String) -> CachedScore? {
        guard let entry = loadEntry(homeID: homeID),
              let cachedFp = entry.homeFingerprint,
              cachedFp == fingerprint else { return nil }
        return entry
    }
}
