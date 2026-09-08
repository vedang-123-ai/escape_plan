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
                            apiClient.baseURL = APIClient.deployedDefaultBaseURL
                            refreshFields()
                            health = .unknown
                        }
                        .accessibilityHint("Points the app back at the team's hosted server.")
                        divider
                        actionRow("Use local dev server (localhost:8000)") {
                            apiClient.baseURL = APIClient.localDevBaseURL
                            refreshFields()
                            health = .unknown
                        }
                        .accessibilityHint("Points the app at a server running on this Mac.")
                    }
                    footnote("Debug builds only. The local option expects `uvicorn app.main:app --port 8000` running on this Mac.")
                    #endif

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
            .sheet(isPresented: $showingHowRoutes) { HowRoutesAreComputedSheet() }
        }
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

    private func refreshFields() {
        baseURLText = apiClient.baseURL.absoluteString
        bearerTokenText = apiClient.bearerToken
    }

    private func save() {
        if let url = URL(string: baseURLText.trimmingCharacters(in: .whitespaces)) {
            apiClient.baseURL = url
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

#Preview {
    SettingsScreen()
        .environment(APIClient())
}
