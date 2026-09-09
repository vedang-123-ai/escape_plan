//  BetaScreen.swift
//  escape_plan
//
//  The pre-S6 "Homes" library, kept alive as a Beta tab. When the Home tab became the
//  readiness checklist (dac8673), the list of saved homes — the seeded fixtures plus anything
//  scanned or built — lost its front door. Testers still need it: it is the fastest way to
//  jump between the four fixture homes, duplicate one to experiment on, or reach a home's
//  score / profiles / drill / printable plan in one swipe.
//
//  This is the last list version of HomeScreen (3babbc0) with the title changed and nothing
//  removed. It sits leftmost in the tab bar so it never competes with the product tabs.

import SwiftUI

struct BetaScreen: View {
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

    // Scan → /convert → save → open editor.
    @State private var showingScan = false
    @State private var isConverting = false
    /// The classified failure, not a flattened sentence: a 502 and a 503 read identically as
    /// strings, and only the full value knows whether Retry can possibly help.
    @State private var scanFailure: BackendFailure?
    /// Kept so Retry re-converts the scan the user already walked, instead of losing it.
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
            .navigationTitle("Beta")
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
            scanFailure = BackendFailure(error, while: .scanConversion)
        }
    }

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
            .accessibilityIdentifier("beta.scanFailure")
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
                Label("No homes yet", systemImage: "house")
            } description: {
                Text("Scan one, import a plan, or build one by hand. Everything saved shows up here.")
            } actions: {
                Button("Scan My Home") { showingScan = true }
                    .buttonStyle(.borderedProminent).hapticTap()
                Button("Build It Myself") { showingNewHome = true }
                    .hapticTap()
            }
        } else {
            List {
                if let error = library.loadError {
                    Text(error).font(.caption).foregroundStyle(Theme.warning)
                }
                Section {
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
                                        .foregroundStyle(Theme.supporting)
                                }
                            }
                        }
                        .buttonStyle(HapticPlainButtonStyle())
                        // Swipe actions get the rigid swipe click; menu items the plain press —
                        // neither surface takes a ButtonStyle, so the calls sit in the actions.
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Haptics.warning()
                                library.delete(homeID: home.id)
                            }
                            Button("Duplicate") { Haptics.swipe(); library.duplicate(homeID: home.id) }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Score", systemImage: "checkmark.shield") {
                                Haptics.swipe(); scoreHomeID = home.id
                            }
                            .tint(Theme.accent)
                            Button {
                                Haptics.swipe(); profilesHomeID = home.id
                            } label: {
                                Label("Profiles", systemImage: "person.2")
                            }
                            .tint(.indigo)
                            Button {
                                Haptics.swipe(); drillHomeID = home.id
                            } label: {
                                Label("Drill", systemImage: "figure.run")
                            }
                            .tint(Theme.caution)
                        }
                        .contextMenu {
                            Button("Preparedness Score", systemImage: "checkmark.shield") {
                                Haptics.press(); scoreHomeID = home.id
                            }
                            Button {
                                Haptics.press(); profilesHomeID = home.id
                            } label: {
                                Label("Profiles", systemImage: "person.2")
                            }
                            Button {
                                Haptics.press(); drillHomeID = home.id
                            } label: {
                                Label("Practice Drill", systemImage: "figure.run")
                            }
                            Button {
                                Haptics.press(); exportTarget = ExportTarget(id: home.id)
                            } label: {
                                Label("Printable Plan", systemImage: "printer")
                            }
                        }
                    }
                } header: {
                    Text("Saved homes")
                } footer: {
                    Text("Test surface. Swipe a row for score, profiles and drill; long-press for the printable plan.")
                }
            }
            .refreshable { Haptics.begin(); library.refresh() }
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
    BetaScreen()
        .environment(APIClient())
}
