// HomeScreen.swift
import SwiftUI

struct HomeScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var library: HomeLibrary
    
    // Checklist & Score state for the active home
    @State private var activeHomeID: String?
    @State private var activeHome: HomeModel?
    @State private var breakdown: ScoreBreakdown?
    @State private var checklistState: [String: Bool] = [:]
    
    @State private var isScoring = false
    @State private var scoreFailure: BackendFailure?
    @State private var refreshTask: Task<Void, Never>?
    
    // Sheet states
    @State private var showingNewHome = false
    @State private var showingBuildFromPlan = false
    @State private var showingScan = false
    @State private var openHomeID: String?
    @State private var scoreHomeID: String?
    @State private var drillHomeID: String?
    
    // Scan conversion
    @State private var isConverting = false
    @State private var scanFailure: BackendFailure?
    @State private var lastScanArtifacts: ScanArtifacts?

    private let stateStore = ChecklistStateStore()

    init() {
        _library = StateObject(wrappedValue: HomeLibrary(store: try! HomeDocumentStore()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scanFailureBanner
                
                if isConverting {
                    ProgressView("Converting scan…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if library.homes.isEmpty {
                    emptyState
                } else {
                    checklistView
                }
            }
            .navigationTitle(activeHome?.name ?? "Readiness")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section {
                            Button { showingScan = true } label: { Label("Scan New Home", systemImage: "camera.viewfinder") }
                                .accessibilityIdentifier("Scan New Home")
                            Button { showingNewHome = true } label: { Label("Build Manually", systemImage: "plus") }
                                .accessibilityIdentifier("Build Manually")
                            Button { showingBuildFromPlan = true } label: { Label("Import Plan", systemImage: "wand.and.stars") }
                                .accessibilityIdentifier("Import Plan")
                        }
                        Section("Homes") {
                            ForEach(library.homes) { home in
                                Button {
                                    switchActiveHome(to: home.id)
                                } label: {
                                    if activeHomeID == home.id {
                                        Label(home.name, systemImage: "checkmark")
                                    } else {
                                        Text(home.name)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Menu", systemImage: "ellipsis.circle")
                    }
                }
            }
            .task { 
                if activeHomeID == nil {
                    activeHomeID = library.homes.first?.id
                }
                await initialLoad() 
            }
            .onChange(of: activeHomeID) { _, _ in Task { await initialLoad() } }
            .sheet(isPresented: $showingBuildFromPlan) {
                BuildFromPlanView { homeID in
                    library.refresh()
                    switchActiveHome(to: homeID)
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
            .navigationDestination(item: $openHomeID) { homeID in
                HouseScreen(homeID: homeID, library: library) { 
                    library.refresh()
                    Task { await initialLoad() } // Reload checklist
                }
            }
            .navigationDestination(isPresented: $showingNewHome) {
                HouseScreen(homeID: nil, library: library) { 
                    library.refresh() 
                    activeHomeID = library.homes.first?.id
                }
            }
            .navigationDestination(item: $scoreHomeID) { homeID in
                ScoreScreen(homeID: homeID)
            }
            .navigationDestination(item: $drillHomeID) { homeID in
                DrillScreen(homeID: homeID)
            }
        }
    }
    
    private func switchActiveHome(to id: String) {
        activeHomeID = id
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Let's map your home", systemImage: "house")
        } description: {
            Text("Scan it with your iPhone's camera, or build it by hand in the 3D editor. Once it's here, you'll get a personalized readiness checklist.")
        } actions: {
            Button("Scan My Home") { showingScan = true }
                .buttonStyle(.borderedProminent)
            Button("Build It Myself") { showingNewHome = true }
        }
    }
    
    // MARK: - Checklist View
    
    @ViewBuilder
    private var checklistView: some View {
        List {
            // Header
            if let breakdown {
                Section {
                    Button {
                        scoreHomeID = activeHomeID
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Preparedness Score")
                                    .font(.headline)
                                Text("Tap for full breakdown")
                                    .font(.caption)
                                    .foregroundStyle(Theme.supporting)
                            }
                            Spacer()
                            ScoreRing(score: breakdown.score)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else if isScoring {
                Section {
                    HStack {
                        ProgressView()
                        Text("Scoring…").padding(.leading, 8)
                    }
                }
            } else if let fail = scoreFailure {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Score unavailable", systemImage: fail.symbol)
                            .foregroundStyle(Theme.warning)
                        Text(fail.message).font(.caption)
                        if fail.isRetryable {
                            Button("Retry") { refresh() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            
            // Checklist Sections
            if let breakdown {
                let items = breakdown.checklist
                let highSeverity = items.filter { $0.category == .agent_finding && ($0.id.contains("no_viable_route") || $0.id.contains("no_viable_safe_room")) }
                
                if !highSeverity.isEmpty {
                    Section {
                        ForEach(highSeverity) { item in
                            checklistRow(item, isHighSeverity: true)
                        }
                    } header: {
                        Text("CRITICAL").foregroundStyle(Theme.warning)
                    }
                }
                
                let regularItems = items.filter { !highSeverity.contains($0) }
                
                checklistSection(title: "Foundation", items: regularItems.filter { $0.category == .smoke_alarm })
                checklistSection(title: "Know your home", items: regularItems.filter { $0.category == .routes || $0.category == .agent_finding })
                checklistSection(title: "Practice", items: regularItems.filter { $0.category == .practice })
                checklistSection(title: "Mitigate", items: regularItems.filter { $0.category == .egress || $0.category == .recommendation })
                
                Section("Stay ready") {
                    if let home = activeHome, isStale(home) {
                        rescanNudge
                    }
                    ForEach(regularItems.filter { $0.category == .other }) { item in
                        checklistRow(item, isHighSeverity: false)
                    }
                }
            }
        }
        .refreshable { await initialLoad() }
    }
    
    @ViewBuilder
    private func checklistSection(title: String, items: [ChecklistItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    checklistRow(item, isHighSeverity: false)
                }
            }
        }
    }
    
    @ViewBuilder
    private func checklistRow(_ item: ChecklistItem, isHighSeverity: Bool) -> some View {
        let isDone = (checklistState[item.id] ?? item.done)
        
        Button {
            handleRowTap(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if item.scoring {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDone ? Theme.accent : Theme.supporting)
                        .font(.title3)
                } else {
                    Image(systemName: isDone ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isDone ? Theme.accent : Theme.supporting)
                        .font(.title3)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title)
                            .font(.subheadline)
                            .strikethrough(isDone)
                            .foregroundStyle(isDone ? Theme.supporting : .primary)
                            .fontWeight(isHighSeverity ? .bold : .regular)
                        
                        if let hazard = item.hazard {
                            hazardChip(hazard)
                        }
                    }
                    
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.supporting)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func hazardChip(_ hazard: HazardTag) -> some View {
        Text(hazard.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.supporting)
    }
    
    private var rescanNudge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Stale Floor Plan", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Text("It's been over 6 months since this home was scanned. Have you rearranged furniture or added a pet?")
                .font(.caption)
                .foregroundStyle(Theme.supporting)
            Button("Scan Now") { showingScan = true }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
    
    private func isStale(_ home: HomeModel) -> Bool {
        guard let scanned = home.meta.last_scanned else { return false }
        return Date().timeIntervalSince(scanned) > 180 * 24 * 3600
    }
    
    // MARK: - Row Handling
    
    private func handleRowTap(_ item: ChecklistItem) {
        // Spatial artifacts -> Editor tool / open house.
        // Practice -> Drill Screen.
        // Narrative items -> local toggle.
        
        let category = item.category
        if category == .smoke_alarm || category == .routes || category == .egress || category == .agent_finding || category == .recommendation {
            // Needs floor plan edit or route view
            openHomeID = activeHomeID
        } else if category == .practice {
            // Drill
            drillHomeID = activeHomeID
        } else {
            // Narrative only: toggle
            let newDone = !(checklistState[item.id] ?? item.done)
            checklistState[item.id] = newDone
            if let activeHomeID {
                stateStore.save(checklistState, homeID: activeHomeID)
            }
            if newDone { Haptics.tick() }
            refresh()
        }
    }
    
    // MARK: - Scoring
    
    private func initialLoad() async {
        guard let activeHomeID else { return }
        checklistState = stateStore.load(homeID: activeHomeID)
        isScoring = true
        defer { isScoring = false }
        do {
            activeHome = try HomeDocumentStore().load(homeID: activeHomeID, as: HomeModel.self)
        } catch {
            scoreFailure = BackendFailure(error, while: .score)
            return
        }
        await fetchScore()
    }
    
    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await fetchScore() }
    }
    
    private func fetchScore() async {
        guard let activeHome else { return }
        isScoring = true
        defer { isScoring = false }
        do {
            let new = try await apiClient.score(home: activeHome, checklistState: checklistState)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .linear(duration: 0) : .snappy) {
                breakdown = new
                scoreFailure = nil
            }
        } catch is CancellationError {
            // superseded
        } catch {
            scoreFailure = BackendFailure(error, while: .score)
        }
    }
    
    // MARK: - Scan Conversion (copied from original)
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
            switchActiveHome(to: summary.id)
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
            }
            .padding(.horizontal)
        }
    }
    
    private func retryScanImport() {
        guard let artifacts = lastScanArtifacts else { return }
        Task { await importScan(artifacts) }
    }
}

// MARK: - ScoreRing placeholder (just a static shape for the header)
struct ScoreRing: View {
    let score: Int
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(score)/100)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(.caption.bold())
        }
    }
}
