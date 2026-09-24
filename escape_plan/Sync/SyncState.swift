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

/// One home's deletion, remembered so the server cannot undo it.
struct HomeDeletion: Codable, Equatable, Sendable {
    let deletedAt: Date
    /// The account that owned the home when it was deleted, if any.
    ///
    /// Carried so a deletion suppresses only the account it happened in. The three starter
    /// homes keep FIXED `home_id`s, so without this, user A deleting the bundled Bungalow on a
    /// shared device would stop user B from ever receiving *their own* Bungalow from *their*
    /// account — one person's deletion silently editing another person's library.
    let ownerUserID: String?
}

/// Every `HomeSyncRecord` this device holds, keyed by schema `home_id`, plus the tombstones
/// for homes deleted here, plus who owns what.
///
/// Versioned from the start. This file is read by a future build that may have changed its
/// shape, and an unreadable sidecar must degrade to "nothing has ever synced" — which costs
/// one redundant upload per home — rather than to a crash or to silent data loss.
struct SyncState: Codable, Equatable, Sendable {
    /// 2 added `userID` and tombstones; 3 (2026-09-16) added `homeOwners` and gave each
    /// tombstone an owner. An older sidecar cannot answer "whose home is this?", and guessing
    /// would either leak one account's homes into another's or refuse to back up a first-time
    /// user's entire library — so the version guard in `FileSyncStateStore.load` discards it
    /// and the device re-syncs from scratch.
    static let currentVersion = 3

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

    /// Homes deleted on this device, keyed by `home_id`. The backend has no delete endpoint,
    /// so the server keeps serving a deleted home forever; without a tombstone the next sync
    /// downloads it again and it reappears in the library. The app already learned this
    /// lesson locally — `FixtureSeeder.starterSeedDefaultsKey` exists so "a home the user
    /// deleted on purpose is never resurrected on the next launch". Sync must honour the same
    /// rule.
    var deletions: [String: HomeDeletion]

    /// Which account claimed each home, keyed by `home_id`. **Survives an account switch** —
    /// unlike `records`, which are server ids that mean nothing to a different account.
    ///
    /// This is the whole answer to "do local homes belong to whoever signs in?". See
    /// `ownership(of:)`.
    var homeOwners: [String: String]

    init(version: Int = SyncState.currentVersion,
         userID: String? = nil,
         records: [String: HomeSyncRecord] = [:],
         deletions: [String: HomeDeletion] = [:],
         homeOwners: [String: String] = [:]) {
        self.version = version
        self.userID = userID
        self.records = records
        self.deletions = deletions
        self.homeOwners = homeOwners
    }

    private enum CodingKeys: String, CodingKey {
        case version, userID, records, deletions, homeOwners
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
        deletions = try container.decodeIfPresent([String: HomeDeletion].self, forKey: .deletions) ?? [:]
        homeOwners = try container.decodeIfPresent([String: String].self, forKey: .homeOwners) ?? [:]
    }

    static let empty = SyncState()

    func record(for localHomeID: String) -> HomeSyncRecord? { records[localHomeID] }

    mutating func remember(_ record: HomeSyncRecord) {
        records[record.localHomeID] = record
        // A home that just synced belongs to whoever synced it.
        if let userID { homeOwners[record.localHomeID] = userID }
        // Re-syncing a home means it is back; a stale tombstone would suppress it forever.
        deletions.removeValue(forKey: record.localHomeID)
    }

    mutating func forget(localHomeID: String) {
        records.removeValue(forKey: localHomeID)
    }

    // MARK: - Ownership

    /// Who a home belongs to, from this device's point of view.
    enum Ownership: Equatable, Sendable {
        /// No account has ever synced it. The signing-in account may adopt it.
        case unclaimed
        /// It belongs to the account currently signed in.
        case mine
        /// It belongs to a DIFFERENT account that has used this device.
        case anotherAccount(userID: String)
    }

    /// ─── THE RULE: first account to sign in adopts the device's homes; a second one never
    /// does. ───────────────────────────────────────────────────────────────────────────────
    ///
    /// The app is local-first, so homes exist before any account does, and the common case by
    /// far is one person who used the app offline and then signed up — for them "sign in to
    /// back up your homes" has to mean exactly that, or the feature does nothing. So an
    /// unclaimed home is adopted.
    ///
    /// The case that must NOT be served the same way is a shared device: a family phone, a
    /// demo iPad, a handed-down handset. There, uploading the previous user's homes into the
    /// new user's account would copy someone's home layout, `meta.address_optional` and
    /// household composition into a stranger's cloud account permanently, with no prompt and
    /// nothing to undo it. Ownership is recorded the moment a home first syncs, survives the
    /// account switch, and a home owned by someone else is left strictly alone — not pushed,
    /// not pulled, not overwritten.
    ///
    /// The deliberate gap: a home owned by another account stays VISIBLE on this device. The
    /// boundary for that is the phone's own lock screen, not sync, and deleting a previous
    /// user's homes on sign-in would be a far worse failure than showing them.
    func ownership(of localHomeID: String) -> Ownership {
        guard let owner = homeOwners[localHomeID] else { return .unclaimed }
        return owner == userID ? .mine : .anotherAccount(userID: owner)
    }

    // MARK: - Tombstones

    /// Whether a deletion recorded here should suppress a home the server is still serving.
    ///
    /// Scoped to the account it happened in. A deletion with no owner was made before anyone
    /// signed in, so the home was never in any account and the tombstone is harmless whoever
    /// is looking.
    func isDeletedLocally(_ localHomeID: String) -> Bool {
        guard let deletion = deletions[localHomeID] else { return false }
        return deletion.ownerUserID == nil || deletion.ownerUserID == userID
    }

    /// Records a deletion. Also drops the sync record: the home is gone from this device, so
    /// "what this device last synced" no longer describes anything.
    mutating func markDeleted(localHomeID: String, at date: Date) {
        // Capture the owner into the tombstone, then release the claim. A home that is gone
        // from this device is not owned by anyone ON this device any more, and leaving the
        // claim behind would make a later account's OWN copy of that id read as "somebody
        // else's home" and be skipped forever — the starter homes share fixed ids, so that is
        // reachable, not theoretical. The tombstone keeps the owner so the deletion still
        // applies to the account it happened in, and only that one.
        deletions[localHomeID] = HomeDeletion(deletedAt: date,
                                              ownerUserID: homeOwners[localHomeID])
        homeOwners.removeValue(forKey: localHomeID)
        records.removeValue(forKey: localHomeID)
    }

    /// The home is on disk again (re-imported, or a stale tombstone from a race), so the
    /// tombstone is wrong and must not keep suppressing it.
    mutating func clearTombstone(localHomeID: String) {
        deletions.removeValue(forKey: localHomeID)
    }

    /// Erase every trace of one account from the sidecar, after it has been deleted.
    ///
    /// Stronger than `scoped(to:)`, which only drops the server ids: the account no longer
    /// exists, so its ownership claims must go too. Leaving them behind would mark the
    /// device's homes as belonging to an account that can never sign in again, and
    /// `ownership(of:)` would report `.anotherAccount` forever — the next person to sign in on
    /// this phone would never be able to back up a single home, with nothing on screen to
    /// explain why.
    ///
    /// Tombstones from that account go for the same reason. They are scoped to the owner who
    /// made them, so once the owner is gone they can never match again, and a deletion cannot
    /// be undone by a server copy that has also been deleted.
    ///
    /// Homes owned by a DIFFERENT account are untouched: deleting my account is not a licence
    /// to rewrite what this device knows about somebody else's.
    func forgettingAccount(_ userID: String) -> SyncState {
        let isCurrent = self.userID == userID
        return SyncState(
            version: version,
            userID: isCurrent ? nil : self.userID,
            // `records` describe whichever account the sidecar is scoped to, so they are only
            // this account's when it IS that account. Clearing them unconditionally would
            // throw away a different signed-in account's sync history for no reason.
            records: isCurrent ? [:] : records,
            deletions: deletions.filter { $0.value.ownerUserID != userID },
            homeOwners: homeOwners.filter { $0.value != userID })
    }

    /// A copy scoped to one account.
    ///
    /// `records` are server ids and mean nothing to a different account, so they go. Ownership
    /// and tombstones are facts about THIS DEVICE rather than about one login, so they stay —
    /// dropping them is what would let a second account adopt the first one's homes, and let
    /// the server undo a deletion simply because someone else signed in.
    func scoped(to userID: String?) -> SyncState {
        guard self.userID != userID else { return self }
        return SyncState(version: version,
                         userID: userID,
                         records: [:],
                         deletions: deletions,
                         homeOwners: homeOwners)
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
