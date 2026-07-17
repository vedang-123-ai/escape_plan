//  ContentView.swift
//  escape_plan
//
//  Tab shell: Home / Editor / Plan / Assistant / Settings. Each non-Home tab is a placeholder
//  until its owning session lands (S1.3 renderer/editor, S3.3 chat assistant); wiring them up
//  now means later sessions fill in a screen body rather than restructuring navigation.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeScreen()
                .tabItem { Label("Home", systemImage: "house") }

            EditorScreen()
                .tabItem { Label("Editor", systemImage: "pencil.and.ruler") }

            PlanScreen()
                .tabItem { Label("Plan", systemImage: "figure.run") }

            AssistantScreen()
                .tabItem { Label("Assistant", systemImage: "bubble.left.and.bubble.right") }

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

#Preview {
    ContentView()
        .environment(APIClient())
}
