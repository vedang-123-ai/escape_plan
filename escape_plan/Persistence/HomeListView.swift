//
//  HomeListView.swift
//  escape_plan — S2.4 persistence
//
//  Deliberately unstyled. P2 restyles this in the Phase-2 UI pass; it exists so
//  persistence is exercisable by hand (the manual test checklist in
//  docs/decisions.md drives this screen).
//

import SwiftUI

struct HomeListView: View {
    @StateObject var library: HomeLibrary
    @State private var export: ExportedFile?

    var body: some View {
        NavigationStack {
            List {
                if let error = library.loadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if library.homes.isEmpty {
                    Text("No saved homes yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(library.homes) { home in
                    // TODO(integration) — S2.1/S2.2: tapping a row opens the
                    // editor on `home.id`.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(home.name).font(.headline)
                        Text(subtitle(for: home))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            library.delete(homeID: home.id)
                        }
                        Button("Duplicate") { library.duplicate(homeID: home.id) }
                        Button("Export") {
                            if let url = library.export(homeID: home.id) {
                                export = ExportedFile(url: url)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Homes")
            .refreshable { library.refresh() }
            .sheet(item: $export) { file in
                ShareLink(item: file.url) {
                    Text("Share \(file.url.lastPathComponent)")
                }
                .padding()
            }
        }
    }

    private func subtitle(for home: HomeSummary) -> String {
        let floors = "\(home.floorCount) floor\(home.floorCount == 1 ? "" : "s")"
        let rooms = "\(home.roomCount) room\(home.roomCount == 1 ? "" : "s")"
        let modified = home.modified.formatted(date: .abbreviated, time: .shortened)
        return "\(floors) · \(rooms) · \(modified)"
    }
}

/// Identifiable box so the share sheet can be driven by `.sheet(item:)` without
/// a retroactive `Identifiable` conformance on `URL` (which would collide with
/// any other lane doing the same).
private struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
