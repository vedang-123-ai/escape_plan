//  AuthFormComponents.swift
//  escape_plan — S8.3 auth
//
//  The pieces LoginView and SignupView are both made of. Shared rather than duplicated so the
//  two forms cannot drift into having different keyboard behaviour or different error
//  treatment — which is what happened to the six hand-rolled catch ladders that
//  BackendFailure was eventually written to replace.
//
//  No new colours: Theme.accent / Theme.warning and the DS chrome only. The route, exit and
//  hazard inks are reserved for legends that label a real route or exit (Theme.swift).

import SwiftUI

/// Which field the keyboard is on. Shared so both forms tab in the same order.
enum AuthField: Hashable { case email, password }

/// Email + password, wired for Password AutoFill.
///
/// The `textContentType` values are what let iOS offer a saved password on sign-in and a
/// generated one on sign-up; without them the user types a password by hand into an app that
/// is asking them to create an account, which is how people end up reusing one.
struct AuthCredentialFields: View {
    @Binding var email: String
    @Binding var password: String
    var focus: FocusState<AuthField?>.Binding
    /// Sign-up wants `.newPassword` so iOS offers to generate and save one; sign-in wants
    /// `.password` so it offers the existing one.
    var isNewAccount: Bool
    var onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused(focus, equals: .email)
                .onSubmit { focus.wrappedValue = .password }
                .accessibilityLabel("Email address")
                .fieldChrome()

            SecureField(isNewAccount ? "Password (at least 8 characters)" : "Password",
                        text: $password)
                .textContentType(isNewAccount ? .newPassword : .password)
                .submitLabel(.go)
                .focused(focus, equals: .password)
                .onSubmit(onSubmit)
                .accessibilityLabel("Password")
                .accessibilityHint(isNewAccount
                    ? "At least 8 characters. No other requirements."
                    : "The password for your account.")
                .fieldChrome()
        }
    }
}

private extension View {
    /// One inset field treatment, so the two forms cannot drift apart.
    func fieldChrome() -> some View {
        self
            .font(.body)
            .foregroundStyle(DS.ink)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(DS.inset, in: RoundedRectangle(cornerRadius: DS.buttonRadius,
                                                       style: .continuous))
    }
}

/// An `AuthFailure` as a line the user can act on. Mirrors `BackendFailureBanner`'s treatment
/// deliberately — one visual language for "something went wrong", not two.
struct AuthFailureNote: View {
    let failure: AuthFailure

    var body: some View {
        Label {
            Text(failure.message)
                .font(.footnote)
                .foregroundStyle(DS.bodyInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: failure.symbol)
                .foregroundStyle(Theme.warning)
        }
        .padding(12)
        .background(DS.inset, in: RoundedRectangle(cornerRadius: DS.buttonRadius,
                                                   style: .continuous))
        // One announcement rather than icon-then-text, and it interrupts, because the user is
        // waiting on the result of a button they just pressed.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(failure.message)
    }
}

/// Signed in, but the token could not be stored. Not a failure — the session simply will not
/// outlive this launch, and saying so beats the app appearing to forget the account.
struct AuthPersistenceNote: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(.footnote)
                .foregroundStyle(DS.bodyInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.caution)
        }
        .padding(12)
        .background(DS.inset, in: RoundedRectangle(cornerRadius: DS.buttonRadius,
                                                   style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The primary action, with the in-flight state folded in.
///
/// Disabled while working so a second tap cannot start a second request — `AuthSession` drops
/// those anyway, but a button that visibly does nothing is better than one that appears to.
struct AuthSubmitButton: View {
    let title: String
    let isWorking: Bool
    var action: () -> Void

    var body: some View {
        ZStack {
            DSPrimaryButton(title: isWorking ? "" : title, action: action)
                .disabled(isWorking)
            if isWorking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .allowsHitTesting(false)
            }
        }
        // One element, not two. Without this the underlying button is still its own
        // accessibility element with an EMPTY label while working — a VoiceOver dead end on
        // the one control the user is waiting on.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isWorking ? "\(title), in progress" : title)
        .accessibilityRespondsToUserInteraction(!isWorking)
    }
}
