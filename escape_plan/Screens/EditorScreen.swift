//  EditorScreen.swift
//  escape_plan
//
//  Placeholder — the SceneKit 3D dollhouse + wall/room editor lands in S1.3/Phase 2 (P2 lane).

import SwiftUI

struct EditorScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Editor",
                systemImage: "pencil.and.ruler",
                description: Text("3D dollhouse editor arrives in S1.3.")
            )
            .navigationTitle("Editor")
        }
    }
}

#Preview {
    EditorScreen()
}
