//  HomeScreen.swift
//  escape_plan
//
//  Placeholder "list of saved homes" screen. Persistence (S2.4) isn't built yet, so this
//  loads the twostory.json fixture as proof the Models/ decode layer works end to end, and
//  displays room names grouped per floor per the S0.3 acceptance criterion.

import SwiftUI

struct HomeScreen: View {
    @State private var home: HomeModel?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Homes")
        }
        .task { loadFixture() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView("Couldn't load fixture", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let home {
            List {
                Section {
                    LabeledContent("Name", value: home.name)
                    LabeledContent("Schema version", value: home.schema_version)
                    LabeledContent("Floors", value: "\(home.floors.count)")
                } header: {
                    Text("twostory.json (fixture)")
                }

                ForEach(home.floors.sorted(by: { $0.level < $1.level })) { floor in
                    Section("\(floor.name) — level \(floor.level)") {
                        ForEach(floor.rooms) { room in
                            Label(room.name, systemImage: symbol(for: room.type))
                        }
                    }
                }
            }
        } else {
            ProgressView("Loading fixture…")
        }
    }

    private func loadFixture() {
        do {
            home = try FixtureLoader.load(.twostory)
        } catch {
            loadError = "\(error)"
        }
    }

    private func symbol(for type: RoomType) -> String {
        switch type {
        case .bedroom: return "bed.double"
        case .living: return "sofa"
        case .kitchen: return "fork.knife"
        case .hall: return "arrow.left.arrow.right"
        case .bath: return "shower"
        case .garage: return "car"
        case .other: return "square"
        }
    }
}

#Preview {
    HomeScreen()
}
