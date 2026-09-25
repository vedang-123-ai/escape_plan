//  ContentView.swift
//  escape_plan
//
//  Tab shell: Home / House / Assistant / Settings (the Linear revamp dropped the Beta tab —
//  its home library moves into House's switcher), plus the S4.1 onboarding flow on
//  first launch — seed a demo home from the twostory fixture, review low-confidence items,
//  then land on routes + inspection. Finishing (or skipping) marks onboarding done; the flow
//  never reappears on its own after that.

import SwiftUI

struct ContentView: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var showingOnboarding = false
    @State private var selectedTab: Tab = .home

    private enum Tab: Hashable { case home, house, assistant, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeScreen()
                .tabItem { Label("Home", systemImage: "house") }
                .accessibilityLabel("Home")
                .accessibilityHint("Your saved homes.")
                .tag(Tab.home)

            HouseScreen()
                .tabItem { Label("House", systemImage: "cube") }
                .accessibilityLabel("House")
                .accessibilityHint("The 3D model of your home, with escape routes.")
                .tag(Tab.house)

            AssistantScreen()
                .tabItem { Label("Assistant", systemImage: "sparkles") }
                .accessibilityLabel("Assistant")
                .accessibilityHint("Ask questions about your escape plan.")
                .tag(Tab.assistant)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .accessibilityLabel("Settings")
                .accessibilityHint("Server connection and app information.")
                .tag(Tab.settings)
        }
        // The tab bar is the one control SwiftUI renders without a click of its own.
        .onChange(of: selectedTab) { Haptics.selection() }
        .onAppear {
            if !onboardingCompleted { showingOnboarding = true }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingFlowView {
                onboardingCompleted = true
                showingOnboarding = false
            }
        }
    }
}

// Previews only — `InMemoryTokenStore` is DEBUG-only, and a preview must never
// touch the real Keychain or the standard UserDefaults.
#if DEBUG
#Preview {
    ContentView()
        .environment(APIClient())
        .environment(AuthSession(client: AuthClient(baseURL: APIClient.deployedDefaultBaseURL),
                                 store: InMemoryTokenStore(),
                                 defaults: UserDefaults(suiteName: "preview.\(UUID().uuidString)")!))
        .previewSyncEnvironment()
}
#endif
