//  escape_planApp.swift
//  escape_plan
//
//  S0.3: replaced the stock Core Data template wholesale. Persistence is local JSON documents
//  via FileManager (S2.4), not Core Data — this entry point just owns the shared APIClient.

import SwiftUI

@main
struct escape_planApp: App {
    @State private var apiClient = APIClient()

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
            ContentView()
                .environment(apiClient)
        }
    }
}
