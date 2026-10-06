//  escape_planApp.swift
//  escape_plan
//
//  S0.3: replaced the stock Core Data template wholesale. Persistence is local JSON documents
//  via FileManager (S2.4), not Core Data — this entry point owns the shared APIClient, and
//  since S8.3 the AuthSession too.

import os
import SwiftUI

@main
// @MainActor because the default value of `authSession` below constructs a @MainActor type in
// this struct's otherwise-nonisolated init. Correct at runtime either way (App.main() is on the
// main thread) and accepted in Swift 5 mode, but an error under Swift 6.
@MainActor
struct escape_planApp: App {
    @State private var apiClient = APIClient()

    /// Set when the starter homes could not be installed and the person has not been told yet.
    /// Shown once as an alert on the root view; see `StarterSeedingNotice`.
    @State private var seedingNotice: String?

    /// The signed-in account, or the absence of one. Built here rather than in a view so the
    /// Keychain is read once per launch instead of once per view rebuild.
    ///
    /// It takes the same base URL the APIClient starts with; Settings keeps the two in step
    /// when that changes. The auth layer is pure Foundation by design (it is symlinked into
    /// the EditorCore package so it can be tested without a simulator) and so cannot reach
    /// into Networking/ to read it for itself.
    @State private var authSession: AuthSession

    /// The bridge between the home documents on disk and the signed-in account's copies
    /// (S8.4). Built here, alongside the AuthSession it reads its token from, so there is
    /// exactly one of each per launch.
    @State private var syncRepository: HomeDocumentSyncRepository
    @State private var syncManager: SyncManager

    /// The one home store for this launch, shared by the library, sync and every tab.
    private let homeStore: HomeDocumentStore
    /// True when Documents could not be opened and `homeStore` is a temporary stand-in:
    /// ContentView then says, permanently, that changes will not be saved.
    private let storageUnavailable: Bool

    init() {
        AppAppearance.install()
        ScanStore.sweepStaleScansInBackground() // S11.40: drop raw scans left over a week (Release)

        // Created ONCE, here, without a `try!` (audit 2026-09-25). There used to be two
        // instances and two force-tries (here and in ContentView), so an unreachable Documents
        // directory crashed the app before its first frame instead of degrading.
        let launch = HomeDocumentStore.launchStore()
        let homeStore = launch.store
        self.homeStore = homeStore
        self.storageUnavailable = launch.isFallback

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TEST_SEED_DEMO_HOME"),
           var model = try? FixtureLoader.load(.twostory) {
            model.home_id = "TEST-DEMO-HOME-1234"
            try? homeStore.save(model: model)
        }
#endif

        // Install the three starter homes before any screen reads the library.
        // At launch rather than inside onboarding on purpose: skipping the tour
        // ("I'll map my own home") must not leave the demo path with nothing to
        // demo. Guarded by a defaults flag, so it happens exactly once — which is also why it
        // is skipped on the temporary fallback store: seeding there would spend the flag on
        // homes that vanish, and the real library would never get them.
        var seedingNotice: String?
        if !launch.isFallback {
            do {
                try FixtureSeeder.seedStarterHomes(into: homeStore)
            } catch {
                // A missing bundled fixture must not stop the app from launching —
                // the library simply starts empty, exactly as it did before. It is no longer
                // silent: the person gets one notice (AUD-049, S11.48).
                seedingNotice = StarterSeedingNotice.noticeToShow(for: error)
            }
        }
        _seedingNotice = State(initialValue: seedingNotice)

#if DEBUG
        // UI tests only (S11.57): a /score answer handed in by the test, cached for every home, so
        // the layout tests see a score card and a checklist with no server running. The app shows
        // it exactly as it shows any cached score; the live /score still runs (and fails offline).
        // Tagged by its `home_name`, and removed again on the next launch without the variable, so a
        // canned score never outlives the UI test run on this simulator.
        if let cache = try? ScoreCache() {
            let tag = "UITEST_CANNED_SCORE"
            if let json = ProcessInfo.processInfo.environment[tag],
               let canned = try? JSONDecoder().decode(ScoreBreakdown.self, from: Data(json.utf8)) {
                for summary in homeStore.list() {
                    var score = canned
                    score.home_id = summary.id
                    score.home_name = tag
                    cache.save(score, for: summary.id)
                }
            } else {
                for summary in homeStore.list() where cache.load(homeID: summary.id)?.home_name == tag {
                    cache.remove(homeID: summary.id)
                }
            }
        }
#endif

        // One sidecar, shared: the repository writes deletion tombstones into it and the
        // manager reads and writes sync records. Two instances over the same file would
        // last-write-wins each other's updates.
        let syncStateStore = FileSyncStateStore(
            url: homeStore.directory.deletingLastPathComponent()
                .appendingPathComponent(FileSyncStateStore.filename))
        let repository = HomeDocumentSyncRepository(store: homeStore, stateStore: syncStateStore)
        _syncRepository = State(wrappedValue: repository)

        // Constructed as a local and handed to BOTH the State wrapper and the sync manager, so
        // the token closure holds the same instance the views get. Deliberately not read back
        // out of `_authSession.wrappedValue`: reading a State's value before the property
        // wrapper is installed on a view is not a supported access.
        let session = AuthSession(client: AuthClient(baseURL: APIClient.currentBaseURL()),
                                  store: KeychainTokenStore())
        _authSession = State(wrappedValue: session)
        _syncManager = State(wrappedValue: SyncManager(
            client: CloudHomesClient(baseURL: APIClient.currentBaseURL()),
            repository: repository,
            // A sidecar beside the home documents, NOT a field on HomeModel: tracking a synced
            // revision inside the schema would be a `schema_version` bump, and sync progress is
            // a fact about this device rather than a property of the home. Its URL is derived
            // from the home store's own directory rather than re-resolving Documents with a
            // fallback — an earlier version fell back to the temporary directory, which the
            // system may purge, so the sidecar would vanish and every launch would read
            // "nothing has ever synced".
            stateStore: syncStateStore,
            tokenProvider: { session.token },
            // A 401 means the JWT is dead. Signing out locally is what puts the user in front
            // of a sign-in form instead of watching sync fail silently every launch.
            onSessionExpired: { session.signOut() }))
    }

    var body: some Scene {
        WindowGroup {
            RootView(homeStore: homeStore, storageUnavailable: storageUnavailable)
                .environment(apiClient)
                .environment(authSession)
                .environment(syncManager)
                .environment(syncRepository)
                // Dark only (the Linear revamp, 2026-09-25). Set at the root so every sheet
                // and cover inherits it.
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .alert("Starter homes unavailable", isPresented: Binding(
                    get: { seedingNotice != nil },
                    set: { if !$0 { seedingNotice = nil; StarterSeedingNotice.markShown() } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(seedingNotice ?? "")
                }
        }
    }
}

/// The one-time notice for a starter-home seeding failure (AUD-049). A failed seed does not spend
/// the seeding flag, so it is retried every launch; the notice has its own flag so a failure that
/// keeps happening (a build with a missing fixture, which no one on the device can fix) is said
/// once and not on every launch.
enum StarterSeedingNotice {
    static let shownDefaultsKey = "fixtures.starterSeedingFailureNoticeShown.v1"

    static let message = "The sample homes couldn't be set up. You can still build your own "
        + "from the Home tab. Restarting the app will try again."

    /// Logs the failure, and returns the message unless it has already been announced. It does not
    /// record anything: `markShown` does, when the alert is dismissed, so an app killed before the
    /// person saw it still tells them next launch.
    static func noticeToShow(for error: Error, defaults: UserDefaults = .standard) -> String? {
        Logger(subsystem: "escape_plan", category: "Launch")
            .error("Starter-home seeding failed: \(String(describing: error), privacy: .public)")
        return defaults.bool(forKey: shownDefaultsKey) ? nil : message
    }

    static func markShown(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: shownDefaultsKey)
    }
}
