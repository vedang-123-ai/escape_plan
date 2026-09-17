//  SyncState.swift
//  escape_plan — S8.4 cloud sync
//
//  What the device remembers about the last successful sync of each home.
//
//  ─── WHY THIS IS A SIDECAR AND NOT A FIELD ON HomeModel ───────────────────────────────────
//  Putting `last_synced_revision` on the home itself would be a change to
//  `schema/homemodel.schema.json` — the project's one law — requiring a `schema_version` bump,
//  matching pydantic and Swift Codable changes, and a clean `schema-contract-guardian` run.
//  It would also be wrong on the merits: sync progress is a fact about THIS DEVICE's
//  relationship to the server, not a property of the home. Two devices holding the same home
//  legitimately disagree about it, and a device-local fact stored inside a synced document
//  would be overwritten by the sync it is meant to describe.
//
//  So it lives beside the documents, in its own file, and `Persistence/` is untouched.

import Foundation

/// The device's memory of one home's last successful sync.
struct HomeSyncRecord: Codable, Equatable, Sendable {
    /// The schema `home_id` — the key both sides agree on, because it travels inside the
    /// document and therefore survives a round trip through another device.
    let localHomeID: String
    /// The SERVER's record id, needed to address an update rather than create a duplicate.
    let remoteID: String
    /// The `revision` the server reported when it last accepted or served this home.
    let syncedRevision: Int
    /// `HomeFingerprint.of` the model as it stood at that moment. Local edits since then
    /// change it; a byte-different-but-equal copy from the server does not.
    let syncedFingerprint: String
    let lastSyncedAt: Date
}

/// Every `HomeSyncRecord` this device holds, keyed by schema `home_id`, plus the tombstones
/// for homes deleted here, plus whose account the whole file describes.
///
/// Versioned from the start. This file is read by a future build that may have changed its
/// shape, and an unreadable sidecar must degrade to "nothing has ever synced" — which costs
/// one redundant upload per home — rather than to a crash or to silent data loss.
struct SyncState: Codable, Equatable, Sendable {
    /// Bumped to 2 when `userID` and `deletedHomeIDs` were added (2026-09-16). A version-1
    /// sidecar has neither, and reading one as though it did would apply user A's records to
    /// user B's account — so the version guard in `FileSyncStateStore.load` discards it.
    static let currentVersion = 2

    var version: Int

    /// The account these records describe — `AccessToken.subject`, i.e. the `sub` claim.
    ///
    /// Without this, a second user signing in on the same device inherits the first user's
    /// records: their home ids point at server records in someone else's account, so a home
    /// the new user has never seen reads as "already synced, revision 5" and their real cloud
    /// copy never arrives. `nil` means "written before this field existed, or by a signed-out
    /// state" and matches only `nil`.
    var userID: String?

    var records: [String: HomeSyncRecord]

    /// Homes deleted on this device, and when. The backend has no delete endpoint, so the
    /// server keeps serving a deleted home forever; without a tombstone the next sync
    /// downloads it again and it reappears in the library. The app already learned this
    /// lesson locally — `FixtureSeeder.starterSeedDefaultsKey` exists so "a home the user
    /// deleted on purpose is never resurrected on the next launch". Sync must honour the same
    /// rule.
    var deletedHomeIDs: [String: Date]

    init(version: Int = SyncState.currentVersion,
         userID: String? = nil,
         records: [String: HomeSyncRecord] = [:],
         deletedHomeIDs: [String: Date] = [:]) {
        self.version = version
        self.userID = userID
        self.records = records
        self.deletedHomeIDs = deletedHomeIDs
    }

    private enum CodingKeys: String, CodingKey {
        case version, userID, records, deletedHomeIDs
    }

    /// Absent collections decode as empty rather than failing the whole file — the same
    /// `decodeIfPresent` pattern `HomeModel` uses for `stairs`, `profiles` and `objects`.
    ///
    /// Without it, a sidecar written before a field existed takes the entire file down with
    /// it, and "one missing key" degrades to "this device has never synced anything". The
    /// `version` guard in `FileSyncStateStore.load` is the deliberate discard; this is the
    /// accidental one, and it should not exist.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        records = try container.decodeIfPresent([String: HomeSyncRecord].self, forKey: .records) ?? [:]
        deletedHomeIDs = try container.decodeIfPresent([String: Date].self, forKey: .deletedHomeIDs) ?? [:]
    }

    static let empty = SyncState()

    func record(for localHomeID: String) -> HomeSyncRecord? { records[localHomeID] }

    mutating func remember(_ record: HomeSyncRecord) {
        records[record.localHomeID] = record
        // Re-syncing a home means it is back; a stale tombstone would suppress it forever.
        deletedHomeIDs.removeValue(forKey: record.localHomeID)
    }

    mutating func forget(localHomeID: String) {
        records.removeValue(forKey: localHomeID)
    }

    // MARK: - Tombstones

    func isDeletedLocally(_ localHomeID: String) -> Bool {
        deletedHomeIDs[localHomeID] != nil
    }

    /// Records a deletion. Also drops the sync record: the home is gone from this device, so
    /// "what this device last synced" no longer describes anything.
    mutating func markDeleted(localHomeID: String, at date: Date) {
        deletedHomeIDs[localHomeID] = date
        records.removeValue(forKey: localHomeID)
    }

    /// The home is on disk again (re-imported, or a stale tombstone from a race), so the
    /// tombstone is wrong and must not keep suppressing it.
    mutating func clearTombstone(localHomeID: String) {
        deletedHomeIDs.removeValue(forKey: localHomeID)
    }

    /// A copy scoped to one account, keeping the records only if they already belong to it.
    ///
    /// This is the whole user-scoping rule in one place: same account, keep everything;
    /// different account (or an unknown one either side), start clean. Starting clean costs
    /// one redundant upload per home and is the only answer that cannot act on another
    /// account's record ids.
    func scoped(to userID: String?) -> SyncState {
        guard self.userID == userID else { return SyncState(userID: userID) }
        return self
    }
}

// MARK: - Storage

protocol SyncStateStore: AnyObject {
    /// Reads must not throw: a sidecar that cannot be read is indistinguishable from one that
    /// does not exist yet, and both mean "re-sync everything", which is safe.
    func load() -> SyncState
    func save(_ state: SyncState) throws
}

/// The real store: one JSON file next to the home documents.
///
/// Deliberately NOT inside `<Documents>/Homes`. `HomeDocumentStore.list()` enumerates that
/// directory, and while it does filter on the `.homeplan.json` suffix today, a file that is
/// not a home has no business sitting in the folder whose contract is "one file per home".
final class FileSyncStateStore: SyncStateStore {
    static let filename = "sync-state.json"

    private let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    /// The app's real sidecar: `<Documents>/sync-state.json`.
    convenience init(fileManager: FileManager = .default) throws {
        let documents = try fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                            appropriateFor: nil, create: true)
        self.init(url: documents.appendingPathComponent(Self.filename), fileManager: fileManager)
    }

    func load() -> SyncState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(SyncState.self, from: data),
              // A sidecar written by a future build describes records in a shape this build
              // may misread. Ignoring it re-syncs; trusting it could push a stale home.
              state.version == SyncState.currentVersion
        else { return .empty }
        return state
    }

    func save(_ state: SyncState) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        // Atomic: a crash mid-write leaves the previous sidecar intact rather than a truncated
        // file that reads as "nothing has ever synced".
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }
}

#if DEBUG
/// Test double. NOT a production fallback — forgetting every record on quit would make the app
/// re-upload the whole library on every launch.
final class InMemorySyncStateStore: SyncStateStore {
    private var state: SyncState
    private(set) var saveCount = 0

    init(_ state: SyncState = .empty) { self.state = state }

    func load() -> SyncState { state }

    func save(_ state: SyncState) throws {
        self.state = state
        saveCount += 1
    }
}
#endif
