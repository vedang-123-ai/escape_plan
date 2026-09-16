//  AuthGateView.swift
//  escape_plan — S8.3 auth
//
//  The first thing a new install sees, and the S8.3 brief's "show the Auth flow if no token
//  exists" — with one deliberate difference.
//
//  It is NOT a wall. "Continue without an account" is a first-class button, not a buried link,
//  because this app is local-first: the editor, the routes, the drill and the export all work
//  with no server at all, and the CAC demo must not be one Render cold start away from being a
//  login screen. An account buys cloud backup and a second device — which is what S8.4 builds
//  — so that is what this screen offers, honestly, and nothing more.
//
//  Owner-approved 2026-09-15; see docs/decisions.md.

import SwiftUI

struct AuthGateView: View {
    @Environment(AuthSession.self) private var session

    private enum Destination: Hashable { case signIn, signUp }
    @State private var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 24)

                DSIconBadge(systemImage: "house.and.flag", fill: Theme.accent, size: 52)
                    .accessibilityHidden(true)
                    .padding(.bottom, 20)

                Text("Keep your plan safe")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(DS.ink)

                Text("An account backs up the homes you build and lets you open them on another "
                   + "device. Everything else in Escape Plan works without one.")
                    .font(.callout)
                    .foregroundStyle(DS.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                Spacer(minLength: 28)

                VStack(spacing: 12) {
                    DSPrimaryButton(title: "Create an account") { path.append(.signUp) }
                    DSSecondaryButton(title: "I already have an account") { path.append(.signIn) }

                    // A real button, weighted below the other two but not hidden. Someone who
                    // does not want an account must not have to hunt for the way past.
                    Button("Continue without an account") {
                        session.continueWithoutAccount()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.supporting)
                    .frame(maxWidth: .infinity)
                    .minimumTapTarget(44)
                    .padding(.top, 4)
                    .accessibilityHint("Use Escape Plan on this device only. "
                                     + "You can create an account later in Settings.")
                }

                Spacer(minLength: 12)
            }
            .padding(DS.pagePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .dsPage()
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .signIn:
                    LoginView(switchToSignUp: { path = [.signUp] })
                case .signUp:
                    SignupView(switchToSignIn: { path = [.signIn] })
                }
            }
        }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    AuthGateView()
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
}
#endif
