//  LoginView.swift
//  escape_plan — S8.3 auth
//
//  Sign in to an existing account. Deliberately thin: every decision it appears to make —
//  validation, which error to show, whether a retry is possible, when the gate closes — is
//  AuthSession's, and is tested in escape_planTests/EditorCore/AuthSessionTests.swift. What
//  this file owns is layout and keyboard behaviour.

import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var session

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: AuthField?

    /// Offered so someone who tapped the wrong button is one tap from the right one.
    var switchToSignUp: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome back")
                    .font(Theme.screenTitle)
                    .foregroundStyle(DS.ink)

                Text("Sign in to reach the homes you've saved to your account.")
                    .font(.callout)
                    .foregroundStyle(DS.supporting)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 14) {
                    AuthCredentialFields(email: $email, password: $password,
                                         focus: $focus, isNewAccount: false,
                                         onSubmit: submit)

                    if let failure = session.failure {
                        AuthFailureNote(failure: failure)
                    }

                    AuthSubmitButton(title: "Sign in", isWorking: session.isWorking,
                                     action: submit)
                }
                .dsCard()

                if let switchToSignUp {
                    Button("New here? Create an account", action: switchToSignUp)
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
        // Clear a stale message the moment the user starts fixing the thing it complained
        // about — an error that outlives its cause reads as the app being stuck.
        .onChange(of: email) { session.failure = nil }
        .onChange(of: password) { session.failure = nil }
        // No dismissal here. When this is the root of AuthSheetView's NavigationStack, its
        // `dismiss` closes the SHEET rather than popping — so dismissing from both places
        // fires two dismissals for one state change. AuthSheetView owns closing the sheet;
        // from the gate, RootView swaps the whole view out. One owner each.
    }

    private func submit() {
        focus = nil
        Task { await session.signIn(email: email, password: password) }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    LoginView(switchToSignUp: {})
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
}
#endif
