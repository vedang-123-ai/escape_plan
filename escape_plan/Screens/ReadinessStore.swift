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
    /// The last score, tagged with the home it was computed for (AUD-014). `ScoreBreakdown` alone
    /// cannot say which request it answered, so the tag is kept beside it.
    private var scored: (homeID: String, breakdown: ScoreBreakdown)?
    private(set) var checklistState: [String: ChecklistMark] = [:]
    /// A recurring item ticked or unticked since the last /score answer (S11.35). Shown until the
    /// answer lands, then dropped: from there the server's `done` is the only clock.
    private var pendingRecurring: [String: Bool] = [:]
    /// When each item was ticked done while the checklist on screen did not say it recurs
    /// (S11.50). Only a score cached before S11.35 lacks `recurrence_days`, so such a tick is stored
    /// as a plain `true`. If the next answer says the item does recur, the tick gets this date, so
    /// it can lapse like any other; a plain `true` on a recurring item would count as done forever.
    /// Kept in memory only: if the app quits first, the plain `true` stays, as before.
    private var untimedTicks: [String: Date] = [:]
    /// Shown on Tasks when the server refused the date of a tick just made: the phone's clock is
    /// out by more than the server allows (S11.50). Cleared by the next answer that refuses none.
    private(set) var tickNotice: String?
    /// The time a tick records. A test sets it; nothing else does.
    @ObservationIgnored var now: () -> Date = { Date() }
    private(set) var isScoring = false
    private(set) var scoreFailure: BackendFailure?
    private(set) var preventionTips: [PreventionTip] = []

    /// The one in-flight /score request. Every way in (launch, switching homes, onboarding, sync,
    /// pull to refresh, Retry, a ticked task, a household change) goes through `startScoreFetch`,
    /// which cancels this first, so at most one request can change state.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Bumped whenever the in-flight request stops counting (cancelled or replaced). A response
    /// carries the value it started with and is dropped if it no longer matches.
    @ObservationIgnored private var scoreGeneration = 0
    /// Homes seen as unreviewed drafts this launch. Their cached score (written by a build before
    /// AUD-023 was fixed) describes the guessed plan, so it is not shown once they are confirmed;
    /// the first /score after confirming replaces it.
    @ObservationIgnored private var seenAsDraft: Set<String> = []
    @ObservationIgnored private let stateStore = ChecklistStateStore()
    @ObservationIgnored let freshnessStore = ScanFreshnessStore()

    /// Remembers the active home across launches (S53-2). nil in tests and previews, so they
    /// never write the app's own choice; `ContentView` passes the real one.
    @ObservationIgnored private let homeMemory: ActiveHomeMemory?
    /// The home a fresh install opens on (S53-1). A test can name another.
    @ObservationIgnored private let demoHomeID: String?

    /// Opens on the remembered home if it still exists, else the demo home, else the first.
    init(library: HomeLibrary, homeMemory: ActiveHomeMemory? = nil,
         demoHomeID: String? = FixtureSeeder.demoHomeID) {
        self.library = library
        self.homeMemory = homeMemory
        self.demoHomeID = demoHomeID
        activeHomeID = ActiveHomeMemory.choose(remembered: homeMemory?.remembered,
                                               available: library.homes.map(\.id),
                                               demoHomeID: demoHomeID)
        preventionTips = Self.bundledTips()
    }

    // MARK: - Reading

    /// The score on screen. Only ever the active home's: a score computed for another home is
    /// never returned, whatever order responses arrived in (AUD-014).
    var breakdown: ScoreBreakdown? {
        guard let scored, scored.homeID == activeHomeID else { return nil }
        return scored.breakdown
    }

    /// Empty for an unreviewed draft, so the tab badge, Up next and the Tasks header follow the
    /// same predicate as the score, whatever a late response left in `breakdown`.
    var items: [ChecklistItem] { needsDraftReview ? [] : (breakdown?.checklist ?? []) }

    /// The active home still has AI-drafted elements nobody has confirmed (AUD-023). Such a home
    /// is never scored: the score would rest on a floor plan an LLM guessed, and House already
    /// refuses to draw routes for it. This is House's own predicate, not a copy; confirming the
    /// draft in House is the only way to clear it, and House's autosave reloads this store.
    var needsDraftReview: Bool { activeHome?.hasAIDraftContent ?? false }

    /// A recurring item follows the server's `done` (it ages out on the server's clock); a stored
    /// date is only ever sent, never read back as "done". Every other item is the user's word,
    /// so the local tick wins until the next answer agrees.
    func isDone(_ item: ChecklistItem) -> Bool {
        if item.recurrence_days != nil { return pendingRecurring[item.id] ?? item.done }
        switch checklistState[item.id] {
        case .flag(let done): return done
        // A date on an item that does not recur is ignored by the server too; show its answer.
        case .completed, nil: return item.done
        }
    }

    /// The items that can cap the score — the backend's own high-severity rule.
    var urgentOpen: [ChecklistItem] { items.filter { $0.severity == .high && !isDone($0) } }

    /// What to do next, most important first: open urgent items, then open items that move the
    /// score, then the rest.
    var upNext: [ChecklistItem] {
        let open = items.filter { !isDone($0) }
        return open.sorted { rank($0) < rank($1) }
    }

    /// The one definition of a score's band, for every screen that shows a score (Home's card
    /// and the Score screen used to disagree). Thresholds: `Readiness/ScoreBand.swift`.
    static func band(for score: Int) -> ScoreBand { ScoreBand(score: score) }

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

    /// Keeps `activeHomeID` pointing at a home that exists (after a delete, or a first sync or
    /// onboarding fills an empty library). Same choice as launch: the remembered home, else the
    /// demo home, else the first.
    func ensureActiveHome() {
        if activeHomeID == nil || !library.homes.contains(where: { $0.id == activeHomeID }) {
            switchActiveHome(to: ActiveHomeMemory.choose(remembered: homeMemory?.remembered,
                                                         available: library.homes.map(\.id),
                                                         demoHomeID: demoHomeID))
        }
    }

    func select(_ homeID: String, api: APIClient) async {
        guard homeID != activeHomeID || activeHome == nil else { return }
        switchActiveHome(to: homeID)
        await load(api: api)
    }

    /// The only place `activeHomeID` changes after launch. The previous home's request, score and
    /// failure all stop counting here, before anything about the new home is shown.
    private func switchActiveHome(to homeID: String?) {
        cancelScoreFetch()
        activeHomeID = homeID
        homeMemory?.remember(homeID)
        pendingRecurring = [:]
        untimedTicks = [:]
        tickNotice = nil
        scored = nil
        scoreFailure = nil
    }

    /// A model changed outside the editor (the household editor in Profiles). Ignored unless it
    /// is the active home: another home's household must not be scored under this one's name.
    func replaceActiveHome(_ home: HomeModel, api: APIClient) {
        guard home.id == activeHomeID else { return }
        activeHome = home
        rescore(api: api)
    }

    // MARK: - Loading and scoring

    func load(api: APIClient) async {
        // Whatever was in flight was asked for the model about to be replaced.
        cancelScoreFetch()
        guard let activeHomeID else {
            activeHome = nil
            scored = nil
            scoreFailure = nil
            return
        }
        // `pendingRecurring` survives a same-home reload (pull to refresh, House autosave): an
        // offline tick must not vanish. A home switch clears it in `switchActiveHome`.
        checklistState = stateStore.load(homeID: activeHomeID)
        do {
            let home = try library.store.load(homeID: activeHomeID, as: HomeModel.self)
            activeHome = home
            // A home scanned before this feature shipped (or seeded by FixtureSeeder) has no
            // recorded baseline. Seed it to the CURRENT count so the next real edit is detectable.
            if home.meta.last_scanned != nil,
               freshnessStore.recordedWallEdgeCount(homeID: activeHomeID) == nil {
                freshnessStore.recordWallEdgeCount(ScanFreshness.wallEdgeCount(home), homeID: activeHomeID)
            }
        } catch {
            // A document on THIS device that won't load. It used to be reported as a backend
            // failure — "couldn't reach the server" — for a file that never left the phone.
            // Nothing stale is left standing either: the previous home's model and a cached
            // score would otherwise sit under the new home's id.
            activeHome = nil
            scored = nil
            scoreFailure = .localLoad(error)
            return
        }
        // An unreviewed draft shows no score at all, not even one cached before AUD-023 was fixed.
        if needsDraftReview {
            clearScoreForDraft()
            return
        }
        if breakdown == nil, !seenAsDraft.contains(activeHomeID),
           let cached = (try? ScoreCache())?.load(homeID: activeHomeID) {
            scored = (activeHomeID, cached)
        }
        // Awaited so pull to refresh keeps spinning until the answer; a newer request cancels
        // this one and the await returns early.
        await startScoreFetch(api: api).value
    }

    /// Returns the task so a test can await it instead of sleeping.
    @discardableResult
    func rescore(api: APIClient) -> Task<Void, Never> {
        startScoreFetch(api: api)
    }

    /// Every path to /score passes here (load, rescore, a ticked task, a household change). It
    /// cancels the previous request and tags the new one with the home and generation it is for.
    private func startScoreFetch(api: APIClient) -> Task<Void, Never> {
        cancelScoreFetch()
        // `ensureActiveHome` moves the id before the next `load` reads the new model; a Retry in
        // that window must not send the previous home's model (or clear its draft state).
        guard let home = activeHome, home.id == activeHomeID else { return Task {} }
        guard !needsDraftReview else {
            clearScoreForDraft()
            return Task {}
        }
        scoreGeneration += 1
        let generation = scoreGeneration
        let state = checklistState
        isScoring = true
        let task = Task { [weak self] in
            let result: Result<ScoreBreakdown, Error>
            do {
                result = .success(try await api.score(home: home, checklistState: state))
            } catch {
                result = .failure(error)
            }
            self?.finishScore(result, for: home, sent: state, generation: generation, api: api)
        }
        refreshTask = task
        return task
    }

    /// Lands a /score answer, or drops it. Success and failure are treated alike: only the
    /// current request, for the home still active, that is not an unreviewed draft, changes state.
    private func finishScore(_ result: Result<ScoreBreakdown, Error>, for home: HomeModel,
                             sent: [String: ChecklistMark], generation: Int, api: APIClient) {
        // Cancelled or replaced: whoever did that owns `isScoring` now.
        guard generation == scoreGeneration else { return }
        refreshTask = nil
        isScoring = false
        // Asked for another home, or the home became a draft while it was in flight (S11.17).
        guard home.id == activeHomeID, !needsDraftReview else { return }
        switch result {
        case .success(let new):
            let refused = Self.refusedTicks(in: new, sent: sent, ticked: pendingRecurring)
            scored = (home.id, new)
            pendingRecurring = [:]
            (try? ScoreCache())?.save(new, for: home.id)
            scoreFailure = nil
            tickNotice = refused.first.map(Self.clockNotice(for:))
            dateUntimedTicks(in: new, homeID: home.id, api: api)
        case .failure(let error):
            // A cancelled request is not a failure. A cancelled URLSession load throws
            // URLError(.cancelled), not CancellationError, so both are checked.
            guard !Self.isCancellation(error) else { return }
            scoreFailure = BackendFailure(error, while: .score)
        }
    }

    nonisolated static func isCancellation(_ error: Error) -> Bool {
        BackendFailure.isCancellation(error)
    }

    /// Recurring items ticked since the last answer whose date the server read and refused
    /// (S11.50). A fresh tick is stamped "now", so the server only refuses it when this phone's
    /// clock is more than a day ahead of the server's (`FUTURE_SKEW_TOLERANCE` in
    /// backend/app/scoring/checklist.py) or so far behind that the date is already past the
    /// item's interval. The echoed `completed_at` proves the server read our date, not another.
    nonisolated static func refusedTicks(in answer: ScoreBreakdown, sent: [String: ChecklistMark],
                                         ticked: [String: Bool]) -> [ChecklistItem] {
        answer.checklist.filter { item in
            guard item.recurrence_days != nil, !item.done, ticked[item.id] == true,
                  case .completed(let stamped)? = sent[item.id],
                  let echoed = item.completedAt else { return false }
            return abs(echoed.timeIntervalSince(stamped)) < 1
        }
    }

    /// Plain words, no blame on the server: the fix is the phone's own setting.
    nonisolated static func clockNotice(for item: ChecklistItem) -> String {
        "\u{201C}\(item.title)\u{201D} didn't stay ticked because this iPhone's date and time look wrong. "
            + "In the iPhone's Settings, open General, then Date & Time, turn on Set Automatically, "
            + "then tick it again."
    }

    /// A tick made while the checklist did not know an item recurs (an old cached score) was
    /// stored as a plain `true`. Now that an answer says it recurs, it gets the time it was made
    /// and is sent again, so it can lapse like any other tick (S11.50).
    private func dateUntimedTicks(in answer: ScoreBreakdown, homeID: String, api: APIClient) {
        defer { untimedTicks = [:] }  // every item's recurrence is known from here on
        var dated = false
        for item in answer.checklist where item.recurrence_days != nil {
            guard let tickedAt = untimedTicks[item.id], checklistState[item.id] == .flag(true) else { continue }
            checklistState[item.id] = .completed(tickedAt)
            pendingRecurring[item.id] = true
            dated = true
        }
        guard dated else { return }
        stateStore.save(checklistState, homeID: homeID)
        rescore(api: api)
    }

    /// Stops the in-flight request counting. It changes no score and shows no failure.
    private func cancelScoreFetch() {
        refreshTask?.cancel()
        refreshTask = nil
        scoreGeneration += 1
        isScoring = false
    }

    private func clearScoreForDraft() {
        cancelScoreFetch()
        if let id = activeHome?.id {
            seenAsDraft.insert(id)
            // A score cached for a guessed floor plan by a build before AUD-023 was fixed.
            (try? ScoreCache())?.remove(homeID: id)
        }
        scored = nil
        scoreFailure = nil
    }

    // MARK: - Done state

    /// Flips a narrative item and re-scores. Done gets the firmer tick, undone a quiet notch.
    /// Only an item of the checklist on screen, which `items` guarantees is the active home's, so
    /// an item id from another home's score is never saved into this home's state (AUD-014).
    /// Ids the backend gives every home alike (`practice.meeting_point`) cannot be told apart
    /// here: that needs the row to pass its home id (BLOCKERS, S11.23 findings).
    func toggleDone(_ item: ChecklistItem, api: APIClient, animated: Bool = true) {
        guard let activeHomeID, items.contains(where: { $0.id == item.id }) else { return }
        let newDone = !isDone(item)
        let recurs = item.recurrence_days != nil
        // A recurring item records WHEN it was done, so the server can tell when it lapses (S11.35).
        let mark: ChecklistMark = newDone && recurs ? .completed(now()) : .flag(newDone)
        withAnimation(animated ? .snappy(duration: 0.22) : nil) {
            checklistState[item.id] = mark
            if recurs { pendingRecurring[item.id] = newDone }
        }
        // Whether it really recurs may not be known yet (an old cached score): remember when.
        if !recurs { untimedTicks[item.id] = newDone ? now() : nil }
        stateStore.save(checklistState, homeID: activeHomeID)
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

// MARK: - Score band colours

extension ScoreBand {
    /// Fill colour (gauge, bar, pill dot), held to the 3:1 non-text floor on every surface.
    var tint: Color {
        switch self {
        case .wellPrepared: return Theme.success
        case .someGaps: return Theme.caution
        case .needsWork: return Theme.warning
        }
    }

    /// Text colour for the band's words and numbers. The three state colours clear 4.5:1 on
    /// every dark surface (ThemeContrastTests), so today this is `tint`; it stays a separate
    /// name so a future fill that fails text contrast has somewhere to diverge.
    var textTint: Color { tint }
}

// MARK: - Where a task takes you

/// What completing a checklist item means: look at something in the 3D house, run a drill, or
/// just tick it off here. Engine-scored spatial items are decided by the model, so they go to
/// the house; narrative items are the user's word and toggle in place.
///
/// The drill item is the user's word too (trim 2, 2026-10-03): the practice log that ticked it is
/// gone, so it ticks like any manual item, and its button opens House's fire simulation. Nothing
/// ticks it automatically; it is `scoring=False`, so the score never moves either way.
enum TaskDestination {
    case house, drill, toggle

    /// Whether the user ticks this item by hand (the row's circle is a button). House items are
    /// decided by the engine's audit of the model, so they are not.
    var isTickedByUser: Bool { self != .house }

    init(_ item: ChecklistItem) {
        switch item.category {
        // Only the drill item opens the drill (House's fire simulation). The meeting point and
        // "re-scan your home" are practice items too, but a drill does neither (the re-scan review
        // was cut 2026-10-02), so they only tick off here.
        case .practice: self = item.id == "practice.drill_recent" ? .drill : .toggle
        // The alarm test is the user's word: nothing in the model can say a button was pressed
        // (S11.35, owner 2026-10-04). It stopped recurring on 2026-10-05 and is still ticked
        // here, so it is named; any other smoke-alarm item the server says recurs ticks too.
        case .smoke_alarm: self = item.recurrence_days != nil || item.isFormerlyRecurring ? .toggle : .house
        case .routes, .egress, .agent_finding, .recommendation: self = .house
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

    /// The short form for a row chip, so the chip never squeezes the task title onto three lines.
    var shortLabel: String {
        switch self {
        case .severe_weather: return "Weather"
        default: return label
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
