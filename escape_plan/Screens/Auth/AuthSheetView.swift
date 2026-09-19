//  AuthSheetView.swift
//  escape_plan — S8.3 auth
//
//  Signing in from Settings, for someone who chose "Continue without an account" and has since
//  changed their mind. That has to be possible, or the gate's escape hatch becomes a one-way
//  door and the soft gate is really a hard one with extra steps.
//
//  Distinct from `AuthGateView`: this is a sheet with a Cancel button and no "continue
//  without" option, because the user is already past that decision and inside the app.

import SwiftUI

struct AuthSheetView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private enum Destination: Hashable { case signUp }
    @State private var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            LoginView(switchToSignUp: { path = [.signUp] })
                .navigationDestination(for: Destination.self) { _ in
                    SignupView(switchToSignIn: { path = [] })
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        // LoginView and SignupView each dismiss themselves on success, which pops the stack;
        // this closes the sheet behind them.
        .onChange(of: session.state) {
            if session.state.isSignedIn { dismiss() }
        }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    AuthSheetView()
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
}
#endif
