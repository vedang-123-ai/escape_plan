//  ContentView.swift
//  escape_plan
//
//  Tab shell: Home / Editor / Plan / Assistant / Settings. Home/Editor/Plan are wired to real
//  content (S2.1 editor, S2.4 persistence, S1.3 renderer); Assistant stays a placeholder until
//  the AI backend has a live API key (S3.1-S3.3).

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
