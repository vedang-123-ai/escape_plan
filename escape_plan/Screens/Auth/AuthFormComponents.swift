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
        // One element, not two: while working the underlying button's label is empty, and
        // leaving it exposed gives VoiceOver an unlabelled control on the one thing the user
        // is waiting on. `children: .ignore` collapses it — but that also discards the
        // button's activation, so the action has to be put back explicitly or a VoiceOver
        // double-tap silently does nothing.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isWorking ? "\(title), in progress" : title)
        .accessibilityRespondsToUserInteraction(!isWorking)
        .accessibilityAction { if !isWorking { action() } }
    }
}

/// What signing in uploads, and what it never does — the S11.7 privacy disclosure.
///
/// Shown on the gate, in the sign-in sheet and in Settings, from ONE source: the copy lives in
/// `AccountPrivacy` (Foundation-only, so it is testable without a simulator) and is pinned by
/// test against a real encode of a `HomeModel`. A disclosure repeated in three hand-written
/// places is a disclosure that will be true in two of them after the next schema change.
///
/// Collapsed by default. Expanded, it is eight lines of text on a screen whose job is to let
/// someone decide about an account — but the summary above it is the fact that actually
/// decides most of it, and the detail has to be one tap away, not a link to a web page the
/// user has to leave the app to read.
struct AccountPrivacyDisclosure: View {

    /// Queried by `SignedOutPathUITests`. The two lists are `.combine`d for VoiceOver, which
    /// takes their visible strings out of the accessibility tree, so an identifier is the only
    /// handle a UI test has on them.
    static let uploadsIdentifier = "privacy.uploads"
    static let neverUploadsIdentifier = "privacy.neverUploads"

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AccountPrivacy.signedOutSummary)
                .font(.footnote)
                .foregroundStyle(DS.supporting)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Hide what an account uploads"
                                    : "What does an account upload?")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentText)
            }
            .buttonStyle(.plain)
            .minimumTapTarget(44)
            .accessibilityHint("Lists exactly what leaves this iPhone after you sign in.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    disclosureList("Signing in uploads",
                                   AccountPrivacy.uploaded.map(\.text),
                                   symbol: "arrow.up.circle",
                                   identifier: AccountPrivacyDisclosure.uploadsIdentifier)
                    disclosureList("It never uploads",
                                   AccountPrivacy.notUploaded,
                                   symbol: "xmark.circle",
                                   identifier: AccountPrivacyDisclosure.neverUploadsIdentifier)
                }
                .padding(12)
                .background(DS.inset, in: RoundedRectangle(cornerRadius: DS.buttonRadius,
                                                           style: .continuous))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func disclosureList(_ title: String,
                               _ lines: [String],
                               symbol: String,
                               identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.ink)
            ForEach(lines, id: \.self) { line in
                // A real bullet rather than a Label per line: eight icons down the side reads
                // as eight warnings, and none of these is a warning.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").font(.footnote).foregroundStyle(DS.supporting)
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(DS.bodyInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // `.combine` is right for VoiceOver — one announcement beats eight orphan bullets —
        // but it REMOVES the descendant Texts from the accessibility tree, so nothing can be
        // queried by its visible string. The identifier is what gives a UI test a handle on
        // the combined element. Found in review, 2026-09-24: `SignedOutPathUITests` asserted
        // on `staticTexts["Signing in uploads"]`, which could never have resolved.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("\(title): " + lines.joined(separator: ". "))
    }
}
