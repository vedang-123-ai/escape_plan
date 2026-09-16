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

/// What a completed run did.
struct SyncOutcome: Equatable, Sendable {
    var pushed: Int = 0
    var pulled: Int = 0
    var unchanged: Int = 0
    var failures: [HomeSyncFailure] = []

    var isClean: Bool { failures.isEmpty }
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

    private let client: CloudHomesClient
    private let repository: SyncHomeRepository
    private let stateStore: SyncStateStore
    private let tokenProvider: @MainActor () -> AccessToken?
    private let onSessionExpired: @MainActor () -> Void
    private let now: @Sendable () -> Date

    /// Guards against concurrent runs — see property 3 in the header.
    private var isSyncing = false

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

    /// Reconcile this device with the server. Safe to call at any time; concurrent calls
    /// after the first return immediately rather than queueing.
    func sync() async {
        guard !isSyncing else { return }
        guard let token = tokenProvider() else {
            status = .signedOut
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        status = .syncing

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
            return fail(with: failure)
        } catch {
            return fail(with: SyncFailure(transport: error))
        }

        var state = stateStore.load()
        let plan = SyncReconciler.plan(local: local, remote: remote, state: state)
        for staleID in plan.staleRecordIDs { state.forget(localHomeID: staleID) }

        let localByID = Dictionary(local.map { ($0.homeID, $0) }, uniquingKeysWith: { first, _ in first })
        // Keyed by the SERVER's record id, which is what a `.pullRemote` action names.
        let remoteByRecordID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var outcome = SyncOutcome()

        for action in plan.actions {
            do {
                try await apply(action, localByID: localByID, remoteByRecordID: remoteByRecordID,
                                token: token, state: &state, outcome: &outcome)
            } catch let failure as SyncFailure {
                // A dead session invalidates every remaining action, so stop rather than
                // collecting the same 401 once per home.
                if failure.requiresReauthentication {
                    persist(state)
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
        }

        persist(state)
        status = .synced(at: now(), outcome: outcome)
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
            try repository.writePulledHome(stored.home)
            // The fingerprint describes what is now ON DISK, which is the server's copy.
            remember(stored, fingerprintOf: stored.home, in: &state)
            outcome.pulled += 1
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
    private func persist(_ state: SyncState) {
        try? stateStore.save(state)
    }

    private func fail(with failure: SyncFailure) {
        status = .failed(failure)
    }
}
