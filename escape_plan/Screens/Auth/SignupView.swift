//  SignupView.swift
//  escape_plan — S8.3 auth
//
//  Create an account. Thin for the same reason LoginView is — AuthSession owns the behaviour,
//  including the fact that signing up is register-then-login because /auth/register answers
//  201 with a user and no token.

import SwiftUI

struct SignupView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: AuthField?

    var switchToSignIn: (() -> Void)?

    var body: some View {
        @Bindable var session = session

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
        .onAppear { focus = .email }
        .onChange(of: email) { session.failure = nil }
        .onChange(of: password) { session.failure = nil }
        .onChange(of: session.state) {
            if session.state.isSignedIn { dismiss() }
        }
    }

    private func submit() {
        focus = nil
        Task { await session.register(email: email, password: password) }
    }
}

#Preview {
    SignupView(switchToSignIn: {})
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore()))
}
