//  HomeScreen.swift
//  escape_plan — the Home tab (Linear revamp, 2026-09-25).
//
//  A short overview, not a dashboard: which home, how prepared it is, the next three things to
//  do, the two things you come here for (drill, 3D house), and one cited prevention tip. The full
//  checklist moved to the Tasks tab; Home owns the flows that add a home (scan, build, import)
//  and the partial re-scan, because they start here.

import SwiftUI

struct HomeScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(ReadinessStore.self) private var readiness
    @Environment(AppRouter.self) private var router
    @EnvironmentObject private var library: HomeLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Adding a home
    @State private var showingNewHome = false
    @State private var showingBuildFromPlan = false
    @State private var showingScan = false
    @State private var isConverting = false
    @State private var scanFailure: BackendFailure?
    @State private var lastScanArtifacts: ScanArtifacts?

    // Partial re-scan of one room
    @State private var targetRecheckRoomID: String?
    @State private var showingRoomPicker = false
    @State private var pendingDiffResult: DiffResult?
    @State private var pendingRecheckRoomID: String?

    @State private var scoreHomeID: String?
    @State private var drillHomeID: String?
    @State private var profilesHomeID: String?
    @State private var detailItem: ChecklistItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    scanFailureBanner
                    if isConverting {
                        LoadingTipView(label: "Converting scan…").frame(minHeight: 420)
                    } else if library.homes.isEmpty {
                        emptyState
                    } else {
                        titleBlock
                        if readiness.needsDraftReview {
                            draftReview
                        } else {
                            scoreSection
                            upNextSection
                            quickActions
                            household
                        }
                        tipSection
                    }
                }
                .padding(.bottom, 32)
            }
            .refreshable { Haptics.begin(); await readiness.load(api: apiClient) }
            .dsPage()
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: router.homeIntent) { _, intent in
                guard let intent else { return }
                router.homeIntent = nil
                switch intent {
                case .scan: targetRecheckRoomID = nil; showingScan = true
                case .recheckRoom: showingRoomPicker = true
                }
            }
            .confirmationDialog("Select a room to re-check", isPresented: $showingRoomPicker, titleVisibility: .visible) {
                if let home = readiness.activeHome {
                    ForEach(home.floors.flatMap(\.rooms)) { room in
                        Button(room.name) {
                            targetRecheckRoomID = room.id
                            showingScan = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(item: Binding<DiffResultWrapper?>(
                get: { pendingDiffResult.map { DiffResultWrapper(result: $0) } },
                set: { if $0 == nil { pendingDiffResult = nil } }
            )) { wrapper in
                DiffReviewSheet(
                    result: wrapper.result,
                    onAdd: { obj in
                        guard var home = readiness.activeHome, let roomID = pendingRecheckRoomID,
                              let floorIdx = home.floors.firstIndex(where: { $0.rooms.contains(where: { $0.id == roomID }) })
                        else { return }
                        home.floors[floorIdx].objects.append(obj)
                        try? library.store.save(model: home)
                        readiness.replaceActiveHome(home, api: apiClient)
                    },
                    onDismiss: { pendingDiffResult = nil; pendingRecheckRoomID = nil }
                )
            }
            .sheet(isPresented: $showingBuildFromPlan) {
                BuildFromPlanView { homeID in
                    library.refresh()
                    openDraftForReview(homeID)
                }
            }
            .sheet(item: $detailItem) { item in
                TaskDetailSheet(item: item,
                                isDone: readiness.isDone(item),
                                onPrimary: { perform(item) },
                                onRecheck: item.id == "rescan.home"
                                    ? { detailItem = nil; showingRoomPicker = true } : nil)
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
            .navigationDestination(isPresented: $showingNewHome) {
                HouseScreen(homeID: nil, library: library) {
                    library.refresh()
                    if let id = library.homes.first?.id { switchHome(to: id) }
                }
            }
            // Score reads the shared ReadinessStore (the active home), so the id only drives
            // the push.
            .navigationDestination(item: $scoreHomeID) { _ in ScoreScreen() }
            .navigationDestination(item: $drillHomeID) { homeID in
                // The drill writes its own log; "Last: …" on the drill card must not wait
                // for the next full load to notice.
                DrillScreen(homeID: homeID)
                    .onDisappear { readiness.refreshLastPracticed() }
            }
            .navigationDestination(item: $profilesHomeID) { homeID in
                ProfilesScreen(homeID: homeID, store: library.store)
            }
        }
    }

    // MARK: - Top bar: the home switcher, sync, and "add"

    private var topBar: some View {
        HStack(spacing: 8) {
            Menu {
                Section("Homes") {
                    ForEach(library.homes) { home in
                        Button { switchHome(to: home.id) } label: {
                            if home.id == readiness.activeHomeID {
                                Label(home.name, systemImage: "checkmark")
                            } else {
                                Text(home.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(readiness.activeHome?.name ?? "Escape Plan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.supporting)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Home: \(readiness.activeHome?.name ?? "none"). Switch home.")
            Spacer()
            SyncStatusBadge()
            Menu {
                Button { targetRecheckRoomID = nil; showingScan = true } label: {
                    Label("Scan New Home", systemImage: "camera.viewfinder")
                }
                .accessibilityIdentifier("Scan New Home")
                Button { showingNewHome = true } label: { Label("Build Manually", systemImage: "square.and.pencil") }
                    .accessibilityIdentifier("Build Manually")
                Button { showingBuildFromPlan = true } label: { Label("Import Plan", systemImage: "wand.and.stars") }
                    .accessibilityIdentifier("Import Plan")
            } label: {
                Label("Menu", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 34, height: 34)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, DS.pagePadding - 8)
        .padding(.top, 4)
    }

    private func switchHome(to id: String) {
        // A pending "show me in the house" belongs to the home it was made for. Left in place,
        // it pinned the House tab to the previous home after a switch (audit 2026-09-25).
        if id != readiness.activeHomeID { router.clearHouseRequest() }
        Task { await readiness.select(id, api: apiClient) }
    }

    /// A finished Import Plan opens House on the new draft: the spec's mandatory editor review
    /// (§4). Making it active alone left the user on Home with a score for a floor plan an LLM
    /// guessed (AUD-023). Selected first, so House's request is for the active home.
    private func openDraftForReview(_ id: String) {
        router.clearHouseRequest()
        Task {
            await readiness.select(id, api: apiClient)
            router.openHouse(homeID: id)
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(.largeTitle, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            if let home = readiness.activeHome {
                Text(homeSummary(home))
                    .font(.subheadline)
                    .foregroundStyle(Theme.supporting)
            }
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    }

    private func homeSummary(_ home: HomeModel) -> String {
        let rooms = home.floors.reduce(0) { $0 + $1.rooms.count }
        let floors = home.floors.count
        // An unconfirmed AI draft was neither scanned nor built by hand; say what it is (AUD-023).
        let age = readiness.needsDraftReview
            ? "AI draft, not reviewed yet"
            : ScanFreshness.scanAgeText(lastScanned: home.meta.last_scanned, modified: home.meta.modified)
        return "\(rooms) \(rooms == 1 ? "room" : "rooms") · \(floors) \(floors == 1 ? "floor" : "floors") · \(age.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
    }

    // MARK: - Score

    /// An unreviewed AI draft: no score, no next tasks and no drill (a drill would plan routes on
    /// the draft); one way forward, to House (AUD-023).
    @ViewBuilder
    private var draftReview: some View {
        DraftReviewNotice().padding(.horizontal, DS.pagePadding)
    }

    @ViewBuilder
    private var scoreSection: some View {
        if let breakdown = readiness.breakdown {
            Button { scoreHomeID = readiness.activeHomeID } label: { scoreCard(breakdown.score) }
                .buttonStyle(DSPressStyle())
                .padding(.horizontal, DS.pagePadding)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preparedness score \(breakdown.score) out of 100, \(ReadinessStore.band(for: breakdown.score).title). Opens the breakdown.")
        } else if let failure = readiness.scoreFailure {
            BackendFailureBanner(failure: failure,
                                 retry: failure.isRetryable ? { readiness.rescore(api: apiClient) } : nil)
                .padding(.horizontal, DS.pagePadding)
        } else {
            LoadingTipView(label: "Scoring…").frame(minHeight: 240)
        }
    }

    private func scoreCard(_ score: Int) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preparedness")
                    .font(.footnote)
                    .foregroundStyle(Theme.supporting)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(score)")
                        // Dynamic Type (audit 2026-09-25): was a fixed 44 pt.
                        .font(Theme.metric)
                        .monospacedDigit()
                        .kerning(-1.5)
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text("/ 100").font(.subheadline).foregroundStyle(Theme.supporting)
                }
                HStack(spacing: 8) {
                    // One band definition for Home and Score (`Readiness/ScoreBand.swift`).
                    DSStatusPill(text: ReadinessStore.band(for: score).title,
                                 tint: ReadinessStore.band(for: score).tint)
                    HStack(spacing: 3) {
                        Text("Breakdown")
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.supporting)
                }
            }
            Spacer(minLength: 8)
            DSScoreGauge(score: score)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: 16)
    }

    // MARK: - Up next

    @ViewBuilder
    private var upNextSection: some View {
        if readiness.breakdown != nil {
            let next = Array(readiness.upNext.prefix(3))
            HStack {
                Text("Up next").sectionHeaderStyle()
                Spacer()
                Button { router.selectedTab = .tasks } label: {
                    HStack(spacing: 3) {
                        Text("All tasks")
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HapticPlainButtonStyle())
            }
            .padding(.horizontal, DS.pagePadding)
            .padding(.top, 20)

            VStack(spacing: 0) {
                if next.isEmpty {
                    HStack(spacing: 10) {
                        TaskStatusIcon(done: true)
                        Text("You're all caught up.").font(.subheadline).foregroundStyle(Theme.supporting)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
                ForEach(Array(next.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    TaskRow(item: item,
                            done: readiness.isDone(item),
                            onToggle: { readiness.toggleDone(item, api: apiClient, animated: !reduceMotion) },
                            onOpen: { detailItem = item })
                }
            }
            .dsCard(padding: nil)
            .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
            .padding(.horizontal, DS.pagePadding)
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 8) {
            actionCard(title: "Run a fire drill",
                       subtitle: lastPracticedText,
                       symbol: "play.fill",
                       tint: Theme.accentText) { drillHomeID = readiness.activeHomeID }
            actionCard(title: "Open 3D house",
                       subtitle: "Routes, exits, hazards",
                       symbol: "cube.fill",
                       tint: Theme.routeInk) { router.openHouse(homeID: readiness.activeHomeID) }
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 12)
    }

    /// Who lives here (AUD-020): per-person routes and the drill need at least one profile.
    @ViewBuilder
    private var household: some View {
        if let home = readiness.activeHome {
            HouseholdRow(profiles: home.profiles) { profilesHomeID = home.id }
                .padding(.horizontal, DS.pagePadding)
                .padding(.top, 8)
        }
    }

    private var lastPracticedText: String {
        guard let date = readiness.lastPracticed else { return "Never practised" }
        return "Last: \(date.formatted(.relative(presentation: .named)))"
    }

    private func actionCard(title: String, subtitle: String, symbol: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                DSIconBadge(systemImage: symbol, fill: tint, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.supporting).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard(padding: 14)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tip

    @ViewBuilder
    private var tipSection: some View {
        let spotlight = PreventionTipsFilter.spotlight(readiness.preventionTips)
        if !spotlight.isEmpty {
            let tip = spotlight[Calendar.current.ordinality(of: .day, in: .era, for: Date()).map { $0 % spotlight.count } ?? 0]
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb").font(.caption2.weight(.semibold))
                    Text("Prevention tip")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.supporting)
                Text(tip.text)
                    .font(.subheadline)
                    .foregroundStyle(DS.bodyInk)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Source: \(tip.cite)")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard(padding: 14)
            .accessibilityElement(children: .combine)
            .padding(.horizontal, DS.pagePadding)
            .padding(.top, 20)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            DSIconBadge(systemImage: "house", fill: Theme.accentText, size: 40)
            Text("Map your home")
                .font(.system(.largeTitle, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(Theme.text)
            // Prevention and readiness first — never a claim that firefighters use this app.
            Text("Map it once. We'll show cited prevention basics, a readiness checklist, and an escape route for every person who lives here.")
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                DSPrimaryButton(title: "Scan my home", systemImage: "camera.viewfinder") {
                    targetRecheckRoomID = nil; showingScan = true
                }
                DSSecondaryButton(title: "Build it myself") { showingNewHome = true }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 60)
    }

    // MARK: - Doing a task

    private func perform(_ item: ChecklistItem) {
        let destination = TaskDestination(item)
        guard destination != .toggle else {
            readiness.toggleDone(item, api: apiClient, animated: !reduceMotion)
            return
        }
        detailItem = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            if destination == .drill {
                drillHomeID = readiness.activeHomeID
            } else {
                router.openHouse(homeID: readiness.activeHomeID, focusItemID: item.id)
            }
        }
    }

    // MARK: - Scan conversion

    private func processRecheck(artifacts: ScanArtifacts, roomID: String) async {
        isConverting = true
        defer { isConverting = false }
        do {
            guard let activeHome = readiness.activeHome else { return }
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
            // Baseline for the "a wall was added or removed since the last scan" nudge.
            readiness.freshnessStore.recordWallEdgeCount(ScanFreshness.wallEdgeCount(model), homeID: summary.id)
            library.refresh()
            scanFailure = nil
            lastScanArtifacts = nil
            await readiness.select(summary.id, api: apiClient)
            router.openHouse(homeID: summary.id)
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
            .padding(.horizontal, DS.pagePadding)
        }
    }

    private func retryScanImport() {
        guard let artifacts = lastScanArtifacts else { return }
        Task { await importScan(artifacts) }
    }
}

// MARK: - Score gauge

/// A segmented progress ring. It sweeps up from zero when a score arrives — the segments light
/// one by one under the finger — and lands with a firm stop (and the success flourish at 85+).
/// Reduce Motion shows the final value at once, one tick.
struct DSScoreGauge: View {
    let score: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the arc, notches and number currently show (0…100). Chases `score`.
    @State private var displayed: Double = 0
    @State private var sweepTask: Task<Void, Never>?

    private static let notchCount = 24
    private let size: CGFloat = 84

    var body: some View {
        let fraction = displayed / 100
        ZStack {
            // Segmented ring: 24 short arcs, lit up to the score — Linear's progress glyph, scaled up.
            ForEach(0..<Self.notchCount, id: \.self) { i in
                let start = Double(i) / Double(Self.notchCount)
                let lit = start < fraction - 0.0001
                Circle()
                    .trim(from: start + 0.006, to: start + 1 / Double(Self.notchCount) - 0.006)
                    .stroke(lit ? Theme.accent : DS.track,
                            style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(fraction > 0 ? Theme.accentText : DS.supporting)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

