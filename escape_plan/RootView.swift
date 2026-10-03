//  RootView.swift
//  escape_plan — S8.3 auth
//
//  The app's root. Until 2026-10-02 it chose between the account gate and the app; accounts
//  and cloud sync were then cut from the demo app (docs/decisions.md 2026-10-02, branch
//  `trim-1-demo-cuts`). `Auth/` and `Sync/` are kept, switched off: no gate, no sign-in, no
//  sync. Nothing here starts a sync any more.

import SwiftUI

struct RootView: View {
    /// Handed down from the app entry point, which creates the one store per launch.
    let homeStore: HomeDocumentStore
    var storageUnavailable = false

    @Environment(AuthSession.self) private var session

    var body: some View {
        ContentView(store: homeStore, storageUnavailable: storageUnavailable)
            .task {
                // A phone signed in by an earlier build would otherwise keep a login with no
                // screen left to see or end it. Signing out deletes the stored token, so it
                // happens once and never touches the network.
                if session.state.isSignedIn { session.signOut() }
            }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    RootView(homeStore: HomeDocumentStore.launchStore().store)
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
        .environment(APIClient())
        .previewSyncEnvironment()
}
#endif
