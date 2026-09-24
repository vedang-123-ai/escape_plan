//  SettingsScreen.swift
//  escape_plan
//
//  Exposes the APIClient's configurable server address / access token and a connection check.
//  A fresh install already points at the deployed backend (S4.4; docs/decisions.md), so this
//  screen is for checking the connection and for the rare "the team gave me new values" case.
//  DEBUG builds add a developer section to flip between the deployed and local servers.
//
//  Laid out per the Claude Design (2026-09-07): grouped white cards with 60pt rows under
//  uppercase section labels, on the page gradient. Behaviour is unchanged.

import SwiftUI

struct SettingsScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(AuthSession.self) private var authSession
    @Environment(SyncManager.self) private var syncManager

    private enum HealthState: Equatable {
        case unknown
        case checking
        case reachable
        case failed(String)
    }

    @State private var baseURLText: String = ""
    @State private var bearerTokenText: String = ""
    @State private var health: HealthState = .unknown
    @State private var showSaved = false
    @State private var showingHowRoutes = false
    @State private var isPresentingAuth = false
    @State private var isConfirmingDeletion = false
    @State private var isDeletingAccount = false
    
    @AppStorage("snapshot_enabled") private var isSnapshotEnabled = false
    @State private var showingConsent = false
    // S11.6: consent is explicit, per share — a separate sheet from the one-time "enable
    // the feature" gate above, shown fresh every time a snapshot is about to go out.
    @State private var showingShareConsent = false
    @State private var isGeneratingSnapshot = false
    @State private var shareURLs: [URL]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DS.ink)
                        .padding(.horizontal, DS.pagePadding)
                        .padding(.top, 12)
                        .accessibilityAddTraits(.isHeader)

                    accountSection

                    section("Server") {
                        row("Status") { healthBadge }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Connection")
                            .accessibilityValue(healthSpoken)
                        divider
                        actionRow("Test connection") { Task { await checkHealth() } }
                            .disabled(health == .checking)
                            .accessibilityHint("Checks whether this iPhone can reach the Escape Plan server.")
                    }
                    footnote("Escape Plan is already set up to use its own server — you only need to change these if the team gives you new values.")

                    section("Advanced") {
                        row("Server address") {
                            TextField("api.example.com", text: $baseURLText)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(DS.supporting)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .accessibilityLabel("Server address")
                                .accessibilityHint("The web address of the Escape Plan server. Only change this if the team gave you a new one.")
                        }
                        divider
                        row("Access token") {
                            SecureField("Token", text: $bearerTokenText)
                                .font(.subheadline)
                                .foregroundStyle(DS.supporting)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel("Access token")
                                .accessibilityValue(bearerTokenText.isEmpty ? "Empty" : "Set, hidden")
                                .accessibilityHint("The shared password this app uses to talk to the server.")
                        }
                        divider
                        HStack {
                            actionRow("Save changes") { save() }
                                .disabled(!hasEdits)
                                .accessibilityHint(hasEdits ? "Stores the server address and access token."
                                                            : "Unavailable until you change something above.")
                            if showSaved {
                                Text("Saved")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.accentText)
                                    .padding(.trailing, 18)
                                    .transition(.opacity)
                            }
                        }
                    }

                    #if DEBUG
                    section("Developer") {
                        actionRow("Use deployed server") {
                            setBaseURL(APIClient.deployedDefaultBaseURL)
                            refreshFields()
                            health = .unknown
                        }
                        .accessibilityHint("Points the app back at the team's hosted server.")
                        divider
                        actionRow("Use local dev server (localhost:8000)") {
                            setBaseURL(APIClient.localDevBaseURL)
                            refreshFields()
                            health = .unknown
                        }
                        .accessibilityHint("Points the app at a server running on this Mac.")
                    }
                    footnote("Debug builds only. The local option expects `uvicorn app.main:app --port 8000` running on this Mac.")
                    #endif

                    section("Share with your fire department") {
                        let toggle = Toggle("Enable", isOn: Binding(
                            get: { isSnapshotEnabled },
                            set: { newValue in
                                if newValue {
                                    showingConsent = true
                                } else {
                                    isSnapshotEnabled = false
                                    ResponderSnapshotStore().clearSnapshots()
                                }
                            }
                        ))
                        .tint(Theme.accent)
                        .font(.body).foregroundStyle(DS.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 60)
                        
                        if isSnapshotEnabled {
                            VStack(spacing: 0) {
                                toggle
                                divider
                                Button {
                                    // Explicit, per share: re-confirm every time, even
                                    // though the feature itself was already enabled above.
                                    showingShareConsent = true
                                } label: {
                                    HStack {
                                        Text("Share with fire department")
                                            .font(.body)
                                            .foregroundStyle(Theme.accentText)
                                        Spacer()
                                        if isGeneratingSnapshot {
                                            ProgressView()
                                        }
                                    }
                                    .padding(.horizontal, 18)
                                    .frame(minHeight: 60)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(HapticPlainButtonStyle())
                                .disabled(isGeneratingSnapshot)
                            }
                        } else {
                            toggle
                        }
                    }
                    footnote("Generate a PDF and JSON package of floor plans, hazard findings and occupant counts by room — never names unless you opt in per share — to hand to first responders. Never transmitted automatically; every share asks first.")

                    section("About") {
                        row("Version") {
                            Text(versionString).font(.subheadline).foregroundStyle(DS.supporting)
                        }
                        divider
                        Button { showingHowRoutes = true } label: {
                            HStack {
                                Text("How routes are computed")
                                    .font(.body)
                                    .foregroundStyle(DS.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HapticPlainButtonStyle())
                        divider
                        row("Safety sources") {
                            Text("FEMA · NFPA · Red Cross").font(.subheadline).foregroundStyle(DS.supporting)
                        }
                    }
                    footnote("Escape routes are computed by a deterministic engine. The assistant explains them and never changes them.")
                }
                .padding(.bottom, 24)
            }
            .dsPage()
            .navigationTitle("Settings")
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: refreshFields)
            .sheet(isPresented: $isPresentingAuth) {
                AuthSheetView()
            }
            // An alert, not a sheet: deletion is irreversible and the confirmation must be
            // something the user cannot dismiss by swiping past it without reading.
            .alert("Delete your account?", isPresented: $isConfirmingDeletion) {
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(AccountPrivacy.deletionConfirmation)
            }
            .sheet(isPresented: $showingHowRoutes) { HowRoutesAreComputedSheet() }
            .sheet(isPresented: $showingConsent) {
                // isEnablingOnly: true — this accepts nothing being shared, only reveals the
                // "Share" action below. Its own CTA reads "Turn On", never "Share", so
                // accepting it is never mistaken for having shared something
                // (swift-scenekit-reviewer, S11.6).
                ConsentSheet(isEnablingOnly: true) { _ in
                    isSnapshotEnabled = true
                }
            }
            .sheet(isPresented: $showingShareConsent) {
                ConsentSheet { decision in
                    Task { await generateSnapshot(consent: decision) }
                }
            }
            .background(ShareSheet(urls: $shareURLs))
        }
    }

    private func generateSnapshot(consent: SnapshotConsentDecision) async {
        isGeneratingSnapshot = true
        defer { isGeneratingSnapshot = false }

        // Find the most recent home from the library
        guard let store = try? HomeDocumentStore() else { return }
        let summaries = store.list()
        guard let homeID = summaries.first?.id else { return }

        let exporter = EscapePlanExporter(store: store)
        guard let preview = try? exporter.preview(homeID: homeID) else { return }

        // Small delay to let the progress spinner show if rendering takes time
        try? await Task.sleep(for: .seconds(0.1))

        do {
            let urls = try exporter.writeResponderSnapshot(preview: preview, consent: consent)
            shareURLs = urls
        } catch {
            print("Failed to generate snapshot: \(error)")
        }
    }

    /// Delete the account server-side, then make this device forget it.
    ///
    /// The sync sidecar has to be cleaned up too, and only after the server confirms: it holds
    /// ownership claims naming the account's user id, and leaving them would mark this
    /// device's homes as belonging to an account that can never sign in again — so the next
    /// person to sign in on this phone could never back up a single home.
    ///
    /// The user id is read BEFORE the deletion, because the session is empty afterwards. It is
    /// the same id the sidecar stores: the backend mints the JWT with `sub = user.id` and
    /// `/auth/me` returns that same id, so `AuthenticatedUser.id` and `AccessToken.subject`
    /// are one value.
    ///
    /// No home document is touched, which is what `AccountPrivacy.deletionSummary` promises on
    /// the way in. `AuthSession` surfaces any failure; the row above renders it.
    private func deleteAccount() async {
        guard let userID = authSession.state.user?.id else { return }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        if await authSession.deleteAccount() {
            syncManager.forgetAccount(userID)
        }
    }

    // MARK: - Account (S8.3)

    /// Signing in from here, rather than only from the launch gate, is the whole reason the
    /// gate can be dismissed without consequence: someone who taps "Continue without an
    /// account" has to be able to change their mind, and this is where they look.
    @ViewBuilder
    private var accountSection: some View {
        if let user = authSession.state.user {
            section("Account") {
                // Signed in, but the token could not be written to the Keychain — the session
                // will not survive a relaunch. Shown HERE rather than on the sign-in form,
                // because the form dismisses itself the instant sign-in succeeds: the warning's
                // own success path would destroy its host in the same frame. Settings persists,
                // and is where someone goes when the app "forgot" them.
                if let warning = authSession.persistenceWarning {
                    AuthPersistenceNote(message: warning)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                }
                // A failed deletion leaves the user signed in and needs somewhere to say so.
                // The same slot serves any other account-level failure.
                if let failure = authSession.failure {
                    AuthFailureNote(failure: failure)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                }
                row("Signed in as") {
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(DS.supporting)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                divider
                actionRow("Sign out") { authSession.signOut() }
                    .accessibilityHint("Signs out on this iPhone. Your homes stay on this device.")
                divider
                deleteAccountRow
            }
            // True, and worth saying at the moment someone is deciding: nothing local is lost
            // by signing out, because the app keeps its own copy either way.
            footnote("Your homes are saved on this iPhone as well as your account. "
                   + "Signing out doesn't remove them from this device.")
            privacyDisclosureBlock
        } else {
            section("Account") {
                actionRow("Sign in or create an account") { isPresentingAuth = true }
                    .accessibilityHint("Back up your homes and open them on another device.")
            }
            footnote("An account backs up your homes and lets you open them on another device. "
                   + "Everything in Escape Plan works without one.")
            privacyDisclosureBlock
        }
    }

    /// The S11.7 disclosure, in both states. Signed out it answers "what would I be agreeing
    /// to?"; signed in it answers "what did I agree to?" — which is the question someone
    /// deciding whether to delete their account is actually asking.
    private var privacyDisclosureBlock: some View {
        AccountPrivacyDisclosure()
            .padding(.horizontal, DS.pagePadding + 16)
            .padding(.top, 12)
    }

    /// Apple requires an in-app way to delete an account wherever accounts exist.
    ///
    /// `Theme.warning` rather than the accent, because this is the one row on the screen that
    /// destroys something. Not `Theme.danger`-red-on-white as a filled button: it sits in a
    /// list of ordinary rows, and a filled destructive button in that position reads as the
    /// section's primary action.
    private var deleteAccountRow: some View {
        Button { isConfirmingDeletion = true } label: {
            HStack {
                Text("Delete account and data")
                    .font(.body)
                    .foregroundStyle(Theme.warning)
                Spacer()
                if isDeletingAccount { ProgressView() }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticPlainButtonStyle())
        .disabled(isDeletingAccount)
        .accessibilityHint("Permanently erases your account and the homes backed up to it. "
                         + "The homes on this iPhone are not deleted.")
    }

    // MARK: - Layout pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .sectionHeaderStyle()
                .padding(.horizontal, DS.pagePadding)
            VStack(spacing: 0) { content() }
                .dsCard(radius: 18, padding: nil)
                .padding(.horizontal, DS.pagePadding)
        }
        .padding(.top, 26)
    }

    private func row<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.body).foregroundStyle(DS.ink)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
    }

    private func actionRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).font(.body).foregroundStyle(Theme.accentText)
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(HapticPlainButtonStyle())
    }

    private var divider: some View {
        Divider().padding(.leading, 18)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(DS.supporting)
            .padding(.horizontal, DS.pagePadding + 16)
            .padding(.top, 12)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    @ViewBuilder
    private var healthBadge: some View {
        switch health {
        case .unknown:
            Text("Not checked yet").font(.subheadline).foregroundStyle(DS.supporting)
        case .checking:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Testing…").font(.subheadline).foregroundStyle(DS.supporting)
            }
        case .reachable:
            // SC 1.4.1: green vs amber was the only difference between these two states. The
            // glyphs now differ too, so the state survives being seen in greyscale.
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.accentText)
                .labelStyle(StatusLabelStyle())
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)
                .labelStyle(StatusLabelStyle())
        }
    }

    /// What VoiceOver says for the Connection row's value.
    private var healthSpoken: String {
        switch health {
        case .unknown: "Not checked yet"
        case .checking: "Checking"
        case .reachable: "Connected"
        case .failed(let message): message
        }
    }

    private var hasEdits: Bool {
        baseURLText != apiClient.baseURL.absoluteString || bearerTokenText != apiClient.bearerToken
    }

    /// The one place the server address changes.
    ///
    /// `AuthSession` holds its own copy because the auth layer is pure Foundation — symlinked
    /// into the EditorCore package so it can be tested without a simulator — and so cannot
    /// read APIClient's. Updating one and not the other would point sign-in at a different
    /// server than everything else, which is exactly the kind of split-brain bug that only
    /// shows up on the day someone switches to the local dev server.
    private func setBaseURL(_ url: URL) {
        apiClient.baseURL = url
        authSession.baseURL = url
        // The sync client holds its own copy for the same reason AuthClient does: Sync/ is
        // pure Foundation and cannot reach into Networking/ to read it. All three move together
        // or a changed server address silently applies to some requests and not others.
        syncManager.baseURL = url
    }

    private func refreshFields() {
        baseURLText = apiClient.baseURL.absoluteString
        bearerTokenText = apiClient.bearerToken
    }

    private func save() {
        if let url = URL(string: baseURLText.trimmingCharacters(in: .whitespaces)) {
            setBaseURL(url)
        }
        apiClient.bearerToken = bearerTokenText
        health = .unknown
        withAnimation { showSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation { showSaved = false }
        }
    }

    private func checkHealth() async {
        health = .checking
        do {
            let ok = try await apiClient.checkHealth()
            health = ok ? .reachable : .failed("Server gave an unexpected answer")
            if ok { Haptics.tick() }
        } catch {
            health = .failed("Can't reach the server right now")
        }
    }
}

/// Status glyph + text. `.footnote` so the glyph scales with Dynamic Type beside its label.
private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.footnote)
            configuration.title.font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The About row's destination: the division of labour, in plain words. This is the answer to
/// "isn't this just an AI wrapper?", so it lives one tap from Settings.
private struct HowRoutesAreComputedSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Two separate jobs")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(DS.ink)
                    Text("Your escape routes are computed by a deterministic routing engine from the model of your home: the same home always produces the same routes, and every step can be checked by hand. It picks the shortest safe way from each room to an exit for each person's needs.")
                    Text("The assistant is a separate layer. It explains those routes, audits the home for problems, and answers questions — always grounded in FEMA, NFPA and Red Cross guidance, with sources shown. It never computes a route and never invents safety advice.")
                    Text("The preparedness score comes from the engine's audit too. The assistant has no influence on it.")
                }
                .font(.body)
                .foregroundStyle(DS.bodyInk)
                .padding(DS.pagePadding)
            }
            .dsPage()
            .navigationTitle("How routes are computed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.hapticTap() } }
        }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    SettingsScreen()
        .environment(APIClient())
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
        .previewSyncEnvironment()
}
#endif
