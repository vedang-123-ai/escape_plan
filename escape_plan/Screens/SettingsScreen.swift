//  SettingsScreen.swift
//  escape_plan
//
//  Exposes the APIClient's configurable server address / access token and a connection check.
//  A fresh install already points at the deployed backend (S4.4; docs/decisions.md), so this
//  screen is for checking the connection and for the rare "the team gave me new values" case.
//  DEBUG builds add a developer section to flip between the deployed and local servers.

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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Connection") {
                        healthBadge
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Connection")
                    .accessibilityValue(healthSpoken)
                    Button {
                        Task { await checkHealth() }
                    } label: {
                        Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(health == .checking)
                    .accessibilityLabel("Test connection")
                    .accessibilityHint("Checks whether this iPhone can reach the Escape Plan "
                                       + "server.")
                } header: {
                    Text("Server").accessibilityAddTraits(.isHeader)
                } footer: {
                    Text("Escape Plan is already set up to use its own server — you only need "
                         + "to change these if the team gives you new values.")
                }

                Section {
                    TextField("Server address", text: $baseURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityLabel("Server address")
                        .accessibilityHint("The web address of the Escape Plan server. Only "
                                           + "change this if the team gave you a new one.")
                    SecureField("Access token", text: $bearerTokenText)
                        .accessibilityLabel("Access token")
                        .accessibilityValue(bearerTokenText.isEmpty ? "Empty" : "Set, hidden")
                        .accessibilityHint("The shared password this app uses to talk to the "
                                           + "server.")
                    Button("Save changes") { save() }
                        .disabled(!hasEdits)
                        .accessibilityHint(hasEdits
                                           ? "Stores the server address and access token."
                                           : "Unavailable until you change something above.")
                } header: {
                    Text("Advanced").accessibilityAddTraits(.isHeader)
                }

                #if DEBUG
                Section {
                    Button("Use deployed server") {
                        apiClient.baseURL = APIClient.deployedDefaultBaseURL
                        refreshFields()
                        health = .unknown
                    }
                    .accessibilityHint("Points the app back at the team's hosted server.")
                    Button("Use local dev server (localhost:8000)") {
                        apiClient.baseURL = APIClient.localDevBaseURL
                        refreshFields()
                        health = .unknown
                    }
                    .accessibilityHint("Points the app at a server running on this Mac.")
                } header: {
                    Text("Developer").accessibilityAddTraits(.isHeader)
                } footer: {
                    Text("Debug builds only. The local option expects "
                         + "`uvicorn app.main:app --port 8000` running on this Mac.")
                }
                #endif

                Section {
                    LabeledContent("Escape Plan", value: "Congressional App Challenge 2026")
                    LabeledContent("Requires", value: "iOS 17 or later")
                } header: {
                    Text("About").accessibilityAddTraits(.isHeader)
                }
            }
            .navigationTitle("Settings")
            .onAppear(perform: refreshFields)
        }
    }

    @ViewBuilder
    private var healthBadge: some View {
        switch health {
        case .unknown:
            Text("Not checked yet").foregroundStyle(Theme.supporting)
        case .checking:
            ProgressView()
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

/// Status glyph + text. The glyph was an 8pt dot at a fixed point size, which is both below
/// any reasonable legibility floor and completely deaf to Dynamic Type; it is now `.footnote`,
/// so it scales with the text beside it and stays proportionate at every size.
private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.footnote)
            configuration.title.font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SettingsScreen()
        .environment(APIClient())
}
