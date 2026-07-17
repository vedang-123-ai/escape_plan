//  AssistantScreen.swift
//  escape_plan
//
//  Placeholder — grounded chat + agentic home audit backed by the S3.1/S3.2/S3.3 backend
//  endpoints (/explain, /analyze, /chat). Routing itself is never computed here — the
//  deterministic backend engine owns that; this screen only ever talks to the backend.

import SwiftUI

struct AssistantScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Assistant",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Grounded chat + safety audit arrive in S3.3.")
            )
            .navigationTitle("Assistant")
        }
    }
}

#Preview {
    AssistantScreen()
}
