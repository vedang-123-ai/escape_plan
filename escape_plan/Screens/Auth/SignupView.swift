//  SignupView.swift
//  escape_plan — S8.3 auth
//
//  Create an account. Thin for the same reason LoginView is — AuthSession owns the behaviour,
//  including the fact that signing up is register-then-login because /auth/register answers
//  201 with a user and no token.

import SwiftUI

struct SignupView: View {
    @Environment(AuthSession.self) private var session

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: AuthField?

    var switchToSignIn: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create an account")
                    .font(Theme.screenTitle)
                    .foregroundStyle(DS.ink)

                Text("An account backs up your homes and lets you open them on another device. "
                   + "Everything in the app works without one.")
                    .font(.callout)
                    .foregroundStyle(DS.supporting)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    AuthCredentialFields(email: $email, password: $password,
                                         focus: $focus, isNewAccount: true,
                                         onSubmit: submit)

                    if let failure = session.failure {
                        AuthFailureNote(failure: failure)
                    }

                    AuthSubmitButton(title: "Create account", isWorking: session.isWorking,
                                     action: submit)
                }
                .dsCard()

                // The only length rule either side imposes. Said up front rather than as a
                // 422 after the round trip.
                Text("Passwords need at least \(AuthValidation.minimumPasswordLength) characters. "
                   + "There are no other requirements — length is what matters.")
                    .font(Theme.detail)
                    .foregroundStyle(DS.supporting)
                    .fixedSize(horizontal: false, vertical: true)

                if let switchToSignIn {
                    Button("Already have an account? Sign in", action: switchToSignIn)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .minimumTapTarget()
                }
            }
            .padding(DS.pagePadding)
        }
        .dsPage()
        .scrollDismissesKeyboard(.interactively)
        // NOT .onAppear: on a NavigationStack push the view is not in the responder chain
        // yet when onAppear fires, so setting @FocusState there is a silent no-op — it
        // type-checks and simply never raises the keyboard. One runloop beat is enough.
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focus = .email
        }
        .onChange(of: email) { session.failure = nil }
        .onChange(of: password) { session.failure = nil }
        // No dismissal here. When this is the root of AuthSheetView's NavigationStack, its
        // `dismiss` closes the SHEET rather than popping — so dismissing from both places
        // fires two dismissals for one state change. AuthSheetView owns closing the sheet;
        // from the gate, RootView swaps the whole view out. One owner each.
    }

    private func submit() {
        focus = nil
        Task { await session.register(email: email, password: password) }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    SignupView(switchToSignIn: {})
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
}
#endif
