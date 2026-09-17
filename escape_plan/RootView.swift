//  RootView.swift
//  escape_plan — S8.3 auth
//
//  Decides between the auth gate and the app. A plain switch, not a second `fullScreenCover`:
//  `ContentView` already presents onboarding as one, and two covers competing at the root is a
//  reliable way to get neither.
//
//  Order matters. The gate comes first for a brand-new install, so the choice about an account
//  is made before the onboarding tour rather than interrupting it.

import SwiftUI

struct RootView: View {
    @Environment(AuthSession.self) private var session
    @Environment(SyncManager.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if session.shouldPresentGate {
                AuthGateView()
                    // Not a navigation transition — the gate is replaced by the app, and
                    // animating it as a push would imply a back button that does not exist.
                    .transition(.opacity)
            } else {
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.shouldPresentGate)
        .task {
            // No `restore()` here on purpose — AuthSession does it in its initialiser, so this
            // view's FIRST frame is already the right one. Restoring from `.task` would run
            // after that frame, and a signed-in user would watch the gate cross-fade away on
            // every launch.
            //
            // What is left is the server confirmation, which is also how the app finds out an
            // account was deleted. Failing is harmless: refresh() keeps the session on any
            // error short of an outright 401.
            await session.refresh()

            // Then sync, once the server has confirmed who is signed in — a sync fired before
            // `refresh()` would attach a token the server may have already rejected. Signed
            // out, this does nothing at all and never touches the network.
            await sync.syncIfSignedIn()
        }
        // Signing in (or registering) is the moment the account's homes become reachable, so
        // it is the moment to go and get them. `syncIfSignedIn` is a no-op on the way out, so
        // signing out does not fire a doomed request.
        .onChange(of: session.state) { _, _ in
            Task { await sync.syncIfSignedIn() }
        }
        // Coming back to the app is when another device's edits are most likely to be
        // waiting. Launch alone is not enough — iOS keeps an app suspended for days, so a
        // user who never fully quits would otherwise sync once and then never again.
        .onChange(of: scenePhase) { previous, phase in
            guard phase == .active, previous != .active else { return }
            Task { await sync.syncIfSignedIn() }
        }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    RootView()
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
        .environment(APIClient())
        .previewSyncEnvironment()
}
#endif
