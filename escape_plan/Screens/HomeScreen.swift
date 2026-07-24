//  HomeScreen.swift
//  escape_plan
//
//  Real "saved homes" screen backed by S2.4's `HomeLibrary`/`HomeDocumentStore`, replacing the
//  S0.3 placeholder that only ever showed the bundled twostory.json fixture. Tapping a home (or
//  "New Home") opens the S2.1 editor on it; the editor autosaves back into the same store, so
//  this list is always what's actually on disk. A leading swipe (or the context menu) opens the
//  S3.5 preparedness score for that home, or the S4.2 guided drill.
//
//  This screen owns the two entry points the flow owner was always meant to provide: the
//  RoomPlan LiDAR scan (S1.4/S1.5 — toolbar "Scan", and the empty state's promise) and drill
//  mode (S4.2). Both modules were complete but unreachable before this.

import SwiftUI

struct HomeScreen: View {
    @Environment(APIClient.self) private var apiClient

    @StateObject private var library: HomeLibrary
    @State private var openHomeID: String?
    @State private var scoreHomeID: String?
    @State private var profilesHomeID: String?
    @State private var drillHomeID: String?
    @State private var showingNewHome = false
    @State private var initError: String?

    // Scan → /convert → save → open editor.
    @State private var showingScan = false
    @State private var isConverting = false
    @State private var scanError: String?

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
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingScan = true
                        } label: {
                            Label("Scan", systemImage: "camera.viewfinder")
                        }
                    }
                }
                .fullScreenCover(isPresented: $showingScan) {
                    ScanFlowView(
                        onFinished: { artifacts in
                            showingScan = false
                            Task { await importScan(artifacts) }
                        },
                        onCancel: { showingScan = false }
                    )
                }
                .alert(
                    "Couldn't convert that scan",
                    isPresented: Binding(
                        get: { scanError != nil },
                        set: { if !$0 { scanError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { scanError = nil }
                } message: {
                    Text(scanError ?? "")
                }
                .navigationDestination(item: $openHomeID) { homeID in
                    HouseScreen(homeID: homeID, library: library) { library.refresh() }
                }
                .navigationDestination(isPresented: $showingNewHome) {
                    HouseScreen(homeID: nil, library: library) { library.refresh() }
                }
                .navigationDestination(item: $scoreHomeID) { homeID in
                    ScoreScreen(homeID: homeID)
                }
                .navigationDestination(item: $profilesHomeID) { homeID in
                    ProfilesScreen(homeID: homeID) { library.refresh() }
                }
                .navigationDestination(item: $drillHomeID) { homeID in
                    DrillScreen(homeID: homeID)
                }
        }
    }

    /// Uploads a finished scan to `/convert`, saves the resulting HomeModel, and opens it in
    /// the editor so low-confidence scan items get reviewed before anyone trusts a route.
    private func importScan(_ artifacts: ScanArtifacts) async {
        isConverting = true
        defer { isConverting = false }
        do {
            let name = "Scanned Home \(Date().formatted(date: .abbreviated, time: .shortened))"
            let model = try await apiClient.convertScan(at: artifacts.rawJSON, homeName: name)
            let summary = try library.store.save(model: model)
            library.refresh()
            openHomeID = summary.id
        } catch {
            scanError = scanFailureMessage(for: error)
        }
    }

    private func scanFailureMessage(for error: Error) -> String {
        guard case APIClientError.unexpectedResponse(let statusCode) = error else {
            return "\(error.localizedDescription) Check the backend URL in Settings."
        }
        switch statusCode {
        case 422:
            return "The scan couldn't be turned into a floor plan — it may be incomplete. "
                + "Try scanning again, walking the full perimeter of each room."
        case 401, 403:
            return "The backend rejected the request. Check the bearer token in Settings."
        default:
            return "The backend returned an error (\(statusCode)). Check the URL in Settings."
        }
    }

    @ViewBuilder
    private var content: some View {
        if isConverting {
            ProgressView("Converting scan…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.homes.isEmpty {
            ContentUnavailableView {
                Label("No homes yet", systemImage: "house")
            } description: {
                Text("Tap + to build one in the 3D editor, or capture one with a LiDAR scan.")
            } actions: {
                Button("New Home") { showingNewHome = true }
                Button("Scan a Home") { showingScan = true }
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
                        Button {
                            drillHomeID = home.id
                        } label: {
                            Label("Drill", systemImage: "figure.run")
                        }
                        .tint(.orange)
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
                        Button {
                            drillHomeID = home.id
                        } label: {
                            Label("Practice Drill", systemImage: "figure.run")
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
        .environment(APIClient())
}
