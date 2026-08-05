//  DrillLogStore.swift
//  escape_plan — S4.2 drill mode, practice log
//
//  Every drill the household runs is recorded locally: who practised, from which room, when,
//  how long it took, and whether they reached the meeting place or walked away. Modeled on
//  HomeDocumentStore / RoutePlanCache — one atomic JSON file per home under Documents, no
//  index to corrupt, so multiple homes coexist without a shared file to contend over.
//
//  This is app state, not schema state: the HomeModel contract is frozen and its documents are
//  exactly HomeModel JSON ("export is the stored file"), so the log cannot live on the home
//  document. Same reasoning as ChecklistStateStore, but a file rather than UserDefaults because
//  a log grows and is not a handful of booleans. Field names are camelCase for the same reason
//  CachedRoutePlan's are: nothing here crosses the wire, so the snake_case schema-mirror rule
//  does not apply.
//
//  Everything in this file is pure Foundation with an injectable directory, so the tests never
//  write to the real Documents directory.

import Foundation

/// How a drill ended. A drill that was walked away from still counts as practice attempted —
/// it is recorded, not discarded, because hiding abandoned drills would flatter the household.
enum DrillOutcome: String, Codable, Equatable, CaseIterable {
    case completed
    case abandoned

    var displayName: String {
        switch self {
        case .completed: return "Completed"
        case .abandoned: return "Stopped early"
        }
    }
}

/// One practice run.
///
/// `profileName` / `roomName` are snapshots taken when the drill ran. They are deliberately
/// duplicated out of the HomeModel so that renaming a profile — or deleting it — leaves the
/// history readable instead of orphaning it behind a dangling id. The ids are still stored,
/// so a record can be re-linked to a live profile when one still exists.
struct DrillRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var homeID: String
    var roomID: String
    /// Display name captured at drill time.
    var roomName: String
    var profileID: String
    /// Display name captured at drill time.
    var profileName: String
    var startedAt: Date
    /// Wall-clock seconds from starting the drill to reaching the meeting place (or to
    /// walking away). Never negative.
    var elapsedSeconds: Double
    var outcome: DrillOutcome
    /// `OccupantTrack.egress_time_s` for this person, if an evacuation timeline was available
    /// when the drill ran. nil means "no modeled walk existed" — never a stand-in number.
    var modeledEgressSeconds: Double?

    init(id: UUID = UUID(),
         homeID: String,
         roomID: String,
         roomName: String,
         profileID: String,
         profileName: String,
         startedAt: Date,
         elapsedSeconds: Double,
         outcome: DrillOutcome,
         modeledEgressSeconds: Double? = nil) {
        self.id = id
        self.homeID = homeID
        self.roomID = roomID
        self.roomName = roomName
        self.profileID = profileID
        self.profileName = profileName
        self.startedAt = startedAt
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.outcome = outcome
        self.modeledEgressSeconds = modeledEgressSeconds
    }
}

/// The on-disk envelope. Versioned so a future field can be added without silently
/// misreading — or worse, silently overwriting — a log written by a newer build.
struct DrillLogFile: Codable, Equatable {
    static let currentVersion = 1

    var schemaVersion: Int
    var records: [DrillRecord]

    init(schemaVersion: Int = DrillLogFile.currentVersion, records: [DrillRecord] = []) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}

/// One person's practice history, folded down for the UI.
struct DrillPersonSummary: Equatable, Identifiable {
    var profileID: String
    /// The most recently recorded display name for this person.
    var profileName: String
    /// Fastest *completed* drill. nil when this person has only stopped drills early —
    /// an abandoned run has no meaningful "best time".
    var best: DrillRecord?
    /// Most recent drill of any outcome. Always present (the summary would not exist
    /// otherwise).
    var mostRecent: DrillRecord
    var completedCount: Int
    var totalCount: Int

    var id: String { profileID }
}

enum DrillLogError: Error, Equatable {
    /// The stored file was written by a newer build. Read returns nothing rather than
    /// guessing, and writes refuse rather than truncating someone else's data.
    case unsupportedVersion(found: Int, supported: Int)
}

/// FileManager-backed practice log: `<Documents>/DrillLog/<home_id>.drilllog.json`, atomic
/// writes. A missing or corrupt file reads as "no drills yet" — the log must never become a
/// failure mode for the drill itself.
struct DrillLogStore {
    static let fileExtension = "drilllog.json"
    /// Keeps a household's file bounded. Twelve years of twice-yearly practice for a family
    /// of eight is well under this.
    static let maximumRecordsPerHome = 250

    let directory: URL
    private let fileManager: FileManager

    /// The app's real store: `<Documents>/DrillLog`.
    init(fileManager: FileManager = .default) throws {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(directory: documents.appendingPathComponent("DrillLog", isDirectory: true),
                      fileManager: fileManager)
    }

    /// Explicit-directory init — used by tests and by anything needing a scratch log.
    init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Read

    /// Every recorded drill for this home, newest first. Unreadable or future-version files
    /// read as empty.
    func records(homeID: String) -> [DrillRecord] {
        (try? file(homeID: homeID))?.records.sorted { $0.startedAt > $1.startedAt } ?? []
    }

    /// When this household last practised, regardless of who practised or how it ended.
    func lastPracticed(homeID: String) -> Date? {
        records(homeID: homeID).first?.startedAt
    }

    /// Per-person history, ordered by most recent practice first. People who have never
    /// practised do not appear — the caller knows the roster; this store only knows history.
    func summaries(homeID: String) -> [DrillPersonSummary] {
        let all = records(homeID: homeID) // newest first
        var order: [String] = []
        var grouped: [String: [DrillRecord]] = [:]
        for record in all {
            if grouped[record.profileID] == nil { order.append(record.profileID) }
            grouped[record.profileID, default: []].append(record)
        }
        return order.compactMap { profileID in
            guard let runs = grouped[profileID], let mostRecent = runs.first else { return nil }
            let completed = runs.filter { $0.outcome == .completed }
            return DrillPersonSummary(
                profileID: profileID,
                profileName: mostRecent.profileName,
                best: completed.min { $0.elapsedSeconds < $1.elapsedSeconds },
                mostRecent: mostRecent,
                completedCount: completed.count,
                totalCount: runs.count
            )
        }
    }

    // MARK: - Write

    /// Appends a drill and returns the home's records, newest first.
    @discardableResult
    func append(_ record: DrillRecord) throws -> [DrillRecord] {
        var stored = try file(homeID: record.homeID)
        stored.records.append(record)
        // Trim oldest-first so the newest history always survives.
        if stored.records.count > Self.maximumRecordsPerHome {
            stored.records = stored.records
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(Self.maximumRecordsPerHome)
                .map { $0 }
        }
        try write(stored, homeID: record.homeID)
        return stored.records.sorted { $0.startedAt > $1.startedAt }
    }

    /// Removes a home's entire log — used when a home is deleted, and by tests.
    func clear(homeID: String) throws {
        let url = url(for: homeID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    // MARK: - Paths

    func url(for homeID: String) -> URL {
        directory.appendingPathComponent("\(homeID).\(Self.fileExtension)")
    }

    // MARK: - Internals

    /// Corrupt/missing → a fresh empty file. Newer-version → throws, so `append` refuses to
    /// clobber it and `records` (which swallows the error) reports nothing.
    private func file(homeID: String) throws -> DrillLogFile {
        guard let data = try? Data(contentsOf: url(for: homeID)) else { return DrillLogFile() }
        guard let decoded = try? Self.decoder.decode(DrillLogFile.self, from: data) else {
            return DrillLogFile()
        }
        guard decoded.schemaVersion <= DrillLogFile.currentVersion else {
            throw DrillLogError.unsupportedVersion(found: decoded.schemaVersion,
                                                   supported: DrillLogFile.currentVersion)
        }
        return decoded
    }

    private func write(_ file: DrillLogFile, homeID: String) throws {
        var stamped = file
        stamped.schemaVersion = DrillLogFile.currentVersion
        try Self.encoder.encode(stamped).write(to: url(for: homeID), options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
