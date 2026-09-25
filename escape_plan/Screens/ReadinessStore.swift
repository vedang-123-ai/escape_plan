//  ReadinessStore.swift
//  Screens — the active home's readiness state, shared by the Home and Tasks tabs (Linear
//  revamp, 2026-09-25). This used to live inside HomeScreen; splitting the checklist into its own
//  tab means two screens read the same score, checklist and done-state, so it is owned once, by
//  ContentView, and handed to both through the environment.
//
//  The score and checklist still come only from the backend's `/score` response. This type
//  loads, caches and re-requests; it never computes a score or invents an item.

import Observation
import SwiftUI

@MainActor
@Observable
final class ReadinessStore {
    @ObservationIgnored let library: HomeLibrary

    private(set) var activeHomeID: String?
    private(set) var activeHome: HomeModel?
    private(set) var breakdown: ScoreBreakdown?
    private(set) var checklistState: [String: Bool] = [:]
    private(set) var isScoring = false
    private(set) var scoreFailure: BackendFailure?
    private(set) var lastPracticed: Date?
    private(set) var preventionTips: [PreventionTip] = []

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let stateStore = ChecklistStateStore()
    @ObservationIgnored let freshnessStore = ScanFreshnessStore()

    init(library: HomeLibrary) {
        self.library = library
        activeHomeID = library.homes.first?.id
        preventionTips = Self.bundledTips()
    }

    // MARK: - Reading

    var items: [ChecklistItem] { breakdown?.checklist ?? [] }

    func isDone(_ item: ChecklistItem) -> Bool { checklistState[item.id] ?? item.done }

    /// The items that can cap the score — the backend's own high-severity rule.
    var urgentOpen: [ChecklistItem] { items.filter { $0.severity == .high && !isDone($0) } }

    /// What to do next, most important first: open urgent items, then open items that move the
    /// score, then the rest.
    var upNext: [ChecklistItem] {
        let open = items.filter { !isDone($0) }
        return open.sorted { rank($0) < rank($1) }
    }

    private func rank(_ item: ChecklistItem) -> Int {
        if item.severity == .high { return 0 }
        return item.scoring ? 1 : 2
    }

    /// Whichever of the two S11.5 triggers applies right now — a wall added or removed since the
    /// last scan, or the age threshold passed — or nil if the plan is fresh.
    var nudgeReason: ScanFreshness.NudgeReason? {
        guard let home = activeHome else { return nil }
        let days = ScanFreshness.daysSince(lastScanned: home.meta.last_scanned, modified: home.meta.modified)
        let changed = ScanFreshness.wallsChanged(
            currentEdgeCount: ScanFreshness.wallEdgeCount(home),
            recordedEdgeCount: freshnessStore.recordedWallEdgeCount(homeID: home.id))
        return ScanFreshness.nudgeReason(daysSinceScan: days, wallsChanged: changed)
    }

    // MARK: - Changing the active home

    /// Keeps `activeHomeID` pointing at a home that exists (after a delete, or a first sync).
    func ensureActiveHome() {
        if activeHomeID == nil || !library.homes.contains(where: { $0.id == activeHomeID }) {
            activeHomeID = library.homes.first?.id
        }
    }

    func select(_ homeID: String, api: APIClient) async {
        guard homeID != activeHomeID || activeHome == nil else { return }
        activeHomeID = homeID
        breakdown = nil
        await load(api: api)
    }

    /// A model the Home tab changed outside the editor (the partial re-scan diff).
    func replaceActiveHome(_ home: HomeModel, api: APIClient) {
        activeHome = home
        rescore(api: api)
    }

    // MARK: - Loading and scoring

    func load(api: APIClient) async {
        guard let activeHomeID else {
            activeHome = nil
            breakdown = nil
            return
        }
        checklistState = stateStore.load(homeID: activeHomeID)
        if breakdown == nil, let cache = try? ScoreCache() {
            breakdown = cache.load(homeID: activeHomeID)
        }
        do {
            let home = try library.store.load(homeID: activeHomeID, as: HomeModel.self)
            activeHome = home
            // A home scanned before this feature shipped (or seeded by FixtureSeeder) has no
            // recorded baseline. Seed it to the CURRENT count so the next real edit is detectable.
            if home.meta.last_scanned != nil,
               freshnessStore.recordedWallEdgeCount(homeID: activeHomeID) == nil {
                freshnessStore.recordWallEdgeCount(ScanFreshness.wallEdgeCount(home), homeID: activeHomeID)
            }
            lastPracticed = (try? DrillLogStore())?.lastPracticed(homeID: activeHomeID)
        } catch {
            scoreFailure = BackendFailure(error, while: .score)
            return
        }
        await fetchScore(api: api)
    }

    func rescore(api: APIClient) {
        refreshTask?.cancel()
        refreshTask = Task { await fetchScore(api: api) }
    }

    private func fetchScore(api: APIClient) async {
        guard let activeHome else { return }
        isScoring = true
        defer { isScoring = false }
        do {
            let new = try await api.score(home: activeHome, checklistState: checklistState)
            guard !Task.isCancelled else { return }
            breakdown = new
            if let cache = try? ScoreCache() { cache.save(new, for: activeHome.id) }
            scoreFailure = nil
        } catch is CancellationError {
            // superseded by a newer request
        } catch {
            scoreFailure = BackendFailure(error, while: .score)
        }
    }

    // MARK: - Done state

    /// Flips a narrative item and re-scores. Done gets the firmer tick, undone a quiet notch.
    func toggleDone(_ item: ChecklistItem, api: APIClient, animated: Bool = true) {
        let newDone = !isDone(item)
        withAnimation(animated ? .snappy(duration: 0.22) : nil) { checklistState[item.id] = newDone }
        if let activeHomeID { stateStore.save(checklistState, homeID: activeHomeID) }
        if newDone { Haptics.tick() } else { Haptics.selection() }
        rescore(api: api)
    }

    // MARK: - Prevention tips

    private static func bundledTips() -> [PreventionTip] {
        guard let url = Bundle.main.url(forResource: "prevention_tips", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tips = try? PreventionTips.decode(from: data) else { return [] }
        return tips
    }
}

// MARK: - Where a task takes you

/// What completing a checklist item means: look at something in the 3D house, run a drill, or
/// just tick it off here. Engine-scored spatial items are decided by the model, so they go to
/// the house; narrative items are the user's word and toggle in place.
enum TaskDestination {
    case house, drill, toggle

    init(_ item: ChecklistItem) {
        switch item.category {
        case .practice: self = .drill
        case .smoke_alarm, .routes, .egress, .agent_finding, .recommendation: self = .house
        default: self = .toggle
        }
    }

    var label: String? {
        switch self {
        case .house: return "House"
        case .drill: return "Drill"
        case .toggle: return nil
        }
    }

    var symbol: String? {
        switch self {
        case .house: return "cube"
        case .drill: return "play"
        case .toggle: return nil
        }
    }

    func actionTitle(done: Bool) -> String {
        switch self {
        case .house: return "Show me in the house"
        case .drill: return "Run a drill"
        case .toggle: return done ? "Mark as not done" : "Mark as done"
        }
    }

    func actionSymbol(done: Bool) -> String {
        switch self {
        case .house: return "cube"
        case .drill: return "play.fill"
        case .toggle: return done ? "arrow.uturn.backward" : "checkmark"
        }
    }
}

extension HazardTag {
    var label: String {
        switch self {
        case .fire: return "Fire"
        case .earthquake: return "Earthquake"
        case .severe_weather: return "Severe weather"
        case .general: return "General"
        }
    }

    /// The dot on a peril chip. Fire takes the hazard ember (it labels the fire system);
    /// the others take state colours that are not route or exit inks.
    var tint: Color {
        switch self {
        case .fire: return Theme.hazardInk
        case .earthquake: return Theme.caution
        case .severe_weather: return Theme.accentText
        case .general: return Theme.supporting
        }
    }
}
