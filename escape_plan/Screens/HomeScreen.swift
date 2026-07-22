//  HomeScreen.swift
//  escape_plan
//
//  Real "saved homes" screen backed by S2.4's `HomeLibrary`/`HomeDocumentStore`, replacing the
//  S0.3 placeholder that only ever showed the bundled twostory.json fixture. Tapping a home (or
//  "New Home") opens the S2.1 editor on it; the editor autosaves back into the same store, so
//  this list is always what's actually on disk. A leading swipe (or the context menu) opens the
//  S3.5 preparedness score for that home.

import SwiftUI

struct HomeScreen: View {
    @StateObject private var library: HomeLibrary
    @State private var openHomeID: String?
    @State private var scoreHomeID: String?
    @State private var profilesHomeID: String?
    @State private var showingNewHome = false
    @State private var initError: String?

    init() {
        // `HomeDocumentStore()` only fails if the Documents directory itself can't be created,
        // which does not happen on a real device/simulator — fine to trap on.
        _library = StateObject(wrappedValue: HomeLibrary(store: try! HomeDocumentStore()))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Homes")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingNewHome = true
                        } label: {
                            Label("New Home", systemImage: "plus")
                        }
                    }
                }
                .navigationDestination(item: $openHomeID) { homeID in
                    EditorScreen(homeID: homeID) { library.refresh() }
                }
                .navigationDestination(isPresented: $showingNewHome) {
                    EditorScreen(homeID: nil) { library.refresh() }
                }
                .navigationDestination(item: $scoreHomeID) { homeID in
                    ScoreScreen(homeID: homeID)
                }
                .navigationDestination(item: $profilesHomeID) { homeID in
                    ProfilesScreen(homeID: homeID) { library.refresh() }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.homes.isEmpty {
            ContentUnavailableView {
                Label("No homes yet", systemImage: "house")
            } description: {
                Text("Tap + to build one in the 3D editor, or capture one with a LiDAR scan.")
            } actions: {
                Button("New Home") { showingNewHome = true }
            }
        } else {
            List {
                if let error = library.loadError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                ForEach(library.homes) { home in
                    Button {
                        openHomeID = home.id
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(home.name).font(.headline)
                            Text(subtitle(for: home))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { library.delete(homeID: home.id) }
                        Button("Duplicate") { library.duplicate(homeID: home.id) }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Score", systemImage: "checkmark.shield") { scoreHomeID = home.id }
                            .tint(.green)
                        Button {
                            profilesHomeID = home.id
                        } label: {
                            Label("Profiles", systemImage: "person.2")
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button("Preparedness Score", systemImage: "checkmark.shield") {
                            scoreHomeID = home.id
                        }
                        Button {
                            profilesHomeID = home.id
                        } label: {
                            Label("Profiles", systemImage: "person.2")
                        }
                    }
                }
            }
            .refreshable { library.refresh() }
        }
    }

    private func subtitle(for home: HomeSummary) -> String {
        let floors = "\(home.floorCount) floor\(home.floorCount == 1 ? "" : "s")"
        let rooms = "\(home.roomCount) room\(home.roomCount == 1 ? "" : "s")"
        let modified = home.modified.formatted(date: .abbreviated, time: .shortened)
        return "\(floors) · \(rooms) · \(modified)"
    }
}

#Preview {
    HomeScreen()
}
