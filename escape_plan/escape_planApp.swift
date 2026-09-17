//  escape_planApp.swift
//  escape_plan
//
//  S0.3: replaced the stock Core Data template wholesale. Persistence is local JSON documents
//  via FileManager (S2.4), not Core Data — this entry point owns the shared APIClient, and
//  since S8.3 the AuthSession too.

import SwiftUI

@main
// @MainActor because the default value of `authSession` below constructs a @MainActor type in
// this struct's otherwise-nonisolated init. Correct at runtime either way (App.main() is on the
// main thread) and accepted in Swift 5 mode, but an error under Swift 6.
@MainActor
struct escape_planApp: App {
    @State private var apiClient = APIClient()

    /// The signed-in account, or the absence of one. Built here rather than in a view so the
    /// Keychain is read once per launch instead of once per view rebuild.
    ///
    /// It takes the same base URL the APIClient starts with; Settings keeps the two in step
    /// when that changes. The auth layer is pure Foundation by design (it is symlinked into
    /// the EditorCore package so it can be tested without a simulator) and so cannot reach
    /// into Networking/ to read it for itself.
    @State private var authSession = AuthSession(
        client: AuthClient(baseURL: APIClient.currentBaseURL()),
        store: KeychainTokenStore())

    /// The bridge between the home documents on disk and the signed-in account's copies
    /// (S8.4). Built here, alongside the AuthSession it reads its token from, so there is
    /// exactly one of each per launch.
    @State private var syncRepository: HomeDocumentSyncRepository
    @State private var syncManager: SyncManager

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-TEST_SEED_DEMO_HOME") {
            if let store = try? HomeDocumentStore(), var model = try? FixtureLoader.load(.twostory) {
                model.home_id = "TEST-DEMO-HOME-1234"
                try? store.save(model: model)
            }
        }
#endif
        
        // Install the three starter homes before any screen reads the library.
        // At launch rather than inside onboarding on purpose: skipping the tour
        // ("I'll map my own home") must not leave the demo path with nothing to
        // demo. Guarded by a defaults flag, so it happens exactly once.
        do {
            try FixtureSeeder.seedStarterHomes(into: try HomeDocumentStore())
        } catch {
            // A missing bundled fixture must not stop the app from launching —
            // the library simply starts empty, exactly as it did before.
            print("Starter-home seeding skipped: \(error)")
        }

        // `try!` matches the existing convention for this call (`HomeScreen.init` and
        // `BetaScreen.init` both do it): `HomeDocumentStore()` fails only when the Documents
        // directory is unreachable, in which case the app has no persistence at all and the
        // Home tab would crash a moment later regardless. This adds no failure mode that was
        // not already there.
        let repository = HomeDocumentSyncRepository(store: try! HomeDocumentStore())
        _syncRepository = State(wrappedValue: repository)

        // The session object is already constructed — stored-property defaults run before an
        // initialiser body — so the token closure captures the same instance the views get.
        let session = _authSession.wrappedValue
        _syncManager = State(wrappedValue: SyncManager(
            client: CloudHomesClient(baseURL: APIClient.currentBaseURL()),
            repository: repository,
            // A sidecar beside the home documents, NOT a field on HomeModel: tracking a synced
            // revision inside the schema would be a `schema_version` bump, and sync progress is
            // a fact about this device rather than a property of the home.
            stateStore: (try? FileSyncStateStore()) ?? FileSyncStateStore(
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent(FileSyncStateStore.filename)),
            tokenProvider: { session.token },
            // A 401 means the JWT is dead. Signing out locally is what puts the user in front
            // of a sign-in form instead of watching sync fail silently every launch.
            onSessionExpired: { session.signOut() }))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(apiClient)
                .environment(authSession)
                .environment(syncManager)
                .environment(syncRepository)
        }
    }
}
