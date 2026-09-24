// HomeScreen.swift
import SwiftUI

struct HomeScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(SyncManager.self) private var sync
    @Environment(HomeDocumentSyncRepository.self) private var syncRepository
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
    @State private var targetRecheckRoomID: String? = nil
    @State private var showingRoomPicker = false
    @State private var pendingDiffResult: DiffResult?
    @State private var pendingRecheckRoomID: String?

    @State private var openHomeID: String?
    @State private var scoreHomeID: String?
    @State private var drillHomeID: String?
    /// Quick-details sheet for one checklist row (the row itself is compact).
    @State private var detailItem: ChecklistItem?
    /// The checklist row a tap came from, handed to `HouseScreen` so it can resolve the row to
    /// an object against the loaded model and swing the camera to it (S7.7).
    @State private var focusItemID: String?
    /// Rows hide their detail line by default; this reveals every one inline.
    @AppStorage("home.checklist.showDetails") private var showAllDetails = false
    
    // Scan conversion
    @State private var isConverting = false
    @State private var scanFailure: BackendFailure?
    @State private var lastScanArtifacts: ScanArtifacts?

    // S11.5: Prevent section, family plan, scan freshness
    @State private var preventionTips: [PreventionTip] = []
    @State private var lastPracticed: Date?
    @State private var showingExportSheet = false

    private let stateStore = ChecklistStateStore()
    private let freshnessStore = ScanFreshnessStore()

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
            .navigationBarTitleDisplayMode(.inline)
            .dsPage()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        menuContent
                    } label: {
                        Label("Menu", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusBadge()
                }
            }
            .task { 
                // Sync writes pulled homes through this screen's library, and reads its
                // `editor` to know which home is open so it never overwrites one mid-edit.
                // Attached here because HomeScreen owns the library instance.
                syncRepository.library = library
                // The backend has no delete endpoint, so a deletion has to be remembered here
                // or the next sync downloads the home straight back.
                library.deletionObserver = syncRepository

                if activeHomeID == nil {
                    activeHomeID = library.homes.first?.id
                }
                loadPreventionTipsIfNeeded()
                await initialLoad()
            }
            .onChange(of: sync.status) { _, status in
                // A home that arrived from another device is on disk but not in this screen's
                // list until something re-reads the directory. `writePulledHome` refreshes the
                // library it holds; this covers the case where sync ran before the attach above.
                guard case .synced(_, let outcome) = status,
                      outcome.pulled > 0 || !outcome.conflicts.isEmpty else { return }
                library.refresh()
                if activeHomeID == nil {
                    activeHomeID = library.homes.first?.id
                    return  // .onChange(of: activeHomeID) will do the load
                }
                // The active home may be one of the ones that just changed on disk, and
                // `activeHomeID` has not — so nothing else reloads `activeHome`, the checklist
                // or the score, and the screen keeps rendering the pre-pull version until the
                // user switches homes or relaunches.
                Task { await initialLoad() }
            }
            .onChange(of: activeHomeID) { _, _ in Task { await initialLoad() } }
                        .confirmationDialog("Select a room to re-check", isPresented: $showingRoomPicker, titleVisibility: .visible) {
                if let activeHome {
                    ForEach(activeHome.floors.flatMap(\.rooms)) { room in
                        Button(room.name) {
                            targetRecheckRoomID = room.id
                            showingScan = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
                        .sheet(item: Binding<DiffResultWrapper?>(
                get: {
                    if let res = pendingDiffResult { return DiffResultWrapper(result: res) }
                    return nil
                },
                set: { if $0 == nil { pendingDiffResult = nil } }
            )) { wrapper in
                DiffReviewSheet(
                    result: wrapper.result,
                    onAdd: { obj in
                        guard var home = activeHome, let roomID = pendingRecheckRoomID else { return }
                        if let floorIdx = home.floors.firstIndex(where: { $0.rooms.contains(where: { $0.id == roomID }) }) {
                            home.floors[floorIdx].objects.append(obj)
                            // Use EditAction to mutate
                            let docStore = try? HomeDocumentStore()
                            try? docStore?.save(model: home)
                            activeHome = home
                            Task { await fetchScore() }
                        }
                    },
                    onDismiss: { pendingDiffResult = nil; pendingRecheckRoomID = nil }
                )
            }
            .sheet(isPresented: $showingBuildFromPlan) {
                BuildFromPlanView { homeID in
                    library.refresh()
                    switchActiveHome(to: homeID)
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                if let activeHomeID {
                    ExportPlanSheet(homeID: activeHomeID, store: library.store)
                }
            }
            .fullScreenCover(isPresented: $showingScan) {
                ScanFlowView(
                    recheckRoomID: targetRecheckRoomID,
                    onFinished: { artifacts in
                        showingScan = false
                        if let rid = targetRecheckRoomID {
                            Task { await processRecheck(artifacts: artifacts, roomID: rid) }
                        } else {
                            Task { await importScan(artifacts) }
                        }
                    },
                    onCancel: { showingScan = false }
                )
            }
            .navigationDestination(item: $openHomeID) { homeID in
                HouseScreen(homeID: homeID, library: library, initialFocusItemID: focusItemID) { 
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
    
    @ViewBuilder
    private var menuContent: some View {
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
            // Prevention and readiness first, matching the onboarding welcome copy — never a
            // claim that firefighters use this app (S11.5, CLAUDE.md).
            Text("Map it once. We'll show cited prevention basics, a readiness checklist, and an escape route for every person who lives here.")
        } actions: {
            Button("Scan My Home") { showingScan = true }
                .buttonStyle(.borderedProminent)
            Button("Build It Myself") { showingNewHome = true }
        }
    }
    
    // MARK: - Checklist View (Claude Design, 2026-09-07)

    /// Readiness label thresholds from the design's own logic (85 / 60).
    private func readinessLabel(_ score: Int) -> String {
        score >= 85 ? "Well prepared" : score >= 60 ? "Nearly ready" : "Getting started"
    }

    /// Next round-number milestone. The design stepped in 12s because its demo checks were
    /// worth 12 each; real components vary, so a clean 10 is the honest target.
    private func nextMilestone(_ score: Int) -> Int { min(100, (score / 10 + 1) * 10) }

    // S6.7 fix: this used to match `category == .agent_finding && id.contains(...)`, a
    // brittle string check that missed the no_viable_route/no_viable_safe_room items whose
    // ids don't contain those substrings, and missed every other severity=="high" finding
    // (household.sleep_near_exit, safe_room.nearby_shelter, etc). Filtering on `severity`
    // directly is what the backend's own high-severity cap uses (see
    // backend/app/scoring/score.py) — the checklist's CRITICAL section should show exactly
    // the items that can cap the score.
    private func highSeverity(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.filter { $0.severity == .high }
    }

    private func isDone(_ item: ChecklistItem) -> Bool { checklistState[item.id] ?? item.done }

    @ViewBuilder
    private var checklistView: some View {
        ScrollView {
            VStack(spacing: 0) {
                scoreHeader
                if let breakdown {
                    let items = breakdown.checklist
                    let critical = highSeverity(items)
                    if !critical.isEmpty {
                        criticalSection(critical)
                    }
                    readinessCard(score: breakdown.score)
                        .padding(.horizontal, DS.pagePadding)
                        .padding(.top, 18)
                    if let activeHome {
                        scanAgeCaption(activeHome)
                            .padding(.horizontal, DS.pagePadding)
                            .padding(.top, 6)
                    }
                    statTiles(items)
                        .padding(.horizontal, DS.pagePadding)
                        .padding(.top, 14)
                    detailedChecklist(items, critical: critical)
                }
                if let activeHome {
                    preventSection
                    familyPlanSection(activeHome)
                    homesSection
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { Haptics.begin(); await initialLoad() }
        .safeAreaInset(edge: .bottom) { drillCTA }
        .sheet(item: $detailItem) { item in
            ChecklistItemSheet(item: item,
                               isDone: isDone(item),
                               primary: primaryAction(for: item),
                               onPrimary: { performPrimaryAction(for: item) },
                               secondary: item.id == "rescan.home" ? ChecklistRowAction(title: "Re-check with the camera", icon: "camera.viewfinder", navigates: false) : nil,
                               onSecondary: item.id == "rescan.home" ? { detailItem = nil; showingRoomPicker = true } : nil)
        }
    }

    // The gauge, or the loading / failure state that stands in for it.
    @ViewBuilder
    private var scoreHeader: some View {
        if let breakdown {
            Button { scoreHomeID = activeHomeID } label: {
                DSScoreGauge(score: breakdown.score)
            }
            .buttonStyle(HapticPlainButtonStyle())
            .padding(.top, 10)
            .accessibilityLabel("Composite score \(breakdown.score) out of 100. Tap for the breakdown.")
        } else if isScoring {
            HStack(spacing: 10) {
                ProgressView()
                Text("Scoring…").foregroundStyle(DS.supporting)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .accessibilityLabel("Working out your preparedness score.")
        } else if let fail = scoreFailure {
            VStack(alignment: .leading, spacing: 6) {
                Label("Score unavailable", systemImage: fail.symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.warning)
                Text(fail.message).font(.callout).foregroundStyle(DS.bodyInk)
                if fail.isRetryable {
                    Button("Retry") { refresh() }
                        .buttonStyle(.bordered).hapticTap()
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .padding(.horizontal, DS.pagePadding)
            .padding(.top, 20)
        }
    }

    @ViewBuilder
    private func criticalSection(_ items: [ChecklistItem]) -> some View {
        Text("Critical")
            .font(.subheadline.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.pagePadding)
            .padding(.top, 28)
            .padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("CRITICAL_Header")
        VStack(spacing: 10) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 14) {
                    DSIconBadge(systemImage: "exclamationmark.triangle",
                                fill: DS.criticalFill, glyph: Theme.warning, size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.body.weight(.semibold)).foregroundStyle(DS.ink)
                        if let hazard = item.hazard {
                            Text(hazardLabel(hazard)).font(.subheadline).foregroundStyle(DS.supporting)
                        }
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(DS.bodyInk)
                            .padding(.top, 2)
                        HStack(spacing: 10) {
                            Button { handleRowTap(item) } label: {
                                Text("Show me where")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(DSPressStyle())
                            Button { scoreHomeID = activeHomeID } label: {
                                Text("Why it matters")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accentText)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(DS.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(DSPressStyle())
                        }
                        .padding(.top, 12)
                    }
                }
                .dsCard(radius: 18, padding: 18)
            }
        }
        .padding(.horizontal, DS.pagePadding)
    }

    private func readinessCard(score: Int) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
                    .foregroundStyle(Theme.accent.opacity(0.45))
                Image(systemName: "house")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(readinessLabel(score))
                    .font(.headline.weight(.bold))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(Theme.accentText)
                HStack {
                    Text("\(score) points")
                    Spacer()
                    Text("Next milestone: \(nextMilestone(score))")
                }
                .font(.subheadline)
                .foregroundStyle(DS.supporting)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.track)
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.545, green: 0.878, blue: 0.675), Theme.accent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(score) / 100)
                    }
                }
                .frame(height: 12)
                .accessibilityHidden(true)
            }
        }
        .dsCard(radius: DS.cardRadiusLarge, padding: 18)
        .accessibilityElement(children: .combine)
    }

    /// "Scanned 12 days ago." — the firefighter's "remodels make stored layouts stale"
    /// warning, made visible everywhere a home is shown, not just when it's stale enough to
    /// nudge (ScanFreshness.scanAgeText, S11.5).
    private func scanAgeCaption(_ home: HomeModel) -> some View {
        Label(ScanFreshness.scanAgeText(lastScanned: home.meta.last_scanned, modified: home.meta.modified),
              systemImage: "clock")
            .font(.caption)
            .foregroundStyle(DS.supporting)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Tile {
        let key: String
        let value: String
        let unit: String
        let sub: String
        let icon: String
        let fill: Color
        let done: Bool
        let action: () -> Void
    }

    /// Four summary tiles from the checklist. Colours stay inside the app's rule — the routes
    /// tile is the one legitimate chrome use of `routeInk` (it labels routes), alarms take the
    /// caution amber, findings a neutral slate, drills the accent — rather than the design's
    /// blue/purple, which would put two new hues on chrome.
    private func tiles(from items: [ChecklistItem]) -> [Tile] {
        func group(_ cats: [ChecklistCategory]) -> [ChecklistItem] { items.filter { cats.contains($0.category) } }
        let alarms = group([.smoke_alarm]), routes = group([.routes])
        let findings = group([.agent_finding]), drills = group([.practice])
        let alarmsDone = alarms.filter(isDone).count
        let findingsOpen = findings.filter { !isDone($0) }.count
        let drillsDone = drills.filter(isDone).count
        return [
            Tile(key: "alarms", value: "\(alarmsDone)", unit: "of \(alarms.count)", sub: "alarm checks done",
                 icon: "bell.fill", fill: Theme.caution,
                 done: !alarms.isEmpty && alarmsDone == alarms.count,
                 action: { openHomeID = activeHomeID }),
            Tile(key: "routes", value: "\(routes.filter(isDone).count)", unit: "of \(routes.count)", sub: "route checks done",
                 icon: "arrow.triangle.turn.up.right.diamond.fill", fill: Theme.routeInk,
                 done: !routes.isEmpty && routes.allSatisfy(isDone),
                 action: { openHomeID = activeHomeID }),
            Tile(key: "findings", value: "\(findingsOpen)", unit: "to review", sub: "route findings",
                 icon: "exclamationmark.triangle.fill", fill: DS.bodyInk,
                 done: findingsOpen == 0,
                 action: { openHomeID = activeHomeID }),
            Tile(key: "drills", value: "\(drillsDone)", unit: drillsDone == 1 ? "drill" : "drills", sub: "practised",
                 icon: "play.fill", fill: Theme.accent,
                 done: drillsDone > 0,
                 action: { drillHomeID = activeHomeID }),
        ]
    }

    private func statTiles(_ items: [ChecklistItem]) -> some View {
        let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return LazyVGrid(columns: cols, spacing: 14) {
            ForEach(tiles(from: items), id: \.key) { tile in
                Button(action: tile.action) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            DSIconBadge(systemImage: tile.icon, fill: tile.fill, size: 52)
                            Spacer()
                            Text(tile.done ? "Done" : "To do")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(tile.done ? Theme.accentText : Theme.caution)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(tile.done ? DS.accentFill : DS.cautionFill, in: Capsule())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(tile.value)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.ink)
                                Text(tile.unit)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.supporting)
                            }
                            Text(tile.sub).font(.subheadline).foregroundStyle(DS.supporting)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                    .dsCard(radius: DS.cardRadiusLarge, padding: 18)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel("\(tile.value) \(tile.unit) \(tile.sub). \(tile.done ? "Done" : "To do").")
            }
        }
    }

    /// The per-item checklist, grouped as the S6 brief specifies. Critical items already have
    /// their own card above, so they are not repeated here.
    @ViewBuilder
    private func detailedChecklist(_ items: [ChecklistItem], critical: [ChecklistItem]) -> some View {
        let regular = items.filter { !critical.contains($0) }
        VStack(alignment: .leading, spacing: 0) {
            checklistHeader(remaining: regular.filter { !isDone($0) }.count, total: regular.count)
            checklistGroup("Foundation", regular.filter { $0.category == .smoke_alarm })
            // S6.6 categories routed in (2026-09-07): safe_room joins the routes/agent_finding
            // "know your home" group; shutoffs/mitigation join "Mitigate"; supply_kit/alerts
            // join "Stay ready" below. Before this fix these 5 categories matched none of the
            // filters and silently vanished from the checklist.
            checklistGroup("Know your home", regular.filter {
                $0.category == .routes || $0.category == .agent_finding || $0.category == .safe_room
            })
            checklistGroup("Practice", regular.filter { $0.category == .practice })
            checklistGroup("Mitigate", regular.filter {
                $0.category == .egress || $0.category == .recommendation
                    || $0.category == .shutoffs || $0.category == .mitigation
            })
            let other = regular.filter {
                $0.category == .other || $0.category == .supply_kit || $0.category == .alerts
            }
            if let home = activeHome, let reason = nudgeReason(for: home) {
                sectionLabel("Stay ready")
                rescanNudge(reason).dsCard()
                    .padding(.horizontal, DS.pagePadding)
                    .padding(.bottom, other.isEmpty ? 0 : 10)
                if !other.isEmpty { checklistCard(other) }
            } else {
                checklistGroup("Stay ready", other)
            }
        }
    }

    /// Sits above the first group: how much is left, and the one switch that expands every
    /// row's detail line. Rows stay compact unless the reader asks.
    private func checklistHeader(remaining: Int, total: Int) -> some View {
        HStack {
            Text(remaining == 0 ? "All \(total) done" : "\(remaining) of \(total) to do")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DS.supporting)
            Spacer()
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { showAllDetails.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showAllDetails ? "Hide details" : "Show details")
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(showAllDetails ? 180 : 0))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(DS.card, in: Capsule())
                .shadow(color: DS.shadowColor, radius: 9, y: 6)
            }
            .buttonStyle(DSPressStyle())
            .accessibilityHint(showAllDetails ? "Hides every item's detail line."
                                              : "Shows every item's detail line under its title.")
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 30)
        .padding(.bottom, 2)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .sectionHeaderStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.pagePadding)
            .padding(.top, 26)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private func checklistGroup(_ title: String, _ items: [ChecklistItem]) -> some View {
        if !items.isEmpty {
            sectionLabel(title)
            checklistCard(items)
        }
    }

    private func checklistCard(_ items: [ChecklistItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 52) }
                checklistRow(item, isHighSeverity: false)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
            }
        }
        .dsCard(padding: nil)
        .padding(.horizontal, DS.pagePadding)
    }

    @ViewBuilder
    /// Compact by default — title, hazard, a chevron — so the list scans as a list. The detail
    /// line appears under "Show details" or in the quick-details sheet a tap opens. Narrative
    /// items keep a one-tap checkbox on the left; engine-scored items show their state only.
    private func checklistRow(_ item: ChecklistItem, isHighSeverity: Bool) -> some View {
        let done = isDone(item)
        HStack(alignment: .top, spacing: 12) {
            checkbox(for: item, done: done)
            Button {
                detailItem = item
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title)
                                .font(.subheadline.weight(isHighSeverity ? .bold : .medium))
                                .strikethrough(done)
                                .foregroundStyle(done ? DS.supporting : DS.ink)
                                .multilineTextAlignment(.leading)
                            if let hazard = item.hazard { hazardChip(hazard) }
                        }
                        if showAllDetails {
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(DS.supporting)
                                .multilineTextAlignment(.leading)
                                .transition(.opacity)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HapticPlainButtonStyle())
            .accessibilityLabel(item.title)
            .accessibilityValue(done ? "Done" : "To do")
            .accessibilityHint("Opens the details for this item.")
        }
    }

    /// Narrative items toggle right here; everything else is decided by the engine, so its
    /// mark is a read-only glyph (the sheet says what to do about it).
    @ViewBuilder
    private func checkbox(for item: ChecklistItem, done: Bool) -> some View {
        let glyph = Image(systemName: item.scoring
                          ? (done ? "checkmark.circle.fill" : "circle")
                          : (done ? "checkmark.square.fill" : "square"))
            .foregroundStyle(done ? Theme.accent : DS.supporting)
            .font(.title3)
            .frame(width: 28, height: 28)
        if primaryAction(for: item).navigates {
            glyph.accessibilityHidden(true)
        } else {
            Button { toggleDone(item) } label: {
                glyph.contentShape(Rectangle())
            }
            .buttonStyle(HapticPlainButtonStyle())
            .accessibilityLabel(done ? "Mark as not done" : "Mark as done")
        }
    }

    private func hazardLabel(_ hazard: HazardTag) -> String {
        hazard.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    @ViewBuilder
    private func hazardChip(_ hazard: HazardTag) -> some View {
        Text(hazardLabel(hazard))
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DS.inset, in: Capsule())
            .foregroundStyle(DS.supporting)
    }

    /// `reason` distinguishes "it's just been a while" from "a wall actually changed" — the
    /// wording (ScanFreshness.nudgeMessage) always says the plan is resident-maintained, not
    /// verified, whichever reason fired.
    private func rescanNudge(_ reason: ScanFreshness.NudgeReason) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(reason == .wallsEdited ? "Layout changed since the last scan" : "Stale floor plan",
                  systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .foregroundStyle(DS.ink)
            Text(ScanFreshness.nudgeMessage(reason))
                .font(.subheadline)
                .foregroundStyle(DS.bodyInk)
            Button("Scan now") { showingScan = true }
                .buttonStyle(.bordered).hapticTap()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pinned above the tab bar, as on the design: the one action the screen is nudging toward.
    @ViewBuilder
    private var drillCTA: some View {
        if breakdown != nil {
            Button { drillHomeID = activeHomeID } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(.white, in: Circle())
                    Text("Run a fire drill").font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Color(red: 27/255, green: 35/255, blue: 64/255).opacity(0.16), radius: 13, y: 10)
            }
            .buttonStyle(DSPressStyle())
            .padding(.horizontal, DS.pagePadding)
            .padding(.bottom, 8)
        }
    }

    /// Whichever of the two S11.5 triggers applies to this home right now — a wall added or
    /// removed since the last scan, or the age threshold passed — or nil if the plan is fresh.
    /// Pure decision lives in ScanFreshness; this just supplies the model's own state.
    private func nudgeReason(for home: HomeModel) -> ScanFreshness.NudgeReason? {
        let days = ScanFreshness.daysSince(lastScanned: home.meta.last_scanned, modified: home.meta.modified)
        let changed = ScanFreshness.wallsChanged(
            currentEdgeCount: ScanFreshness.wallEdgeCount(home),
            recordedEdgeCount: freshnessStore.recordedWallEdgeCount(homeID: home.id))
        return ScanFreshness.nudgeReason(daysSinceScan: days, wallsChanged: changed)
    }

    // MARK: - Row Handling
    
    private func handleRowTap(_ item: ChecklistItem) {
        // Spatial artifacts -> Editor tool / open house.
        // Practice -> Drill Screen.
        // Narrative items -> local toggle.
        
        let category = item.category
        
        switch category {
        case .smoke_alarm, .routes, .egress, .agent_finding, .recommendation, .mitigation, .other, .safe_room, .shutoffs:
            focusItemID = item.id
            // Needs floor plan edit or route view
            openHomeID = activeHomeID
        case .practice:
            // Drill
            drillHomeID = activeHomeID
        default:
            // Narrative only: toggle
            toggleDone(item)
        }
    }

    /// Flips a narrative item and re-scores. Done gets the firmer tick, undone a quiet notch.
    private func toggleDone(_ item: ChecklistItem) {
        let newDone = !(checklistState[item.id] ?? item.done)
        withAnimation(reduceMotion ? nil : .snappy) { checklistState[item.id] = newDone }
        if let activeHomeID {
            stateStore.save(checklistState, homeID: activeHomeID)
        }
        if newDone { Haptics.tick() } else { Haptics.selection() }
        refresh()
    }

    /// What the quick-details sheet's main button does for a row — the same routing as a row
    /// tap used to do directly: spatial items go to the house, practice to the drill, and
    /// narrative items toggle in place.
    private func primaryAction(for item: ChecklistItem) -> ChecklistRowAction {
        switch item.category {
        case .practice:
            return ChecklistRowAction(title: "Run a drill", icon: "play.fill", navigates: true)
        case .smoke_alarm, .routes, .egress, .agent_finding, .recommendation:
            return ChecklistRowAction(title: "Show me where", icon: "cube", navigates: true)
        default:
            let done = isDone(item)
            return ChecklistRowAction(title: done ? "Mark as not done" : "Mark as done",
                                      icon: done ? "arrow.uturn.backward" : "checkmark",
                                      navigates: false)
        }
    }

    private func performPrimaryAction(for item: ChecklistItem) {
        if primaryAction(for: item).navigates {
            detailItem = nil
            // Let the sheet finish dismissing before the push, or the stack drops it.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                handleRowTap(item)
            }
        } else {
            toggleDone(item)
        }
    }
    
    // MARK: - Prevent

    /// Loads the bundled corpus copy once per screen lifetime. A missing or corrupt resource
    /// just leaves `preventionTips` empty — `preventSection` renders nothing rather than
    /// crashing or showing a failure banner over what is, at worst, a missing nice-to-have.
    private func loadPreventionTipsIfNeeded() {
        guard preventionTips.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "prevention_tips", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tips = try? PreventionTips.decode(from: data) else { return }
        preventionTips = tips
    }

    // MARK: - Scoring

    private func initialLoad() async {
        guard let activeHomeID else { return }
        checklistState = stateStore.load(homeID: activeHomeID)
        isScoring = true
        defer { isScoring = false }
        do {
            let home = try HomeDocumentStore().load(homeID: activeHomeID, as: HomeModel.self)
            activeHome = home
            // A home scanned before this feature shipped (or seeded by FixtureSeeder) has no
            // recorded baseline. Seed it to the CURRENT count rather than leaving it nil —
            // nil already reads as "no change" (ScanFreshness.wallsChanged), so this is only
            // to make the very next real edit detectable, not a correction of anything now.
            if home.meta.last_scanned != nil,
               freshnessStore.recordedWallEdgeCount(homeID: activeHomeID) == nil {
                freshnessStore.recordWallEdgeCount(ScanFreshness.wallEdgeCount(home), homeID: activeHomeID)
            }
            lastPracticed = (try? DrillLogStore())?.lastPracticed(homeID: activeHomeID)
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
        guard var activeHome = activeHome else { return }
        isScoring = true
        defer { isScoring = false }
        do {
            let new = try await apiClient.score(home: activeHome, checklistState: checklistState)
            guard !Task.isCancelled else { return }
            // Not wrapped in withAnimation on purpose: animating a wholesale swap of the
            // checklist content is the one thing that can make the ScrollView drop its offset
            // mid-list. The gauge sweeps on its own; the rows just update in place.
            breakdown = new
            if let cache = try? ScoreCache() { cache.save(new, for: activeHome.id) }
            scoreFailure = nil
        } catch is CancellationError {
            // superseded
        } catch {
            scoreFailure = BackendFailure(error, while: .score)
        }
    }
    
    // MARK: - Scan Conversion (copied from original)
    
    private func processRecheck(artifacts: ScanArtifacts, roomID: String) async {
        isConverting = true
        defer { isConverting = false }
        do {
            guard let activeHome = activeHome else { return }
            let scanModel = try await apiClient.convertScan(at: artifacts.rawJSON, homeName: "Recheck")
            let diffRequest = DiffRequest(stored_model: activeHome, scan_model: scanModel, target_room_id: roomID)
            let result = try await apiClient.diffObstructions(diffRequest)
            pendingRecheckRoomID = roomID
            pendingDiffResult = result
        } catch {
            scanFailure = BackendFailure(error, while: .score)
        }
    }

    private func importScan(_ artifacts: ScanArtifacts) async {
        isConverting = true
        lastScanArtifacts = artifacts
        defer { isConverting = false }
        do {
            let name = "Scanned Home \(Date().formatted(date: .abbreviated, time: .shortened))"
            let model = try await apiClient.convertScan(at: artifacts.rawJSON, homeName: name)
            let summary = try library.store.save(model: model)
            // Baseline for the "a wall was added or removed since the last scan" nudge —
            // recorded at the moment of the scan that made the model current.
            freshnessStore.recordWallEdgeCount(ScanFreshness.wallEdgeCount(model), homeID: summary.id)
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

    // MARK: - Prevent section

    /// S11.5 reframe: readiness score/checklist (above), then Prevent, then the family plan,
    /// then homes (01-product-spec.md §2 — "a cited in-app prevention layer").
    @ViewBuilder
    private var preventSection: some View {
        if !preventionTips.isEmpty {
            sectionLabel("Prevent")
            VStack(spacing: 10) {
                ForEach(PreventionTipsFilter.spotlight(preventionTips)) { tip in
                    PreventionTipCard(tip: tip)
                }
            }
            .padding(.horizontal, DS.pagePadding)
        }
    }

    // MARK: - Family plan section

    @ViewBuilder
    private func familyPlanSection(_ home: HomeModel) -> some View {
        sectionLabel("Family plan")
        VStack(spacing: 14) {
            meetingPointCard(home)
            PracticeReminderCard(homeID: home.id, homeName: home.name, lastPracticed: lastPracticed)
                .dsCard(padding: 16)
            // S11.6's opt-in share, wired at integration: the firefighter's own best idea,
            // so it sits in the family plan rather than buried in Settings. The card owns its
            // consent sheet and share state — nothing to bind from here.
            ShareWithFireDepartmentCard(homeID: home.id, store: library.store)
        }
        .padding(.horizontal, DS.pagePadding)
    }

    /// Read-only display: the meeting place is edited in the real export flow
    /// (Export/ExportPlanSheet.swift, S11.6's territory), not duplicated here. Tapping opens
    /// that same sheet rather than a second editor for the same UserDefaults-backed value.
    private func meetingPointCard(_ home: HomeModel) -> some View {
        let point = MeetingPointStore().meetingPoint(forHomeID: home.id)
        return Button { showingExportSheet = true } label: {
            HStack(spacing: 14) {
                DSIconBadge(systemImage: "mappin.and.ellipse", fill: Theme.accent, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meeting point").font(.subheadline.weight(.semibold)).foregroundStyle(DS.ink)
                    Text(point.isEmpty ? "Not set yet — tap to add one" : point)
                        .font(.footnote)
                        .foregroundStyle(DS.supporting)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .buttonStyle(HapticPlainButtonStyle())
        .dsCard(padding: 14)
        .accessibilityLabel("Meeting point: \(point.isEmpty ? "not set" : point)")
        .accessibilityHint("Opens the export sheet to set your outside meeting place.")
    }

    // MARK: - Homes section

    /// Only shown once there is a choice to make — a single-home library already names its
    /// home in the navigation title, so a one-row list here would be pure repetition.
    @ViewBuilder
    private var homesSection: some View {
        if library.homes.count > 1 {
            sectionLabel("Homes")
            VStack(spacing: 0) {
                ForEach(Array(library.homes.enumerated()), id: \.element.id) { index, home in
                    if index > 0 { Divider().padding(.leading, 52) }
                    Button { switchActiveHome(to: home.id) } label: {
                        HStack(spacing: 12) {
                            DSIconBadge(systemImage: "house.fill",
                                       fill: home.id == activeHomeID ? Theme.accent : DS.supporting,
                                       size: 36)
                            Text(home.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DS.ink)
                            Spacer()
                            if home.id == activeHomeID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HapticPlainButtonStyle())
                    .accessibilityLabel(home.name)
                    .accessibilityAddTraits(home.id == activeHomeID ? [.isSelected] : [])
                }
            }
            .dsCard(padding: nil)
            .padding(.horizontal, DS.pagePadding)
        }
    }
}

/// One card in the "Prevent" section — a tip and its tappable source label. `cite` is never
/// omitted from a PreventionTip (see PreventionTip.swift), so this view has no "no citation"
/// branch to fall into by construction.
private struct PreventionTipCard: View {
    let tip: PreventionTip
    @State private var showingSource = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(perilLabel)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(DS.supporting)
            Text(tip.text)
                .font(.subheadline)
                .foregroundStyle(DS.bodyInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { showingSource.toggle() }
            } label: {
                Label(showingSource ? "Source: \(tip.cite)" : "Source", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
            }
            .buttonStyle(.plain)
            .hapticTap()
            .accessibilityHint("Shows which cited guidance this tip comes from.")
        }
        .dsCard(radius: DS.cardRadiusLarge, padding: 16)
        .accessibilityElement(children: .combine)
    }

    /// "Severe weather" rather than the corpus's own "tornado" tag, matching HazardTag's
    /// label everywhere else in the app (ScoreModels.swift / HomeScreen's own hazardLabel).
    private var perilLabel: String {
        switch tip.peril {
        case .fire: return "Fire"
        case .earthquake: return "Earthquake"
        case .tornado: return "Severe weather"
        }
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


// MARK: - Score gauge (the design's 240° arc)

/// 240° arc gauge opening at the bottom, tick ring, score inside, "Tap for breakdown" pill.
/// Geometry from the design: r = 100, stroke 14, 25 ticks every 10° from 150°.
/// The design's 240° arc. It sweeps up from zero when a score arrives — the arc fills, the
/// notches light one by one under the finger, the number counts — and lands with a firm stop
/// (and the success flourish at 85+). Reduce Motion shows the final value at once, one tick.
struct DSScoreGauge: View {
    let score: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the arc, notches and number currently show (0…100). Chases `score`.
    @State private var displayed: Double = 0
    @State private var sweepTask: Task<Void, Never>?

    private let arcFraction = 240.0 / 360.0
    private static let notchCount = 25
    private let gradient = LinearGradient(
        colors: [Color(red: 0.545, green: 0.878, blue: 0.675),
                 Color(red: 0.133, green: 0.706, blue: 0.361),
                 Theme.accent],
        startPoint: .bottomLeading, endPoint: .topTrailing)

    var body: some View {
        let fraction = displayed / 100
        ZStack(alignment: .top) {
            ZStack {
                Circle()
                    .trim(from: 0, to: arcFraction)
                    .stroke(DS.track, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(150))
                Circle()
                    .trim(from: 0, to: arcFraction * fraction)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(150))
                    .shadow(color: Theme.accent.opacity(0.20), radius: 12, y: 12)
                ForEach(0..<Self.notchCount, id: \.self) { i in
                    Capsule()
                        .fill(Double(i) / Double(Self.notchCount - 1) <= fraction + 0.0001
                              ? Theme.accent : DS.track)
                        .frame(width: 2.5, height: 8)
                        .offset(y: -80)
                        .rotationEffect(.degrees(240 + Double(i) * 10))
                }
                VStack(spacing: 4) {
                    Text("\(Int(displayed.rounded()))")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .kerning(-2)
                        .foregroundStyle(DS.ink)
                    Text("of 100")
                        .font(.body.weight(.medium))
                        .foregroundStyle(DS.supporting)
                }
                .offset(y: -6)
            }
            .frame(width: 200, height: 200)
            .padding(.top, 25)

            Text("Tap for breakdown")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(DS.card, in: Capsule())
                .shadow(color: DS.shadowColor, radius: 9, y: 6)
                .padding(.top, 192)
        }
        .frame(width: 260, height: 232)
        .accessibilityElement(children: .ignore)
        .onChange(of: score, initial: true) { _, target in sweep(to: target) }
        .onDisappear { sweepTask?.cancel() }
    }

    private func sweep(to target: Int) {
        sweepTask?.cancel()
        let to = Double(min(max(target, 0), 100))
        let from = displayed
        guard !reduceMotion, abs(to - from) >= 1 else {
            displayed = to
            if abs(to - from) >= 1 { Haptics.tick() }
            return
        }
        sweepTask = Task { @MainActor in
            let haptics = HapticSweep()
            // 0.9 s for a nudge, about 1.4 s for the full climb from zero.
            let duration = 0.9 + 0.5 * abs(to - from) / 100
            let start = Date()
            var lastNotch = notch(for: from)
            while !Task.isCancelled {
                let t = min(1, Date().timeIntervalSince(start) / duration)
                let eased = 1 - pow(1 - t, 3)
                displayed = from + (to - from) * eased
                let current = notch(for: displayed)
                if current != lastNotch {
                    haptics.tick(progress: displayed / 100)
                    lastNotch = current
                }
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            displayed = to
            haptics.finish(celebrate: to >= 85)
        }
    }

    private func notch(for value: Double) -> Int {
        Int((value / 100 * Double(Self.notchCount - 1)).rounded(.down))
    }
}

/// What the quick-details sheet's main button does for a row.
private struct ChecklistRowAction {
    let title: String
    let icon: String
    /// Leaves Home (House or Drill) rather than toggling in place.
    let navigates: Bool
}

/// The quick-details page for one checklist item: everything the compact row leaves out,
/// and the one thing to do about it.
private struct ChecklistItemSheet: View {
    let item: ChecklistItem
    let isDone: Bool
    let primary: ChecklistRowAction
    let onPrimary: () -> Void
    var secondary: ChecklistRowAction? = nil
    var onSecondary: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        statusPill
                        if let hazard = item.hazard { chip(label(hazard.rawValue)) }
                        chip(label("\(item.category)"))
                    }
                    Text(item.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DS.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(item.detail)
                        .font(.body)
                        .foregroundStyle(DS.bodyInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let source = item.source_citation, !source.isEmpty {
                        Label(source, systemImage: "doc.text")
                            .font(.footnote)
                            .foregroundStyle(DS.supporting)
                    }
                    if item.scoring {
                        Text("Counts toward your preparedness score.")
                            .font(.footnote)
                            .foregroundStyle(DS.supporting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.pagePadding)
            }
            .safeAreaInset(edge: .bottom) {
                DSPrimaryButton(title: primary.title, systemImage: primary.icon, action: onPrimary)
                    .padding(.horizontal, DS.pagePadding)
                    .padding(.bottom, 8)
                if let sec = secondary, let onSec = onSecondary {
                    Button(action: onSec) {
                        Label(sec.title, systemImage: sec.icon)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.inset, in: Capsule())
                            .foregroundStyle(DS.ink)
                    }
                    .padding(.horizontal, DS.pagePadding)
                    .padding(.bottom, 8)
                }
            }
            .dsPage()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.hapticTap()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var statusPill: some View {
        Text(isDone ? "Done" : "To do")
            .font(.caption.weight(.bold))
            .foregroundStyle(isDone ? Theme.accentText : Theme.caution)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isDone ? DS.accentFill : DS.cautionFill, in: Capsule())
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DS.supporting)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(DS.inset, in: Capsule())
    }

    private func label(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
