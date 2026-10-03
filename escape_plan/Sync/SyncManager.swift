//  SyncManager.swift
//  escape_plan — S8.4 cloud sync
//
//  Runs a sync: read both sides, ask `SyncReconciler` what to do, do it, remember what
//  happened. Every DECISION lives in the reconciler; this type owns only the I/O and the
//  observable status the Home tab renders.
//
//  Three properties it is built to guarantee, each of which has a test:
//
//  1. **It never blocks the app.** Sync is additive — every home works offline, with no
//     account, exactly as it did before S8. A failure here changes a badge and nothing else.
//  2. **One bad home does not stop the library.** A home the server rejects is recorded as a
//     per-home failure and the rest of the plan still runs.
//  3. **It cannot run twice at once.** A double-tap of the sync button, or a launch sync
//     overlapping a manual one, would push the same home twice and mint a duplicate server
//     record — see `SyncReconciler.collapseDuplicates`, which exists to clean up after
//     exactly that happening between two DEVICES. It must not also happen within one.

import Foundation
import Observation

/// One home that could not be synced, and why. Kept per-home so the UI can say "1 home
/// didn't sync" instead of failing a library where everything else went up fine.
struct HomeSyncFailure: Equatable, Sendable {
    let localHomeID: String
    let failure: SyncFailure
}

/// A home whose local copy lost a conflict, and where the losing copy was put.
///
/// Surfaced rather than swallowed: the user edited the same home in two places, one of those
/// edits is no longer the canonical copy, and a badge that just said "Synced" over that would
/// be reporting a silent loss as a success.
struct HomeSyncConflict: Equatable, Sendable {
    let localHomeID: String
    /// The `home_id` of the set-aside copy of what this device had.
    let preservedAs: String
}

/// What a completed run did.
struct SyncOutcome: Equatable, Sendable {
    var pushed: Int = 0
    var pulled: Int = 0
    var unchanged: Int = 0
    /// Homes on the server that this device deleted, and therefore did not download again.
    var skipped: Int = 0
    /// Homes whose server copy was erased because this device had deleted them (S11.7). A
    /// subset of `skipped`: the skip is the decision not to download, this is the cleanup.
    var deletedRemotely: Int = 0
    /// Homes on this device that belong to a different account, and so were neither uploaded
    /// into the signed-in one nor overwritten by it. Counted separately because it is the one
    /// skip the user may be surprised by and should be told about.
    var skippedOtherAccount: Int = 0
    var conflicts: [HomeSyncConflict] = []
    var failures: [HomeSyncFailure] = []

    /// Nothing went wrong AND nothing was quietly replaced. A conflict is not a failure, but
    /// it is not a clean run either — somebody needs to know their other device won.
    var isClean: Bool { failures.isEmpty && conflicts.isEmpty }
    var changed: Int { pushed + pulled }
}

@Observable
@MainActor
final class SyncManager {

    enum Status: Equatable {
        /// No account. Not an error — the app is local-first and fully usable here.
        case signedOut
        /// Signed in, nothing synced yet this launch.
        case idle
        case syncing
        case synced(at: Date, outcome: SyncOutcome)
        /// The run failed as a whole: no token, the library could not be read, or `GET /homes`
        /// failed. Distinct from a `synced` outcome carrying per-home failures.
        case failed(SyncFailure)
    }

    private(set) var status: Status = .signedOut

    /// Set when the server rejected the token, and NOT cleared by the sign-out that follows.
    ///
    /// Without stickiness this state is unreachable on screen: `onSessionExpired` signs the
    /// user out, `RootView` observes `session.state` and re-enters `syncIfSignedIn()`, which
    /// finds no token and overwrites `.failed(.sessionExpired)` with `.signedOut` — so the
    /// user is silently signed out mid-session with no explanation. The badge reads this flag
    /// and says so. Cleared by the next successful sync.
    private(set) var needsReauthentication = false

    private let client: CloudHomesClient
    private let repository: SyncHomeRepository
    private let stateStore: SyncStateStore
    private let tokenProvider: @MainActor () -> AccessToken?
    private let onSessionExpired: @MainActor () -> Void
    private let now: @Sendable () -> Date

    /// Guards against concurrent runs — see property 3 in the header.
    private var isSyncing = false

    /// An account deleted while a sync was in flight. Read by `persist` so the running loop
    /// cannot write its pre-deletion copy of the sidecar back over the wipe. See
    /// `forgetAccount`.
    private var forgottenAccountID: String?

    /// The tombstones the running sync started from. A tombstone in the sidecar that is not in
    /// here was written while the sync ran (a home deleted from "Your homes" mid-sync), and the
    /// running loop's own `state` does not know about it. See `adoptDeletionsWrittenSinceStart`.
    private var deletionsAtStart: [String: HomeDeletion] = [:]

    /// The account the running sync is for, so a tombstone written mid-run can be given the
    /// owner this run just claimed (see `adoptDeletionsWrittenSinceStart`).
    private var runSubject: String?

    /// A sync was asked for while one was already running. Render's free tier has been
    /// measured at a 42 s cold start, which is plenty of time for a user to finish an edit
    /// and tap the badge; dropping that request silently means their edit does not go up and
    /// the badge reports success anyway. Re-enters exactly once so a stuck server cannot
    /// produce an unbounded loop.
    private var wasAskedAgainWhileRunning = false

    init(client: CloudHomesClient,
         repository: SyncHomeRepository,
         stateStore: SyncStateStore,
         tokenProvider: @escaping @MainActor () -> AccessToken?,
         onSessionExpired: @escaping @MainActor () -> Void = {},
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.repository = repository
        self.stateStore = stateStore
        self.tokenProvider = tokenProvider
        self.onSessionExpired = onSessionExpired
        self.now = now
        self.status = tokenProvider() == nil ? .signedOut : .idle
    }

    /// Kept in step with `AuthClient.baseURL` by whoever owns both — this layer is pure
    /// Foundation and cannot reach into `Networking/` to read it.
    var baseURL: URL {
        get { client.baseURL }
        set { client.baseURL = newValue }
    }

    // MARK: - Running a sync

    /// Sync if there is an account, and do nothing at all if there is not.
    ///
    /// The launch and sign-in call sites use this rather than `sync()` so that a signed-out
    /// user never sees a failure badge for a thing they did not ask for.
    func syncIfSignedIn() async {
        guard tokenProvider() != nil else {
            status = .signedOut
            return
        }
        await sync()
    }

    /// Forget everything this device recorded about an account that no longer exists.
    ///
    /// Called after `AuthSession.deleteAccount()` succeeds. Without it the sidecar keeps
    /// ownership claims naming a user id that can never sign in again, so `ownership(of:)`
    /// answers `.anotherAccount` forever and the next person to sign in on this phone can
    /// never back up a single home — with nothing on screen to explain why.
    ///
    /// **Touches the sidecar only.** Not one home document is read, written or removed: the
    /// homes on this device predate the account and outlive it, which is exactly what
    /// `AccountPrivacy.deletionSummary` promises the user on the way in.
    ///
    /// `forgottenAccountID` rather than a straight write, because a sync may be in flight.
    /// `sync()` holds its own `state` across every `await` and persists it after each action,
    /// so a deletion confirmed during a launch sync — up to 90s of it, against a Render
    /// instance that has to wake up — would be wiped here and then written straight back by
    /// the running loop's next `persist`, restoring exactly the dangling ownership claims this
    /// function exists to remove. Both are `@MainActor`, so they cannot interleave mid-
    /// statement; they interleave at suspension points, which is enough. The flag makes the
    /// running loop apply the same forgetting to its own copy before it writes. Found in
    /// review, 2026-09-24.
    func forgetAccount(_ userID: String) {
        forgottenAccountID = userID
        persist(stateStore.load().forgettingAccount(userID))
        needsReauthentication = false
        status = .signedOut
    }

    /// Reconcile this device with the server. Safe to call at any time; concurrent calls
    /// after the first return immediately rather than queueing.
    func sync() async {
        guard !isSyncing else {
            wasAskedAgainWhileRunning = true
            return
        }
        guard let token = tokenProvider() else {
            status = .signedOut
            return
        }

        isSyncing = true
        wasAskedAgainWhileRunning = false
        defer { isSyncing = false }
        status = .syncing

        // A new sync under a DIFFERENT account means the deleted one is history: keeping the
        // flag would silently forget the new account's records on every write.
        if let forgotten = forgottenAccountID, forgotten != token.subject {
            forgottenAccountID = nil
        }

        // Taken BEFORE the library is read. A home deleted after this point, including during
        // the `GET /homes` below (up to 90 s against a cold Render instance), is then seen as
        // new by `adoptDeletionsWrittenSinceStart`, even though `local` still lists it. Taken
        // after the list, its tombstone would read as stale and this run would push it back.
        // `scoped(to:)` never changes `deletions`, so the unscoped read is the same set.
        deletionsAtStart = stateStore.load().deletions
        runSubject = token.subject

        let local: [LocalHome]
        do {
            local = try repository.loadAllHomes().map(LocalHome.init)
        } catch {
            // Reading the library failed. Nothing has been sent, so nothing is inconsistent.
            status = .failed(SyncFailure(
                kind: .unreadableResponse,
                message: "Couldn't read your saved homes, so there was nothing to sync.",
                isRetryable: true, symbol: "exclamationmark.triangle"))
            return
        }

        let remote: [StoredHome]
        do {
            remote = try await client.list(token: token)
        } catch let failure as SyncFailure {
            if failure.requiresReauthentication {
                needsReauthentication = true
                onSessionExpired()
            }
            return fail(with: failure)
        } catch {
            return fail(with: SyncFailure(transport: error))
        }

        // Scope the sidecar to the signed-in account BEFORE reading a single record. A
        // second user on the same device must never inherit the first user's record ids —
        // those point at server records in someone else's account, and acting on one either
        // uploads into the wrong account or reports a home as "already synced, revision 5"
        // that this user has never seen. `AccessToken.subject` is the `sub` claim.
        var state = stateStore.load().scoped(to: token.subject)
        let plan = SyncReconciler.plan(local: local, remote: remote, state: state)
        for homeID in plan.staleRecordHomeIDs { state.forget(localHomeID: homeID) }
        for homeID in plan.staleTombstoneHomeIDs { state.clearTombstone(localHomeID: homeID) }

        let localByID = Dictionary(local.map { ($0.homeID, $0) }, uniquingKeysWith: { first, _ in first })
        // Keyed by the SERVER's record id, which is what a `.pullRemote` action names.
        let remoteByRecordID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var outcome = SyncOutcome()

        for action in plan.actions {
            // Deleted on this device since the plan was made. Pushing it would put it back in
            // the account, and pulling it would put it back on disk.
            // "Since" by value, not by presence: a home whose old tombstone this run cleared (it
            // was back on disk) and that is then deleted again carries a new `deletedAt`.
            adoptDeletionsWrittenSinceStart(into: &state)
            if let current = state.deletions[action.localHomeID],
               current != deletionsAtStart[action.localHomeID] {
                outcome.skipped += 1
                continue
            }
            do {
                try await apply(action, localByID: localByID, remoteByRecordID: remoteByRecordID,
                                token: token, state: &state, outcome: &outcome)
            } catch let failure as SyncFailure {
                // A dead session invalidates every remaining action, so stop rather than
                // collecting the same 401 once per home.
                if failure.requiresReauthentication {
                    persist(state)
                    needsReauthentication = true
                    onSessionExpired()
                    return fail(with: failure)
                }
                outcome.failures.append(
                    HomeSyncFailure(localHomeID: action.localHomeID, failure: failure))
            } catch {
                outcome.failures.append(
                    HomeSyncFailure(localHomeID: action.localHomeID,
                                    failure: SyncFailure(transport: error)))
            }
            // Persisted per action, not once at the end: a twelve-home first sync killed at
            // home ten would otherwise lose all ten records and redo the whole thing next
            // launch — and a home with no record is routed through the conflict tiebreak
            // rather than a clean comparison, which is where the sharp edges are. The write
            // is atomic and cheap.
            persist(state)
        }

        needsReauthentication = false
        status = .synced(at: now(), outcome: outcome)

        // Someone asked again while this was in flight. Serve that request once.
        if wasAskedAgainWhileRunning {
            wasAskedAgainWhileRunning = false
            isSyncing = false
            await sync()
        }
    }

    // MARK: - One action

    private func apply(_ action: SyncAction,
                       localByID: [String: LocalHome],
                       remoteByRecordID: [String: StoredHome],
                       token: AccessToken,
                       state: inout SyncState,
                       outcome: inout SyncOutcome) async throws {
        switch action.operation {

        case .upToDate:
            outcome.unchanged += 1

        case .skip:
            if action.reason == .ownedByAnotherAccount {
                outcome.skippedOtherAccount += 1
            } else {
                outcome.skipped += 1
                // The server still holds a home this device deleted. Until S11.7 there was no
                // delete endpoint, so all the reconciler could do was refuse to download it
                // again, forever, on the strength of a tombstone — and the home stayed in the
                // account, reachable from a second device and from any future sign-in.
                //
                // Now the server copy can actually go. Done HERE rather than as a new
                // `SyncAction.Operation` on purpose: the reconciler's answer is unchanged
                // ("do not download this"), and the plan stays a pure decision about the
                // library. This is the I/O that decision implies, which is what this type is
                // for.
                //
                // Self-limiting: once the DELETE succeeds the home is gone from `GET /homes`,
                // so the next sync produces no action for it at all and nothing is retried.
                // The tombstone STAYS — it is what suppresses the home on a second device,
                // which may still be holding its own copy.
                //
                // ─── THE GATE: only a tombstone THIS ACCOUNT made may delete from the server.
                //
                // `.deletedOnThisDevice` is NOT specific enough to authorise a delete.
                // `SyncReconciler` emits it via `state.isDeletedLocally`, which deliberately
                // also matches an OWNERLESS tombstone — one made before anybody signed in —
                // for whichever account is looking. As a reason not to download, that is
                // correct and harmless. As a reason to erase somebody's cloud copy it is
                // catastrophic, and it is reachable from this repo's own facts: the starter
                // homes keep FIXED `home_id`s across installs, so a fresh install where the
                // user deletes the seeded Bungalow BEFORE signing in produces exactly such a
                // tombstone — and the first sign-in would erase their other device's real
                // Bungalow from the account. Found in review, reproduced, and pinned by
                // `testAnOwnerlessTombstoneNeverDeletesTheAccountsServerCopy`.
                //
                // So this reads the tombstone itself and requires a non-nil owner equal to the
                // signed-in subject. The ownerless case stays the pure skip it was before.
                if action.reason == .deletedOnThisDevice,
                   let owner = state.deletions[action.localHomeID]?.ownerUserID,
                   owner == token.subject {
                    try await deleteRemoteCopies(ofLocalHomeID: action.localHomeID,
                                                 in: remoteByRecordID,
                                                 token: token, outcome: &outcome)
                }
            }

        case .createRemote:
            guard let home = localByID[action.localHomeID] else { return }
            let stored = try await client.push(home.model, remoteID: nil, token: token)
            remember(stored, fingerprintOf: home.model, in: &state)
            outcome.pushed += 1

        case .updateRemote(let remoteID):
            guard let home = localByID[action.localHomeID] else { return }
            let stored: StoredHome
            do {
                stored = try await client.push(home.model, remoteID: remoteID, token: token)
            } catch let failure as SyncFailure where failure.kind == .homeMissing {
                // The record we were updating is gone from the server — deleted out from
                // under us, or a sidecar pointing at a record from a different account. Drop
                // the stale id and create instead, so a user whose home vanished server-side
                // gets it back rather than seeing the same error on every sync forever.
                state.forget(localHomeID: action.localHomeID)
                stored = try await client.push(home.model, remoteID: nil, token: token)
            }
            remember(stored, fingerprintOf: home.model, in: &state)
            outcome.pushed += 1

        case .pullRemote(let remoteID, _):
            // Straight from the `GET /homes` response the plan was built from. There is no
            // `GET /homes/{id}` on the backend, and re-listing once per pulled home would
            // turn a 12-home first sync into 13 round trips against a service that can take
            // most of a minute to wake up.
            guard let stored = remoteByRecordID[remoteID] else { return }

            // Asked BEFORE any copy is made (S11.22, AUD-015). A copy for a pull that is then
            // refused (the home is open in House) left the record unchanged, so every later
            // sync planned the same pull and made one more copy. Refused here, it is a per-home
            // failure whose message the sync badge already shows, and nothing is copied.
            try repository.checkCanWritePulledHome(stored.home)

            // A pull that overwrites edits this device also has sets the local copy aside
            // first. Last-write-wins decides which copy is CANONICAL; it is not a licence to
            // destroy the other one, least of all on a tiebreak between two devices' clocks.
            if action.overwritesLocalEdits, let local = localByID[action.localHomeID],
               let preservedID = try preserveOnce(local, localByID: localByID, state: &state) {
                outcome.conflicts.append(HomeSyncConflict(localHomeID: action.localHomeID,
                                                          preservedAs: preservedID))
            }

            try repository.writePulledHome(stored.home)
            // The fingerprint describes what is now ON DISK, which is the server's copy.
            remember(stored, fingerprintOf: stored.home, in: &state)
            outcome.pulled += 1
        }
    }

    /// Set the local home aside as "<name> (this device)", at most once per version of it.
    ///
    /// A copy is recorded in `state` before the pull is written, so if the write then fails the
    /// next sync finds it instead of making another. Returns the copy's id, or nil when this
    /// same version was copied before and the user has since deleted that copy (S11.21 lets
    /// them): they discarded it, so it is neither brought back nor made again.
    ///
    /// A local home edited AFTER its copy was made has a new fingerprint, so that version is
    /// new work and gets a copy of its own. Reachable only when a write failed after the first
    /// copy, since a refused write is caught before any copy is made.
    ///
    /// A copy still on disk but undecodable is absent from `localByID` and read as deleted: no
    /// new copy is made, and the file itself is left alone.
    private func preserveOnce(_ local: LocalHome,
                              localByID: [String: LocalHome],
                              state: inout SyncState) throws -> String? {
        if let earlier = state.preservedCopies[local.homeID],
           earlier.preservedFingerprint == local.fingerprint {
            return localByID[earlier.copyHomeID] == nil ? nil : earlier.copyHomeID
        }
        let copyID = try repository.preserveLocalCopy(
            of: local.model, named: "\(local.model.name) (this device)")
        state.preservedCopies[local.homeID] = PreservedCopy(copyHomeID: copyID,
                                                            preservedFingerprint: local.fingerprint)
        return copyID
    }

    /// Delete EVERY server record for one deleted home, tolerating the failure that means
    /// success.
    ///
    /// All of them, not the first match: the server can hold duplicate records for one
    /// `home_id` — two devices racing to create it, which is the whole reason
    /// `SyncReconciler.collapseDuplicates` exists — and the reconciler collapses those to a
    /// single action. Deleting one per sync would leave the home in the account until the user
    /// happened to sync again, and `Dictionary.values.first` would pick which survivor in
    /// unspecified order.
    ///
    /// A 404 is `.homeMissing`, which for a delete is the outcome we wanted — another device
    /// got there first. Anything else is recorded as a per-home failure like any other, so a
    /// server that refuses the delete does not take the rest of the sync down with it.
    private func deleteRemoteCopies(ofLocalHomeID localHomeID: String,
                                    in remoteByRecordID: [String: StoredHome],
                                    token: AccessToken,
                                    outcome: inout SyncOutcome) async throws {
        // Sorted so a sync is deterministic, which matters when one of several deletes fails.
        let doomed = remoteByRecordID.values
            .filter { $0.localHomeID == localHomeID }
            .map(\.id)
            .sorted()
        for remoteID in doomed {
            do {
                try await client.delete(remoteID: remoteID, token: token)
            } catch let failure as SyncFailure where failure.kind == .homeMissing {
                continue
            }
            outcome.deletedRemotely += 1
        }
    }

    private func remember(_ stored: StoredHome, fingerprintOf home: HomeModel, in state: inout SyncState) {
        state.remember(HomeSyncRecord(
            localHomeID: stored.localHomeID,
            remoteID: stored.id,
            syncedRevision: stored.revision,
            syncedFingerprint: HomeFingerprint.of(home),
            lastSyncedAt: now()))
    }

    /// A sidecar that cannot be written is not worth failing a sync over — the work already
    /// landed on the server. The cost is one redundant upload next launch.
    /// The single write path for the sidecar, which is what makes the deleted-account guard
    /// possible: a sync that was already running when the account was deleted still holds a
    /// `state` describing it, and applying the same forgetting on the way out is cheaper and
    /// safer than trying to cancel the loop mid-flight.
    ///
    /// The same reasoning covers a home deleted while a sync runs (S11.22, a finding from
    /// S11.21): `HomeDocumentSyncRepository.homeWasDeletedLocally` writes its tombstone straight
    /// to the sidecar, and writing this sync's older `state` over it would drop the tombstone
    /// and its owner, so the next sync would download the deleted home again.
    private func persist(_ state: SyncState) {
        var state = state
        adoptDeletionsWrittenSinceStart(into: &state)
        state = forgottenAccountID.map(state.forgettingAccount) ?? state
        try? stateStore.save(state)
    }

    /// Copy into `state` every tombstone the sidecar gained since this sync started.
    ///
    /// Compared against `deletionsAtStart`, not against `state`, because this sync clears
    /// tombstones on purpose (a home back on disk); those were in the sidecar at the start and
    /// must not be put back. A tombstone written during the run wins over anything the run did
    /// to that home since: the user deleted it after the plan was made.
    ///
    /// Owner: `markDeleted` reads the owner from the sidecar, and a home first uploaded by THIS
    /// run is claimed only in the run's own `state` until the next `persist`. Deleted during
    /// that upload, its tombstone has no owner, and an ownerless tombstone never deletes the
    /// server copy, so the home would stay in the account for good. Only a claim by this run's
    /// own account fills it in; any other owner would let `forgettingAccount` drop it.
    ///
    /// Reads the sidecar twice per action (before it and in `persist`), on purpose: a delete
    /// can land in either gap. The file is small and the read is cheap.
    private func adoptDeletionsWrittenSinceStart(into state: inout SyncState) {
        guard isSyncing else { return }
        for (homeID, written) in stateStore.load().deletions
        where deletionsAtStart[homeID] != written {
            var deletion = written
            if deletion.ownerUserID == nil, let subject = runSubject,
               state.homeOwners[homeID] == subject {
                deletion = HomeDeletion(deletedAt: written.deletedAt, ownerUserID: subject)
            }
            guard state.deletions[homeID] != deletion else { continue }
            state.apply(deletion, to: homeID)
        }
    }

    private func fail(with failure: SyncFailure) {
        status = .failed(failure)
    }
}
