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
}
#endif
