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

import SceneKit
import SwiftUI

struct DrillScreen: View {
    @Environment(APIClient.self) private var apiClient
    let homeID: String

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

    private let stateStore = ChecklistStateStore()

    var body: some View {
        content
            .navigationTitle("Practice drill")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: load)
            .onDisappear {
                routesTask?.cancel()
                overlay?.cancelTour()
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
                    explode: 0,               // tour flies the stacked house — never exploded
                    hiddenFloorIDs: [],
                    wantsContinuousRendering: routePlan != nil,
                    isTouring: isFlying,
                    onViewReady: { view, rig in
                        sceneView = view
                        cameraRig = rig
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    statusBanner
                    if let session {
                        drillCard(for: session)
                    } else {
                        profilePicker(homeModel)
                    }
                }
                .padding()
            }
        } else {
            ProgressView("Loading…")
        }
    }

    // MARK: - Profile picking

    @ViewBuilder
    private func profilePicker(_ home: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who is practicing?").font(.headline)
            Text("The drill walks that person's primary route from their bedroom to an exit.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(home.profiles) { profile in
                Button {
                    beginDrill(for: profile)
                } label: {
                    HStack {
                        Text(profile.name)
                        Spacer()
                        if !profile.tags.isEmpty {
                            Text(profile.tags.map(\.rawValue).joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isFetchingRoutes)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Drill card

    @ViewBuilder
    private func drillCard(for session: DrillSession) -> some View {
        let card = DrillInstructions.card(for: session.currentStep,
                                          profileName: session.profile.name)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.title).font(.headline)
                Spacer()
                Text("Step \(session.stepNumber) of \(session.stepCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Copy is shown verbatim — inline [cite:] tags stay visible (grounding is the
            // feature), with the ids echoed as chips, like AssistantScreen.
            Text(card.body).font(.subheadline)
            if !card.citations.isEmpty {
                citationChips(card.citations)
            }

            if case .meetingPoint = session.currentStep {
                meetingPointActions
            }

            HStack {
                Button("Back") { stepBack() }
                    .buttonStyle(.bordered)
                    .disabled(session.isAtStart || isFlying)
                Spacer()
                Button("Exit drill") { endDrill() }
                    .buttonStyle(.bordered)
                    .disabled(isFlying)
                Spacer()
                if !session.isAtEnd {
                    Button {
                        stepForward()
                    } label: {
                        Label("Next", systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFlying)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var meetingPointActions: some View {
        if practiced {
            Label("Plan practiced — your preparedness score updates on the Score screen.",
                  systemImage: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        } else {
            Button {
                markPracticed()
            } label: {
                Label("Mark plan as practiced", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func citationChips(_ ids: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    Text(id)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }
            }
        }
        .accessibilityLabel("Citations: \(ids.joined(separator: ", "))")
    }

    // MARK: - Status / errors

    @ViewBuilder
    private var statusBanner: some View {
        if isFetchingRoutes {
            HStack(spacing: 8) {
                ProgressView()
                Text("Planning routes… the first request can take ~30 s while the server wakes.")
                    .font(.caption)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        } else if let routesError {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                Text(routesError).font(.caption)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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
        } catch {
            loadError = "\(error)"
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
            } catch APIClientError.unexpectedResponse(let statusCode) where statusCode == 401 {
                routesError = "Backend rejected the request — check the bearer token in Settings."
            } catch {
                guard !Task.isCancelled else { return }
                routesError = "Couldn't fetch routes: \(error.localizedDescription)"
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
    }

    private func stepForward() {
        guard var updated = session else { return }
        updated.advance()
        session = updated
        if case .move(let segment, _) = updated.currentStep,
           let overlay, let view = sceneView {
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
        session = nil
        routePlan = nil // back to a static scene — stop continuous rendering
    }

    private func markPracticed() {
        var state = stateStore.load(homeID: homeID)
        state["practice.drill_recent"] = true
        stateStore.save(state, homeID: homeID)
        practiced = true
    }
}

#Preview {
    NavigationStack {
        DrillScreen(homeID: "preview")
    }
    .environment(APIClient())
}
