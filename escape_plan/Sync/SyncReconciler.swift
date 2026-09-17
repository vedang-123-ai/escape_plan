//  SyncReconciler.swift
//  escape_plan — S8.4 cloud sync
//
//  Given what is on this device, what is on the server, and what this device remembers about
//  the last sync, decide what to do about each home.
//
//  A PURE FUNCTION over three value inputs — no networking, no file I/O, no clock. That is
//  deliberate and it is what makes S8.4's hard half testable on a machine with no simulator:
//  every branch below, including both sides of the conflict rule, is exercised by
//  `SyncReconcilerTests` with hand-built inputs. `SyncManager` does the I/O and owns none of
//  the decisions.
//
//  ─── HOW THE TWO SIDES ARE MATCHED ────────────────────────────────────────────────────────
//  On the schema's `home_id`, NOT on the server's record id. `home_id` travels inside the
//  document, so a home created on one device keeps the same `home_id` after it has been
//  through the server and landed on a second device. The server's id is per-record and known
//  only to whoever created it. Matching on the server id would make "the same home" a
//  different home on every device.
//
//  ─── HOW A CONFLICT IS SETTLED ────────────────────────────────────────────────────────────
//  `revision` answers "is the server ahead of what I last saw?" — a monotonic counter the
//  server owns, which is the only trustworthy signal, because two devices' clocks disagree.
//  It cannot, on its own, settle a genuine conflict (edited here AND edited there), because
//  by construction both sides are ahead. For that and only that, the tiebreak is
//  `meta.modified` — last write wins — and an exact tie goes to the server, so that two
//  devices reconciling the same pair reach the SAME answer rather than each preferring itself
//  and ping-ponging the home back and forth forever.

import Foundation

/// One home as it exists on this device, with its value-identity digest.
struct LocalHome: Equatable, Sendable {
    let model: HomeModel
    let fingerprint: String

    var homeID: String { model.home_id }

    init(model: HomeModel) {
        self.model = model
        self.fingerprint = HomeFingerprint.of(model)
    }
}

/// What to do about one home.
struct SyncAction: Equatable, Sendable {

    enum Operation: Equatable, Sendable {
        /// `POST /homes` with no `home_id` — the server mints a record.
        case createRemote
        /// `POST /homes` with this `home_id` — the server increments its revision.
        case updateRemote(remoteID: String)
        /// Write the server's copy over the local document.
        case pullRemote(remoteID: String, revision: Int)
        /// Nothing to do. Still returned rather than omitted, so the plan accounts for every
        /// home and a test can tell "decided nothing was needed" from "never considered it".
        case upToDate
        /// Deliberately left alone — the home was deleted on this device, or it belongs to a
        /// different account. See `SyncAction.Reason`.
        case skip
    }

    /// Why, in enough detail to explain a surprising sync in a bug report — and, for the two
    /// conflict cases, to tell the user their other device's edit won.
    enum Reason: Equatable, Sendable {
        case newLocalHome
        case newRemoteHome
        case localEdits
        case remoteEdits
        /// Edited in both places; this device's `meta.modified` is later.
        case conflictLocalWins
        /// Edited in both places; the server's `meta.modified` is later, or it is a tie.
        case conflictRemoteWins
        /// Both sides have the home but this device has no record of ever syncing it —
        /// a reinstall, or a sidecar that was lost. Settled the same way a conflict is.
        case neverSyncedOnThisDevice
        /// This device remembered a server record that is gone. Re-create it.
        case staleRecordRemoteGone
        /// The server still has a home this device deleted. Not downloaded again — see
        /// `SyncState.deletions`.
        case deletedOnThisDevice
        /// The home belongs to a different account that has used this device. Never uploaded
        /// into the signed-in account, and never overwritten by it — see
        /// `SyncState.ownership(of:)`.
        case ownedByAnotherAccount
        case unchanged
    }

    /// Whether applying this action overwrites the local document with the server's copy
    /// while this device also had changes of its own. The caller keeps a copy before
    /// proceeding, so a losing edit is set aside rather than destroyed.
    var overwritesLocalEdits: Bool {
        guard case .pullRemote = operation else { return false }
        return reason == .conflictRemoteWins || reason == .neverSyncedOnThisDevice
    }

    let localHomeID: String
    let operation: Operation
    let reason: Reason
}

struct SyncPlan: Equatable, Sendable {
    let actions: [SyncAction]

    var hasWork: Bool {
        actions.contains { $0.operation != .upToDate && $0.operation != .skip }
    }

    /// Homes whose sync record points at a server copy that is gone. Named for what it holds —
    /// schema `home_id`s, the key `SyncState.records` is stored under, NOT server record ids.
    /// `SyncManager` drops them so the next sync does not try to update a record that is not
    /// there.
    let staleRecordHomeIDs: [String]

    /// Tombstones that no longer describe anything, because the home is on disk again.
    /// `SyncManager` clears them so a re-imported home is not suppressed forever.
    let staleTombstoneHomeIDs: [String]
}

enum SyncReconciler {

    /// Decide what to do about every home on either side.
    ///
    /// Deterministic: the returned actions are ordered by `localHomeID` so two runs over the
    /// same inputs produce byte-identical plans, which is what lets the tests assert on whole
    /// plans instead of hunting for elements.
    static func plan(local: [LocalHome],
                     remote: [StoredHome],
                     state: SyncState) -> SyncPlan {

        let localByID = Dictionary(local.map { ($0.homeID, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteByID = collapseDuplicates(remote)

        var actions: [SyncAction] = []
        var staleRecordHomeIDs: [String] = []
        var staleTombstoneHomeIDs: [String] = []

        for homeID in Set(localByID.keys).union(remoteByID.keys).sorted() {
            let localHome = localByID[homeID]
            let remoteHome = remoteByID[homeID]
            let record = state.record(for: homeID)

            // A home on disk contradicts its own tombstone — it was re-imported, or the
            // tombstone lost a race with a pull. The file is the truth; drop the tombstone
            // and reconcile the home normally.
            let deletedHere = state.isDeletedLocally(homeID)
            if localHome != nil && deletedHere { staleTombstoneHomeIDs.append(homeID) }

            // A home claimed by a DIFFERENT account is left strictly alone: not pushed into
            // the signed-in account, not overwritten by it. Checked before anything else,
            // because every branch below would otherwise do one or the other. See
            // `SyncState.ownership(of:)` for why the first account to sign in adopts a
            // device's homes and a second one never does.
            if case .anotherAccount = state.ownership(of: homeID) {
                actions.append(SyncAction(localHomeID: homeID,
                                          operation: .skip,
                                          reason: .ownedByAnotherAccount))
                continue
            }

            switch (localHome, remoteHome) {

            case let (.some(localHome), .none):
                // On this device only. Either it has never been uploaded, or the record we
                // hold points at a server copy that no longer exists — the backend has no
                // delete endpoint, so the second case means the record is stale, not that the
                // user deleted the home elsewhere. Re-create either way; the alternative
                // (deleting the local home) would destroy data on the strength of a guess.
                if record != nil { staleRecordHomeIDs.append(localHome.homeID) }
                actions.append(SyncAction(
                    localHomeID: homeID,
                    operation: .createRemote,
                    reason: record == nil ? .newLocalHome : .staleRecordRemoteGone))

            case let (.none, .some(remoteHome)):
                // Deleted here, and the server still has it because there is no delete
                // endpoint. Downloading it again would undo a deliberate deletion — the exact
                // resurrection `FixtureSeeder.starterSeedDefaultsKey` exists to prevent
                // locally. Skip it, and keep skipping it.
                guard !deletedHere else {
                    actions.append(SyncAction(localHomeID: homeID,
                                              operation: .skip,
                                              reason: .deletedOnThisDevice))
                    continue
                }
                // On the server only — this is a home created on ANOTHER DEVICE, which is the
                // whole point of the feature.
                actions.append(SyncAction(
                    localHomeID: homeID,
                    operation: .pullRemote(remoteID: remoteHome.id, revision: remoteHome.revision),
                    reason: .newRemoteHome))

            case let (.some(localHome), .some(remoteHome)):
                actions.append(decideMatched(local: localHome, remote: remoteHome, record: record))

            case (.none, .none):
                continue  // unreachable: the id came from one of the two dictionaries.
            }
        }

        return SyncPlan(actions: actions,
                        staleRecordHomeIDs: staleRecordHomeIDs.sorted(),
                        staleTombstoneHomeIDs: staleTombstoneHomeIDs.sorted())
    }

    // MARK: - The matched case

    private static func decideMatched(local: LocalHome,
                                      remote: StoredHome,
                                      record: HomeSyncRecord?) -> SyncAction {
        let homeID = local.homeID

        guard let record else {
            // Present on both sides with no memory of a sync. Cannot tell who is ahead, so
            // fall straight to the tiebreak rather than guessing a direction.
            return settleConflict(local: local, remote: remote, reason: .neverSyncedOnThisDevice)
        }

        let localEdited = local.fingerprint != record.syncedFingerprint
        // `>` not `!=`: revision only ever increases, and a server that reported something
        // LOWER than we recorded is a state we cannot interpret — treating it as "not ahead"
        // keeps the local copy, which is the direction that cannot lose the user's work.
        let remoteEdited = remote.revision > record.syncedRevision

        switch (localEdited, remoteEdited) {
        case (false, false):
            return SyncAction(localHomeID: homeID, operation: .upToDate, reason: .unchanged)
        case (true, false):
            return SyncAction(localHomeID: homeID,
                              operation: .updateRemote(remoteID: remote.id),
                              reason: .localEdits)
        case (false, true):
            return SyncAction(localHomeID: homeID,
                              operation: .pullRemote(remoteID: remote.id, revision: remote.revision),
                              reason: .remoteEdits)
        case (true, true):
            return settleConflict(local: local, remote: remote, reason: nil)
        }
    }

    /// Last write wins, by `meta.modified`. A tie goes to the server — see the header.
    private static func settleConflict(local: LocalHome,
                                       remote: StoredHome,
                                       reason forced: SyncAction.Reason?) -> SyncAction {
        let localWins = local.model.meta.modified > remote.home.meta.modified
        if localWins {
            return SyncAction(localHomeID: local.homeID,
                              operation: .updateRemote(remoteID: remote.id),
                              reason: forced ?? .conflictLocalWins)
        }
        return SyncAction(localHomeID: local.homeID,
                          operation: .pullRemote(remoteID: remote.id, revision: remote.revision),
                          reason: forced ?? .conflictRemoteWins)
    }

    // MARK: - Duplicate server records

    /// Two devices that both create the same home before either syncs each `POST /homes` with
    /// no `home_id`, so the server mints TWO records carrying the same embedded `home_id`.
    /// The backend cannot prevent this — it has no uniqueness constraint on a field inside the
    /// document — so the client must pick one, and every device must pick the SAME one or they
    /// will fight.
    ///
    /// Highest `revision` wins (it has absorbed the most accepted writes), then latest
    /// `updated_at`, then lowest record id as a final deterministic tiebreak. The losing
    /// record is left on the server rather than deleted: there is no delete endpoint, and
    /// silently discarding a record that may hold a user's only copy of an edit is worse than
    /// leaving an orphan.
    private static func collapseDuplicates(_ remote: [StoredHome]) -> [String: StoredHome] {
        var best: [String: StoredHome] = [:]
        for home in remote {
            guard let incumbent = best[home.localHomeID] else {
                best[home.localHomeID] = home
                continue
            }
            if wins(home, over: incumbent) { best[home.localHomeID] = home }
        }
        return best
    }

    private static func wins(_ candidate: StoredHome, over incumbent: StoredHome) -> Bool {
        if candidate.revision != incumbent.revision { return candidate.revision > incumbent.revision }
        if candidate.updated_at != incumbent.updated_at { return candidate.updated_at > incumbent.updated_at }
        return candidate.id < incumbent.id
    }
}
