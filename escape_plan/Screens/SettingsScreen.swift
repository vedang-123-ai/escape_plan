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
                    Button {
                        Task { await checkHealth() }
                    } label: {
                        Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(health == .checking)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Escape Plan is already set up to use its own server — you only need "
                         + "to change these if the team gives you new values.")
                }

                Section {
                    TextField("Server address", text: $baseURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Access token", text: $bearerTokenText)
                    Button("Save changes") { save() }
                        .disabled(!hasEdits)
                } header: {
                    Text("Advanced")
                }

                #if DEBUG
                Section {
                    Button("Use deployed server") {
                        apiClient.baseURL = APIClient.deployedDefaultBaseURL
                        refreshFields()
                        health = .unknown
                    }
                    Button("Use local dev server (localhost:8000)") {
                        apiClient.baseURL = APIClient.localDevBaseURL
                        refreshFields()
                        health = .unknown
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Debug builds only. The local option expects "
                         + "`uvicorn app.main:app --port 8000` running on this Mac.")
                }
                #endif

                Section("About") {
                    LabeledContent("Escape Plan", value: "Congressional App Challenge 2026")
                    LabeledContent("Requires", value: "iOS 17 or later")
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
            Text("Not checked yet").foregroundStyle(.secondary)
        case .checking:
            ProgressView()
        case .reachable:
            Label("Connected", systemImage: "circle.fill")
                .foregroundStyle(Theme.accent)
                .labelStyle(DotLabelStyle())
        case .failed(let message):
            Label(message, systemImage: "circle.fill")
                .foregroundStyle(Theme.caution)
                .labelStyle(DotLabelStyle())
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

/// Small colored dot + text — a status light, not an icon.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 8))
            configuration.title.font(.subheadline)
        }
    }
}

#Preview {
    SettingsScreen()
        .environment(APIClient())
}
