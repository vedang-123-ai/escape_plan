//  DrillScreen.swift
//  escape_plan — S4.2 drill mode (guided walkthrough)
//
//  Pick a family member → walk their primary escape route waypoint-by-waypoint on the 3D
//  dollhouse, reusing the S2.3 camera tour per segment → cited instruction cards → outside
//  meeting-place card → "mark plan as practiced", which flips the S3.5 scoring checklist item
//  `practice.drill_recent` in ChecklistStateStore. The score itself is always the backend's:
//  ScoreScreen re-POSTs /score with the updated checklist state next time it appears.
//
//  Routes are server truth from /routes (fetched with profile_id — constraints are derived
//  server-side); this screen never computes, extends, or invents a route or a safety judgment.
//
//  Reached from HomeScreen: per-home leading swipe ("Drill") or context menu
//  ("Practice Drill") → `.navigationDestination(item: $drillHomeID)`, mirroring how Score and
//  Profiles are reached.
//
//  Three things layer on top of that walkthrough, all local and all offline-capable:
//
//  - a stopwatch, recorded into DrillLogStore as a DrillRecord (who, which room, when, how
//    long, completed or stopped early);
//  - a time-to-exit comparison against that person's modeled `egress_time_s` from an
//    EvacuationTimeline, framed as "how your practice compares to the modeled walk" and never
//    as a survivability judgement — and honestly absent when no timeline exists;
//  - local practice reminders, whose recommended cadence is the corpus's twice-a-year and is
//    never shown without its citation chips.

import SceneKit
import SwiftUI

struct DrillScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let homeID: String

    /// An externally supplied timeline (previews, tests, a future caller that already has one).
    /// Takes precedence over anything this screen fetches; nil is the normal case.
    var timeline: EvacuationTimeline? = nil

    @State private var homeModel: HomeModel?
    @State private var built: DollhouseSceneBuilder.Result?
    @State private var loadError: String?

    @State private var routePlan: RoutePlan?
    /// The classified backend failure. Was a bare `String`, which discarded `isRetryable` —
    /// so a 502 (an operator must act) and a 503 (busy, retry) read identically here.
    @State private var routesFailure: BackendFailure?
    /// Engine/app-level messages that are NOT transport failures ("no primary route for Ana",
    /// findings shown verbatim). Kept separate so they never borrow a network banner's wording.
    @State private var routesNotice: String?
    /// Set when the plan being walked came out of the offline cache rather than the network.
    @State private var cachedPlanDate: Date?
    @State private var isFetchingRoutes = false
    @State private var routesTask: Task<Void, Never>?

    // MARK: Fire origin (optional)

    @State private var selectedPeril = "fire"

    /// Where the fire starts, if the household chose to say. Nil is a first-class answer: the
    /// drill runs identically, and the time comparison stays honestly unavailable.
    @State private var originRoomID: String?
    @State private var fetchedTimeline: EvacuationTimeline?
    @State private var simulationFailure: BackendFailure?
    @State private var isSimulating = false
    @State private var originPickerPresented = false
    @State private var evacuateTask: Task<Void, Never>?

    /// The one legitimate source of a modeled time. There is deliberately no third branch that
    /// derives a number from `Route.length_m` and an assumed speed — that would be the app
    /// fabricating engine output, which the whole architecture exists to prevent.
    private var effectiveTimeline: EvacuationTimeline? { timeline ?? fetchedTimeline }

    @State private var overlay: RouteOverlay?
    @State private var sceneView: SCNView?
    @State private var cameraRig: OrbitCameraRig?
    @State private var session: DrillSession?
    @State private var isFlying = false
    @State private var practiced = false

    // Timing + log
    @State private var drillStartedAt: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var activeRoomID = ""
    @State private var activeRoomName = ""
    @State private var recordedOutcome: DrillOutcome?
    @State private var comparison: DrillTimeComparison?
    @State private var lastPracticed: Date?
    @State private var logError: String?
    @State private var showingLog = false
    /// nil only if Documents is unavailable; the drill still runs, it just isn't recorded.
    /// Built once in `load()` rather than per view init — SwiftUI re-inits the struct on every
    /// timer tick, and the store's init touches the filesystem.
    @State private var logStore: DrillLogStore?
    /// Cached fold of the log, refreshed on load and after each drill, so drawing the picker
    /// doesn't re-read the file for every row on every tick.
    @State private var summaries: [DrillPersonSummary] = []
    @State private var recordCount = 0

    private let stateStore = ChecklistStateStore()
    private let reminderScheduler = PracticeReminderScheduler()

    var body: some View {
        content
            .navigationTitle("Practice drill")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: load)
            .task(id: drillStartedAt) { await runTimer() }
            .onDisappear {
                routesTask?.cancel()
                evacuateTask?.cancel()
                overlay?.cancelTour()
                // Leaving mid-drill is a stopped drill, not a lost one.
                finish(outcome: .abandoned)
            }
            .sheet(isPresented: $showingLog, onDismiss: refreshLog) {
                PracticeLogView(homeID: homeID,
                                store: logStore,
                                currentProfileIDs: Set(homeModel?.profiles.map(\.id) ?? []))
            }
            .sheet(isPresented: $originPickerPresented) {
                if let homeModel { originPickerSheet(homeModel) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView("Couldn't load home", systemImage: "exclamationmark.triangle",
                                   description: Text(loadError))
        } else if let homeModel, homeModel.profiles.isEmpty {
            ContentUnavailableView(
                "No family profiles yet",
                systemImage: "person.2",
                description: Text("Add family members in Profiles first — the drill walks one person's escape route.")
            )
        } else if let built, let homeModel {
            ZStack(alignment: .bottom) {
                UnifiedSceneView(
                    dollhouse: built.dollhouse,
                    home: homeModel,
                    hiddenFloorIDs: [],
                    // The tour flies the whole stacked house, so leave the builder's default
                    // focus alone rather than ghosting the floors the camera flies through.
                    activeFloorID: nil,
                    wantsContinuousRendering: routePlan != nil,
                    isTouring: isFlying,
                    onViewReady: { view, rig in
                        sceneView = view
                        cameraRig = rig
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                // A ScrollView, not a fixed-height stack: at the largest accessibility text
                // sizes these cards are taller than the screen and must scroll, not clip.
                ScrollView {
                    VStack(spacing: 10) {
                        statusBanner
                        if let session {
                            drillCard(for: session)
                        } else {
                            perilPicker
                            profilePicker(homeModel)
                            if selectedPeril == "fire" {
                                fireOriginSection(homeModel)
                            }
                            practiceSection(homeModel)
                        }
                    }
                    .padding()
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        } else {
            ProgressView("Loading…")
        }
    }

    // MARK: - Peril picking

    @ViewBuilder
    private var perilPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are you practicing?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    DSPill(title: "Fire", isSelected: selectedPeril == "fire") {
                        selectedPeril = "fire"
                    }
                    DSPill(title: "Earthquake", isSelected: selectedPeril == "earthquake") {
                        selectedPeril = "earthquake"
                    }
                    DSPill(title: "Severe Weather", isSelected: selectedPeril == "tornado") {
                        selectedPeril = "tornado"
                    }
                }
            }
        }
        .dsCard()
    }

    // MARK: - Profile picking

    @ViewBuilder
    private func profilePicker(_ home: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who is practicing?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("The drill walks that person's primary route from their bedroom to an exit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(home.profiles) { profile in
                Button {
                    beginDrill(for: profile)
                } label: {
                    HStack {
                        Text(profile.name).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if !profile.tags.isEmpty {
                            Text(profile.tags.map(\.displayName).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isFetchingRoutes)
                .accessibilityLabel("Practice with \(profile.name)")
                .accessibilityValue(profileAccessibilityValue(profile))
                .accessibilityHint("Starts a timed drill along \(profile.name)'s primary escape route")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func profileAccessibilityValue(_ profile: Profile) -> String {
        var parts: [String] = []
        if !profile.tags.isEmpty {
            parts.append(profile.tags.map(\.displayName).joined(separator: ", "))
        }
        if let summary = summaries.first(where: { $0.profileID == profile.id }) {
            if let best = summary.best {
                parts.append("best drill "
                             + DrillTimeComparison.spokenDuration(best.elapsedSeconds))
            }
            parts.append("last practised \(PracticeLogView.dateText(summary.mostRecent.startedAt))")
        } else {
            parts.append("no drills recorded yet")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Fire origin (optional, and optional on purpose)

    /// The step that makes the time-to-exit comparison possible at all.
    ///
    /// `/evacuate` needs to know where the fire starts before the engine can time anyone's
    /// escape, and nothing in the drill knew that — which is why the comparison always showed
    /// its "unavailable" branch. Asking is the only honest way to get the number: the
    /// alternative considered (dividing `Route.length_m` by an assumed walking speed) would be
    /// the app inventing engine output.
    ///
    /// Everything here is skippable. Skipped, offline, or failed, the drill runs exactly as it
    /// did before and the comparison says plainly that there is nothing to compare against.
    @ViewBuilder
    private func fireOriginSection(_ home: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where does the fire start? (optional)")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Pick a room and the engine works out how long the walk out takes with the "
                 + "fire there. Skip it and the drill still runs — you just won't get a "
                 + "modeled time to compare your practice against.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isSimulating {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Working out the modeled walk from \(originRoomName)…")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            } else if effectiveTimeline != nil {
                Label("Modeled from a fire starting in \(originRoomName).",
                      systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Modeled from a fire starting in \(originRoomName). "
                                        + "Your practice will be compared against it.")
            }

            if let simulationFailure {
                BackendFailureBanner(
                    failure: simulationFailure,
                    retry: simulationFailure.isRetryable
                        ? { originRoomID.map { fetchTimeline(originRoomID: $0) } }
                        : nil
                )
                if simulationFailure.isOfflineFlavoured {
                    OfflineCapabilityNote()
                }
                Text("The drill itself doesn't need this — you can start walking the route now.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Two buttons never share a line at accessibility text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { originButtons }
                VStack(alignment: .leading, spacing: 8) { originButtons }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var originButtons: some View {
        Button {
            originPickerPresented = true
        } label: {
            Label(originRoomID == nil ? "Choose a room…" : "Change room",
                  systemImage: "flame")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .disabled(isSimulating)
        .minimumTapTarget()
        .accessibilityLabel(originRoomID == nil
                            ? "Choose the room the fire starts in"
                            : "Change the room the fire starts in")
        .accessibilityValue(originRoomID == nil ? "Not set" : originRoomName)
        .accessibilityHint("Opens a list of every room in this home. Optional — the drill "
                           + "works without it.")
        .accessibilityIdentifier("drill.origin.choose")

        if originRoomID != nil {
            Button("Skip this") { clearOrigin() }
                .buttonStyle(.bordered)
                .disabled(isSimulating)
                .minimumTapTarget()
                .accessibilityLabel("Skip the fire-origin step")
                .accessibilityHint("Clears the room and runs the drill without a modeled time "
                                   + "to compare against.")
                .accessibilityIdentifier("drill.origin.skip")
        }
    }

    /// Falls back to the timeline's own `origin_room_id` so an injected timeline still names
    /// its assumption rather than saying "the chosen room".
    private var originRoomName: String {
        guard let id = originRoomID ?? effectiveTimeline?.origin_room_id else {
            return "the chosen room"
        }
        return homeModel?.locateRoom(id)?.room.name ?? id
    }

    /// A plain list, grouped by floor — the same accessible pattern HouseScreen's ignition
    /// picker uses, and the only one that works for someone who can't hit a room in a 3D scene.
    @ViewBuilder
    private func originPickerSheet(_ home: HomeModel) -> some View {
        NavigationStack {
            List {
                ForEach(home.floorsByLevel) { floor in
                    Section(floor.name.isEmpty ? "Level \(floor.level)" : floor.name) {
                        ForEach(floor.rooms) { room in
                            Button {
                                originPickerPresented = false
                                originRoomID = room.id
                                fetchTimeline(originRoomID: room.id)
                            } label: {
                                Label(room.name, systemImage: "flame")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityLabel("Start the fire in \(room.name)")
                            .accessibilityHint("Asks the engine to time everyone's walk out "
                                               + "with the fire in this room.")
                        }
                    }
                }
            }
            .navigationTitle("Start the fire in…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { originPickerPresented = false }
                        .accessibilityHint("Closes without setting a fire origin.")
                }
            }
        }
    }

    /// POST /evacuate. There is no offline path and no client-side substitute on purpose —
    /// failing honestly through `BackendFailure` is the whole point. The drill is unaffected
    /// either way, which the banner says out loud.
    private func fetchTimeline(originRoomID roomID: String) {
        guard let homeModel else { return }
        evacuateTask?.cancel()
        simulationFailure = nil
        fetchedTimeline = nil
        isSimulating = true
        evacuateTask = Task {
            defer { isSimulating = false }
            do {
                let result = try await apiClient.evacuate(home: homeModel, originRoomID: roomID)
                guard !Task.isCancelled else { return }
                // A timeline for a different home would time a walk through another house.
                guard result.home_id == homeModel.home_id else { return }
                fetchedTimeline = result
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                simulationFailure = BackendFailure(error, while: .simulation)
            }
        }
    }

    private func clearOrigin() {
        evacuateTask?.cancel()
        isSimulating = false
        originRoomID = nil
        fetchedTimeline = nil
        simulationFailure = nil
    }

    // MARK: - Practice log + reminders (shown between drills)

    @ViewBuilder
    private func practiceSection(_ home: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DrillTimeComparison.lastPracticedPhrase(lastPracticed))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if let logError {
                Label(logError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                showingLog = true
            } label: {
                Label("Practice log", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Practice log")
            .accessibilityValue(logCountValue)
            .accessibilityHint("Opens the list of drills this household has run")

            Divider()

            PracticeReminderCard(homeID: homeID,
                                 homeName: home.name,
                                 lastPracticed: lastPracticed,
                                 scheduler: reminderScheduler)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var logCountValue: String {
        recordCount == 0 ? "No drills recorded"
            : "\(recordCount) drill\(recordCount == 1 ? "" : "s") recorded"
    }

    /// Re-reads the log's derived views. Cheap (one file) and only called on load / after a
    /// drill / after the log sheet closes.
    private func refreshLog() {
        guard let logStore else { return }
        let records = logStore.records(homeID: homeID)
        recordCount = records.count
        lastPracticed = records.first?.startedAt
        summaries = logStore.summaries(homeID: homeID)
    }

    // MARK: - Drill card

    @ViewBuilder
    private func drillCard(for session: DrillSession) -> some View {
        let card = DrillInstructions.card(for: session.currentStep,
                                          profileName: session.profile.name)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Step \(session.stepNumber) of \(session.stepCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Step \(session.stepNumber) of \(session.stepCount)")
            }

            timerRow

            // Copy is shown verbatim — inline [cite:] tags stay visible (grounding is the
            // feature), with the ids echoed as chips, like AssistantScreen.
            DrillCitedText(text: card.body)

            if case .drillComplete = session.currentStep {
                comparisonCard
                meetingPointActions
            }

            drillControls(for: session)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The running stopwatch. `.updatesFrequently` tells VoiceOver this value changes on its
    /// own, so it isn't re-read every tick; the value is spoken as words rather than "one
    /// colon zero five".
    @ViewBuilder
    private var timerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "stopwatch").font(.caption)
            Text(DrillTimeComparison.clockString(elapsed))
                .font(.title3.monospacedDigit())
            if drillStartedAt == nil, recordedOutcome != nil {
                Text("· stopped").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drill timer")
        .accessibilityValue(DrillTimeComparison.spokenDuration(elapsed))
        .accessibilityAddTraits(drillStartedAt == nil ? [] : .updatesFrequently)
    }

    @ViewBuilder
    private func drillControls(for session: DrillSession) -> some View {
        // Three buttons never fit on one line at accessibility text sizes; ViewThatFits
        // drops them into a column instead of truncating the labels.
        ViewThatFits(in: .horizontal) {
            HStack { controlButtons(for: session) }
            VStack(alignment: .leading, spacing: 8) { controlButtons(for: session) }
        }
    }

    @ViewBuilder
    private func controlButtons(for session: DrillSession) -> some View {
        Button("Back") { stepBack() }
            .buttonStyle(.bordered)
            .disabled(session.isAtStart || isFlying)
            .accessibilityHint("Goes back to the previous drill step")
        Spacer(minLength: 0)
        Button(session.isAtEnd ? "Done" : "Exit drill") { endDrill() }
            .buttonStyle(.bordered)
            .disabled(isFlying)
            .accessibilityHint(session.isAtEnd
                               ? "Closes the drill and returns to the list of people"
                               : "Stops the drill early. It is still recorded in the practice log")
        Spacer(minLength: 0)
        if !session.isAtEnd {
            Button {
                stepForward()
            } label: {
                Label("Next", systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isFlying)
            .accessibilityHint("Moves to the next step of the escape route")
        }
    }

    /// How the practice compares to the modeled walk. Never a verdict, never a survivability
    /// claim, and never a fabricated number when no timeline exists.
    @ViewBuilder
    private var comparisonCard: some View {
        if let comparison {
            VStack(alignment: .leading, spacing: 6) {
                Text(comparison.headline)
                    .font(.subheadline.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                Text(comparison.detail)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let disclaimer = comparison.disclaimer {
                    Text(disclaimer)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if comparison.isAvailable, effectiveTimeline != nil {
                    // Names the assumption the modeled number rests on. A time computed for a
                    // fire in the kitchen is not a time for a fire anywhere else, and the card
                    // must not let that read as a general result.
                    Text("Modeled with the fire starting in \(originRoomName).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !comparison.isAvailable {
                    Text("Pick where the fire starts before a drill and the engine can work "
                         + "out a modeled walk to compare against.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DrillCitedText(text: DrillInstructions.drillTimerGoal, font: .caption2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Time to exit")
        }
    }

    @ViewBuilder
    private var meetingPointActions: some View {
        if practiced {
            Label("Plan practiced — your preparedness score updates on the Score screen.",
                  systemImage: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button {
                markPracticed()
            } label: {
                Label("Mark plan as practiced", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Records this plan as practised for your preparedness score")
        }
    }

    // MARK: - Status / errors

    @ViewBuilder
    private var statusBanner: some View {
        if isFetchingRoutes {
            HStack(spacing: 8) {
                ProgressView()
                Text("Getting the escape route ready… the first time can take about 30 seconds.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        } else {
            if let routesFailure {
                // One classifier, one banner. Retry appears only when retrying can work.
                VStack(alignment: .leading, spacing: 8) {
                    BackendFailureBanner(
                        failure: routesFailure,
                        retry: routesFailure.isRetryable ? { retryRoutes() } : nil
                    )
                    if routesFailure.isOfflineFlavoured {
                        OfflineCapabilityNote()
                    }
                }
                .accessibilityIdentifier("drill.routesFailure")
            }
            if let routesNotice {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(routesNotice)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(routesNotice)
            }
        }
    }

    /// The profile whose route we last tried to fetch, so the banner's Retry has something to
    /// retry. Cleared when a drill starts.
    @State private var lastRequestedProfile: Profile?

    private func retryRoutes() {
        guard let profile = lastRequestedProfile else { return }
        beginDrill(for: profile)
    }

    // MARK: - Loading

    private func load() {
        // onAppear re-fires on tab switches; rebuilding would replace the overlay a live
        // drill session is drawn on. Load once per push.
        guard homeModel == nil else { return }
        do {
            let model = try HomeDocumentStore().load(homeID: homeID, as: HomeModel.self)
            homeModel = model
            built = DollhouseSceneBuilder.build(model)
            overlay = built.map { RouteOverlay(dollhouse: $0.dollhouse) }
            practiced = stateStore.load(homeID: homeID)["practice.drill_recent"] == true
            logStore = try? DrillLogStore()
            if logStore == nil {
                logError = "Drills can't be saved on this device right now — the timer still works."
            }
            refreshLog()
        } catch {
            loadError = "\(error)"
        }
    }

    // MARK: - Timing

    /// Ticks once a second while a drill is running. Keyed on `drillStartedAt`, so clearing it
    /// cancels the loop; the recorded elapsed time is measured from the dates, not from ticks.
    private func runTimer() async {
        guard let start = drillStartedAt else { return }
        while !Task.isCancelled {
            elapsed = Date().timeIntervalSince(start)
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Drill flow

    /// Fetches the route to walk, degrading to the last-good cached plan exactly as HouseScreen
    /// does — this screen was calling the uncached `fetchRoutes` and dead-ending offline, even
    /// though everything else about a drill (the stopwatch, the log, the reminders) is local.
    ///
    /// The fallback is connection-class only. A 401 or a 422 still surfaces: silently walking a
    /// stale plan when the token is wrong would hide a configuration problem behind a drill
    /// that looks like it worked.
    private func beginDrill(for profile: Profile) {
        guard let homeModel else { return }
        routesTask?.cancel()
        routesFailure = nil
        routesNotice = nil
        cachedPlanDate = nil
        lastRequestedProfile = profile
        isFetchingRoutes = true
        routesTask = Task {
            defer { isFetchingRoutes = false }
            do {
                let result = try await apiClient.fetchRoutesCached(home: homeModel,
                                                                   peril: selectedPeril,
                                                                   profileID: profile.id)
                guard !Task.isCancelled else { return }
                let plan: RoutePlan
                switch result {
                case .live(let live):
                    plan = live
                case .cached(let cached):
                    plan = cached.plan
                    cachedPlanDate = cached.savedAt
                    routesFailure = .showingCachedRoutes(savedAt: cached.savedAt)
                }
                guard plan.home_id == homeModel.home_id else {
                    routesNotice = "The saved plan is for a different home — try again online."
                    return
                }
                routePlan = plan
                start(profile: profile, plan: plan)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                // Shared classifier: this screen's own 401 ladder said the same thing as
                // HouseScreen's but drifted on everything else, including 502 vs 503.
                routesFailure = BackendFailure(error, while: .routes)
            }
        }
    }

    private func start(profile: Profile, plan: RoutePlan) {
        guard let homeModel, let overlay else { return }
        guard let room = plan.rooms.first(where: { $0.room_id == profile.bedroom_room_id }) else {
            routesNotice = "The engine returned no plan for \(profile.name)'s bedroom."
            return
        }
        if plan.peril == "tornado", let finding = room.findings.first(where: { $0.kind == .no_viable_safe_room }) {
            routesNotice = "\(finding.detail) Leave immediately and seek shelter in a nearby sturdy building. [cite: redcross-tornado]"
            return
        }
        guard let primary = room.primary else {
            // Findings are the engine's words, shown verbatim — the app never writes its own
            // safety judgments.
            let detail = room.findings.first.map { " \($0.detail)" } ?? ""
            routesNotice = "No primary route for \(profile.name).\(detail)"
            return
        }
        
        let coverObjectName = room.cover_object_id.flatMap { id in
            homeModel.floors.flatMap(\.objects).first(where: { $0.id == id })?.category.rawValue
        }
        let noCoverFinding = room.findings.first(where: { $0.kind == .no_cover_in_room })?.detail

        guard let drill = DrillSession(profile: profile, route: primary,
                                       startRoomName: room.room_name,
                                       peril: plan.peril ?? "fire",
                                       coverObjectName: coverObjectName,
                                       noCoverFinding: noCoverFinding) else {
            routesNotice = "The route for \(profile.name) is too short to walk through."
            return
        }
        overlay.show(rooms: [room], home: homeModel, includeSecondary: false)
        sceneView?.setNeedsDisplay()
        session = drill
        activeRoomID = room.room_id
        activeRoomName = room.room_name
        comparison = nil
        recordedOutcome = nil
        logError = nil
        elapsed = 0
        drillStartedAt = Date()
        Haptics.begin()
    }

    private func stepForward() {
        guard var updated = session else { return }
        updated.advance()
        session = updated
        Haptics.tick()
        if updated.isAtEnd {
            finish(outcome: .completed)
            return
        }
        if case .move(let segment, _) = updated.currentStep,
           let overlay, let view = sceneView {
            // Reduce Motion: the drill still steps, the route stays highlighted and the card
            // still advances — only the swooping camera flight is dropped. Stepped, not
            // disabled.
            guard !reduceMotion else { return }
            isFlying = true
            overlay.startTour(along: segment, in: view, restoreTo: cameraRig?.node) { isFlying = false }
        }
    }

    private func stepBack() {
        guard var updated = session else { return }
        updated.back()
        session = updated
    }

    private func endDrill() {
        overlay?.cancelTour()
        isFlying = false
        overlay?.clear()
        sceneView?.setNeedsDisplay()
        finish(outcome: .abandoned)
        session = nil
        comparison = nil
        routesNotice = nil
        routePlan = nil // back to a static scene — stop continuous rendering
    }

    /// Records the drill exactly once. `.abandoned` calls after a `.completed` one are no-ops,
    /// so leaving the screen after finishing doesn't downgrade the record.
    private func finish(outcome: DrillOutcome, now: Date = Date()) {
        guard recordedOutcome == nil, let start = drillStartedAt, let session else { return }
        let seconds = now.timeIntervalSince(start)
        elapsed = seconds
        drillStartedAt = nil // stops the ticker
        recordedOutcome = outcome

        let modeled = DrillTimeComparison.modeledEgressSeconds(forProfileID: session.profile.id,
                                                              in: effectiveTimeline)
        let record = DrillRecord(homeID: homeID,
                                 roomID: activeRoomID,
                                 roomName: activeRoomName,
                                 profileID: session.profile.id,
                                 profileName: session.profile.name,
                                 startedAt: start,
                                 elapsedSeconds: seconds,
                                 outcome: outcome,
                                 modeledEgressSeconds: modeled)
        do {
            try logStore?.append(record)
            refreshLog()
            if lastPracticed == nil { lastPracticed = start }
        } catch {
            logError = "This drill couldn't be saved to the practice log."
        }

        guard outcome == .completed else { return }
        let result = DrillTimeComparison(elapsed: seconds, modeled: modeled,
                                         personName: session.profile.name,
                                         peril: session.peril)
        comparison = result
        AccessibilityNotification.Announcement(result.accessibilitySummary).post()
        if let homeModel {
            let practicedAt = lastPracticed
            let name = homeModel.name
            Task {
                await reminderScheduler.reschedule(homeID: homeID, homeName: name,
                                                   lastPracticed: practicedAt)
            }
        }
    }

    private func markPracticed() {
        var state = stateStore.load(homeID: homeID)
        state["practice.drill_recent"] = true
        stateStore.save(state, homeID: homeID)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4)) {
            practiced = true
        }
        Haptics.success()
    }
}

#Preview {
    NavigationStack {
        DrillScreen(homeID: "preview")
    }
    .environment(APIClient())
}
