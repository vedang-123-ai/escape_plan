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

    /// The engine's evacuation timeline for this home, when one has been computed. Supplies
    /// the ONLY legitimate modeled time (`OccupantTrack.egress_time_s`); nil simply means the
    /// comparison is unavailable, and the UI says so rather than deriving a number.
    var timeline: EvacuationTimeline? = nil

    @State private var homeModel: HomeModel?
    @State private var built: DollhouseSceneBuilder.Result?
    @State private var loadError: String?

    @State private var routePlan: RoutePlan?
    @State private var routesError: String?
    @State private var isFetchingRoutes = false
    @State private var routesTask: Task<Void, Never>?

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
                overlay?.cancelTour()
                // Leaving mid-drill is a stopped drill, not a lost one.
                finish(outcome: .abandoned)
            }
            .sheet(isPresented: $showingLog, onDismiss: refreshLog) {
                PracticeLogView(homeID: homeID,
                                store: logStore,
                                currentProfileIDs: Set(homeModel?.profiles.map(\.id) ?? []))
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
                            profilePicker(homeModel)
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

            if case .meetingPoint = session.currentStep {
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
        } else if let routesError {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                Text(routesError)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
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

    private func beginDrill(for profile: Profile) {
        guard let homeModel else { return }
        routesTask?.cancel()
        routesError = nil
        isFetchingRoutes = true
        routesTask = Task {
            defer { isFetchingRoutes = false }
            do {
                let plan = try await apiClient.fetchRoutes(home: homeModel,
                                                           profileID: profile.id)
                guard !Task.isCancelled else { return }
                guard plan.home_id == homeModel.home_id else {
                    routesError = "The server answered for a different home — try again."
                    return
                }
                routePlan = plan
                start(profile: profile, plan: plan)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                // Shared classifier: this screen's own 401 ladder said the same thing as
                // HouseScreen's but drifted on everything else, including 502 vs 503.
                routesError = BackendFailure(error, while: .routes).message
            }
        }
    }

    private func start(profile: Profile, plan: RoutePlan) {
        guard let homeModel, let overlay else { return }
        guard let room = plan.rooms.first(where: { $0.room_id == profile.bedroom_room_id }) else {
            routesError = "The engine returned no plan for \(profile.name)'s bedroom."
            return
        }
        guard let primary = room.primary else {
            // Findings are the engine's words, shown verbatim — the app never writes its own
            // safety judgments.
            let detail = room.findings.first.map { " \($0.detail)" } ?? ""
            routesError = "No primary route for \(profile.name).\(detail)"
            return
        }
        guard let drill = DrillSession(profile: profile, route: primary,
                                       startRoomName: room.room_name) else {
            routesError = "The route for \(profile.name) is too short to walk through."
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
                                                              in: timeline)
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
                                         personName: session.profile.name)
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
