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
            // Scrollable since S11.7: expanded, the privacy disclosure is taller than an SE's
            // screen below three buttons, and a "Continue without an account" the user cannot
            // reach is the soft gate failing in the one way it must not.
            //
            // `minHeight: proxy.size.height` is what keeps the collapsed layout as it was — a
            // ScrollView proposes nil height, the flexible frame clamps that to the screen's,
            // and the `Spacer(minLength:)`s go back to distributing a full screen. NOTE that
            // nothing tests this; it is a layout claim and only a rendered SE-class screen can
            // confirm it. See BLOCKERS.
            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(DS.pagePadding)
                        .frame(maxWidth: .infinity,
                               minHeight: proxy.size.height,
                               alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
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

    /// Split out of `body` so the GeometryReader + ScrollView wrapper above stays readable as
    /// the three lines it actually is.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)

            DSIconBadge(systemImage: "house.and.flag", fill: Theme.accent, size: 52)
                .accessibilityHidden(true)
                .padding(.bottom, 20)

            // A question, not a promise. "Keep your plan safe" (the S8.3 wording) reads as
            // "without an account your plan is not safe", which is false — the plan lives on
            // this phone and works there with no server at all. S11.7's copy check: nothing on
            // this screen may imply the app needs an account.
            Text("Back up your homes?")
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

                // A peer of "I already have an account", not a footnote under it.
                //
                // S8.3 shipped this as a grey subheadline with no chrome, which is subordinate
                // by every visual measure even though the decision behind it (docs/decisions.md
                // 2026-09-15) called it first-class. S11.7's brief is explicit that the skip
                // must be VISUALLY EQUAL, so it is the same component at the same height and
                // weight as the sign-in button. The filled primary still marks the recommended
                // path; these two are peers, and ordering is what makes this the third option
                // rather than shrinking it.
                DSSecondaryButton(title: "Continue without an account") {
                    session.continueWithoutAccount()
                }
                .accessibilityHint("Use Escape Plan on this device only. "
                                 + "You can create an account later in Settings.")
            }

            // Below the buttons, not above them: the choice is the point of this screen, and
            // someone who does not want an account should not have to read a privacy
            // disclosure to find the way past. Someone who is weighing it up finds the answer
            // without leaving the app.
            AccountPrivacyDisclosure()
                .padding(.top, 20)

            Spacer(minLength: 12)
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
