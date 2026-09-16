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
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: AuthField?

    /// Offered so someone who tapped the wrong button is one tap from the right one.
    var switchToSignUp: (() -> Void)?

    var body: some View {
        @Bindable var session = session

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
        .onAppear { focus = .email }
        // Clear a stale message the moment the user starts fixing the thing it complained
        // about — an error that outlives its cause reads as the app being stuck.
        .onChange(of: email) { session.failure = nil }
        .onChange(of: password) { session.failure = nil }
        .onChange(of: session.state) {
            if session.state.isSignedIn { dismiss() }
        }
    }

    private func submit() {
        focus = nil
        Task { await session.signIn(email: email, password: password) }
    }
}

#Preview {
    LoginView(switchToSignUp: {})
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore()))
}
