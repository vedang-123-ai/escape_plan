//  escape_planApp.swift
//  escape_plan
//
//  S0.3: replaced the stock Core Data template wholesale. Persistence is local JSON documents
//  via FileManager (S2.4), not Core Data — this entry point owns the shared APIClient, and
//  since S8.3 the AuthSession too.

import SwiftUI

@main
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(apiClient)
                .environment(authSession)
        }
    }
}
