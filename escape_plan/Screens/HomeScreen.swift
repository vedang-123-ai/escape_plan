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
    /// Printable one-page-per-floor PDF (Export/). A sheet, not a destination — it ends in a
    /// share sheet rather than in another screen.
    @State private var exportTarget: ExportTarget?
    @State private var showingNewHome = false
    @State private var showingBuildFromPlan = false
    @State private var initError: String?

    // Scan → /convert → save → open editor.
    @State private var showingScan = false
    @State private var isConverting = false
    /// The classified failure, not a flattened sentence: a 502 and a 503 read identically as
    /// strings, and only the full value knows whether Retry can possibly help.
    @State private var scanFailure: BackendFailure?
    /// Kept so Retry re-converts the scan the user already walked, instead of an alert whose
    /// only button was OK and whose only outcome was losing the capture.
    @State private var lastScanArtifacts: ScanArtifacts?

    init() {
        // `HomeDocumentStore()` only fails if the Documents directory itself can't be created,
        // which does not happen on a real device/simulator — fine to trap on.
        _library = StateObject(wrappedValue: HomeLibrary(store: try! HomeDocumentStore()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                scanFailureBanner
                content
            }
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
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingBuildFromPlan = true
                        } label: {
                            Label("Import a plan", systemImage: "wand.and.stars")
                        }
                    }
                }
                .sheet(isPresented: $showingBuildFromPlan) {
                    BuildFromPlanView { homeID in
                        library.refresh()
                        openHomeID = homeID
                    }
                }
                .sheet(item: $exportTarget) { target in
                    ExportPlanSheet(homeID: target.id, store: library.store)
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
        lastScanArtifacts = artifacts
        defer { isConverting = false }
        do {
            let name = "Scanned Home \(Date().formatted(date: .abbreviated, time: .shortened))"
            let model = try await apiClient.convertScan(at: artifacts.rawJSON, homeName: name)
            let summary = try library.store.save(model: model)
            library.refresh()
            scanFailure = nil
            lastScanArtifacts = nil
            openHomeID = summary.id
        } catch {
            // The shared classifier, kept whole: a 422 (scan too incomplete) offers no Retry
            // and says how to rescan, a 503 offers one, a 502 says the routes you already have
            // are unaffected. The old alert collapsed all three into one OK button.
            scanFailure = BackendFailure(error, while: .scanConversion)
        }
    }

    /// The scan-conversion notice. An inline banner rather than an alert, because an alert
    /// forces a modal dismissal, offers no Retry, and threw away the capture on the way out.
    @ViewBuilder
    private var scanFailureBanner: some View {
        if let failure = scanFailure {
            VStack(alignment: .leading, spacing: 8) {
                BackendFailureBanner(
                    failure: failure,
                    retry: failure.isRetryable ? { retryScanImport() } : nil
                )
                if failure.isOfflineFlavoured {
                    OfflineCapabilityNote()
                }
                Button("Dismiss") { scanFailure = nil; lastScanArtifacts = nil }
                    .font(.caption)
                    .minimumTapTarget()
                    .accessibilityLabel("Dismiss")
                    .accessibilityHint("Hides this message and discards the scan you just took.")
            }
            .padding(.horizontal)
            .accessibilityIdentifier("home.scanFailure")
        }
    }

    private func retryScanImport() {
        guard let artifacts = lastScanArtifacts else { return }
        Task { await importScan(artifacts) }
    }

    @ViewBuilder
    private var content: some View {
        if isConverting {
            ProgressView("Converting scan…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Converting your scan into a floor plan.")
                .accessibilityAddTraits(.updatesFrequently)
        } else if library.homes.isEmpty {
            ContentUnavailableView {
                Label("Let's map your home", systemImage: "house")
            } description: {
                Text("Scan it with your iPhone's camera, or build it by hand in the 3D editor. "
                     + "Once it's here, you'll get escape routes for every room.")
            } actions: {
                Button("Scan My Home") { showingScan = true }
                    .buttonStyle(.borderedProminent)
                Button("Build It Myself") { showingNewHome = true }
            }
        } else {
            List {
                if let error = library.loadError {
                    Text(error).font(.caption).foregroundStyle(Theme.warning)
                }
                ForEach(library.homes) { home in
                    Button {
                        openHomeID = home.id
                    } label: {
                        HStack(spacing: 12) {
                            // A real render of the real model: shape is what makes a home
                            // recognisable, and two lines of text never showed it.
                            HomeThumbnailView(summary: home, store: library.store)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(home.name).font(.headline)
                                Text(subtitle(for: home))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { library.delete(homeID: home.id) }
                        Button("Duplicate") { library.duplicate(homeID: home.id) }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Score", systemImage: "checkmark.shield") { scoreHomeID = home.id }
                            .tint(Theme.accent)
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
                        .tint(Theme.caution)
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
                        Button {
                            exportTarget = ExportTarget(id: home.id)
                        } label: {
                            Label("Printable Plan", systemImage: "printer")
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
