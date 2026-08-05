//  ContentView.swift
//  escape_plan
//
//  Tab shell: Home / Editor / Plan / Assistant / Settings, plus the S4.1 onboarding flow on
//  first launch — seed a demo home from the twostory fixture, review low-confidence items,
//  then land on routes + inspection. Finishing (or skipping) marks onboarding done; the flow
//  never reappears on its own after that.

import SwiftUI

struct ContentView: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var showingOnboarding = false

    var body: some View {
        TabView {
            HomeScreen()
                .tabItem { Label("Home", systemImage: "house") }
                .accessibilityLabel("Home")
                .accessibilityHint("Your saved homes.")

            HouseScreen()
                .tabItem { Label("House", systemImage: "cube.transparent") }
                .accessibilityLabel("House")
                .accessibilityHint("The 3D model of your home, with escape routes.")

            AssistantScreen()
                .tabItem { Label("Assistant", systemImage: "bubble.left.and.bubble.right") }
                .accessibilityLabel("Assistant")
                .accessibilityHint("Ask questions about your escape plan.")

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gear") }
                .accessibilityLabel("Settings")
                .accessibilityHint("Server connection and app information.")
        }
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

#Preview {
    ContentView()
        .environment(APIClient())
}
