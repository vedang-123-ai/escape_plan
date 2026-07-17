//  PlanScreen.swift
//  escape_plan
//
//  Placeholder — animated primary/secondary escape routes on the 3D dollhouse (S1.3+).

import SwiftUI

struct PlanScreen: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Escape Plan",
                systemImage: "figure.run",
                description: Text("Animated routes render here once the 3D renderer (S1.3) lands.")
            )
            .navigationTitle("Plan")
        }
    }
}

#Preview {
    PlanScreen()
}
