//  SettingsScreen.swift
//  escape_plan
//
//  Exposes the APIClient's configurable base URL / bearer token and a /health check, so the
//  backend base URL can move from local dev to the deployed Render URL without a rebuild.

import SwiftUI

struct SettingsScreen: View {
    @Environment(APIClient.self) private var apiClient

    @State private var baseURLText: String = ""
    @State private var bearerTokenText: String = ""
    @State private var healthStatus: String = "Not checked"
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("Base URL", text: $baseURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Bearer token", text: $bearerTokenText)
                    Button("Save") { save() }
                }

                Section("Connectivity") {
                    LabeledContent("Status", value: healthStatus)
                    Button(isChecking ? "Checking…" : "Check /health") {
                        Task { await checkHealth() }
                    }
                    .disabled(isChecking)
                }

                Section("About") {
                    LabeledContent("App target", value: "iOS 17+")
                    LabeledContent("HomeModel schema", value: "v1.0")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                baseURLText = apiClient.baseURL.absoluteString
                bearerTokenText = apiClient.bearerToken
            }
        }
    }

    private func save() {
        if let url = URL(string: baseURLText) {
            apiClient.baseURL = url
        }
        apiClient.bearerToken = bearerTokenText
    }

    private func checkHealth() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let ok = try await apiClient.checkHealth()
            healthStatus = ok ? "Reachable ✓" : "Unexpected response"
        } catch {
            healthStatus = "Unreachable: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsScreen()
        .environment(APIClient())
}
