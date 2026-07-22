//  PlanScreen.swift
//  escape_plan
//
//  Real read-only 3D dollhouse view of a saved home, with the S2.3 route overlay on top:
//  animated primary/secondary escape paths fetched from the backend /routes endpoint
//  (the deterministic engine — routes are NEVER computed client-side), a camera tour along
//  the primary route, and warning badges for rooms the engine flags.

import SceneKit
import SwiftUI

struct PlanScreen: View {
    @Environment(APIClient.self) private var apiClient
    @StateObject private var library: HomeLibrary
    @State private var selectedHomeID: String?
    @State private var built: DollhouseSceneBuilder.Result?
    @State private var loadError: String?
    @State private var explode: Double = 0
    @State private var hiddenFloorIDs: Set<String> = []

    // S2.3 route overlay state.
    @State private var homeModel: HomeModel?
    @State private var routePlan: RoutePlan?
    @State private var routesError: String?
    @State private var isFetchingRoutes = false
    /// nil = "Everyone": primary routes + badges for the whole house.
    @State private var selectedRoomID: String?
    /// S3.4 integration: nil means the whole-house plan with no profile constraints. Changing
    /// it re-fetches from the engine — the app never re-derives a route for a profile itself.
    @State private var selectedProfileID: String?
    @State private var overlay: RouteOverlay?
    @State private var overlayIssues: [String] = []
    @State private var isTouring = false
    @State private var routesTask: Task<Void, Never>?
    @State private var sceneView: SCNView?

    init() {
        _library = StateObject(wrappedValue: HomeLibrary(store: try! HomeDocumentStore()))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Escape Plan")
                .toolbar {
                    if library.homes.count > 1 {
                        ToolbarItem(placement: .principal) {
                            Picker("Home", selection: Binding(
                                get: { selectedHomeID ?? library.homes.first?.id },
                                set: { selectedHomeID = $0 }
                            )) {
                                ForEach(library.homes) { home in
                                    Text(home.name).tag(Optional(home.id))
                                }
                            }
                        }
                    }
                }
        }
        .task { library.refresh() }
        .onChange(of: library.homes) { _, homes in
            if selectedHomeID == nil { selectedHomeID = homes.first?.id }
            reload()
        }
        .onChange(of: selectedHomeID) { _, _ in reload() }
        .onDisappear { routesTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if library.homes.isEmpty {
            ContentUnavailableView(
                "No home to show",
                systemImage: "figure.run",
                description: Text("Build a home in the Editor tab first.")
            )
        } else if let error = loadError {
            ContentUnavailableView("Couldn't render home", systemImage: "exclamationmark.triangle",
                                    description: Text(error))
        } else if let built {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    DollhouseSceneView(
                        dollhouse: built.dollhouse,
                        explode: explode,
                        hiddenFloorIDs: hiddenFloorIDs,
                        wantsContinuousRendering: routePlan != nil,
                        isTouring: isTouring,
                        onViewReady: { sceneView = $0 }
                    )
                    .ignoresSafeArea(edges: .bottom)
                    routesBanner
                }
                controls(for: built)
            }
        } else {
            ProgressView("Loading…")
        }
    }

    /// Non-blocking status strip over the scene: the dollhouse stays fully interactive while
    /// routes are fetched (Render free-tier cold starts can take ~30 s) or after a failure.
    @ViewBuilder
    private var routesBanner: some View {
        if isFetchingRoutes {
            HStack(spacing: 8) {
                ProgressView()
                Text("Planning routes… the first request can take ~30 s while the server wakes.")
                    .font(.caption)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        } else if let routesError {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                Text(routesError).font(.caption)
                Button("Retry") { fetchRoutes() }
                    .font(.caption.bold())
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func controls(for built: DollhouseSceneBuilder.Result) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let floors = built.dollhouse.floors
            if floors.count > 1 {
                Text("Exploded view").font(.caption).foregroundStyle(.secondary)
                Slider(value: $explode, in: 0...1)
                    .disabled(isTouring)
                HStack {
                    ForEach(floors.reversed(), id: \.id) { floor in
                        Toggle(floor.name, isOn: binding(for: floor.id))
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .disabled(isTouring)
                    }
                }
            }
            if let routePlan {
                routeControls(for: routePlan)
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func routeControls(for plan: RoutePlan) -> some View {
        // S3.4 integration: picking a family member re-runs the engine with that profile's
        // constraints (tags → constraints happens server-side) and jumps to their bedroom, so
        // the rendered route updates live. The client sends profile_id and nothing else.
        if let homeModel, !homeModel.profiles.isEmpty {
            Picker("Who", selection: $selectedProfileID) {
                Text("Everyone").tag(String?.none)
                ForEach(homeModel.profiles) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            .pickerStyle(.segmented)
            .disabled(isTouring || isFetchingRoutes)
            .onChange(of: selectedProfileID) { _, newValue in
                selectedRoomID = newValue.flatMap { id in
                    homeModel.profiles.first { $0.id == id }?.bedroom_room_id
                }
                fetchRoutes()
            }
        }

        HStack {
            Picker("Route", selection: $selectedRoomID) {
                Text("Everyone").tag(String?.none)
                ForEach(plan.rooms) { room in
                    Text(room.room_name).tag(Optional(room.room_id))
                }
            }
            .disabled(isTouring)
            .onChange(of: selectedRoomID) { _, _ in applyOverlay() }

            Spacer()

            if let room = selectedRoom(in: plan), let primary = room.primary {
                Button {
                    isTouring ? stopTour() : startTour(along: primary)
                } label: {
                    Label(isTouring ? "Stop" : "Tour",
                          systemImage: isTouring ? "stop.circle" : "play.circle")
                }
                .buttonStyle(.borderedProminent)
            } else if selectedRoomID == nil {
                Text("Pick a room to tour").font(.caption2).foregroundStyle(.secondary)
            }
        }

        let findings = shownFindings(in: plan)
        if !findings.isEmpty {
            // Warning text comes verbatim from the engine's findings — the app never writes
            // its own safety judgments.
            ForEach(findings.indices, id: \.self) { i in
                Label(findings[i].detail, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(DollhousePalette.warningBadge))
            }
        }
        if !overlayIssues.isEmpty {
            Text("Some routes couldn't be drawn — see the log for details.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for floorID: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenFloorIDs.contains(floorID) },
            set: { visible in
                if visible { hiddenFloorIDs.remove(floorID) } else { hiddenFloorIDs.insert(floorID) }
            }
        )
    }

    // MARK: - Loading

    private func reload() {
        routesTask?.cancel()
        overlay?.cancelTour()
        isTouring = false
        guard let homeID = selectedHomeID ?? library.homes.first?.id else {
            built = nil
            homeModel = nil
            return
        }
        do {
            let model = try library.store.load(homeID: homeID, as: HomeModel.self)
            built = DollhouseSceneBuilder.build(model)
            homeModel = model
            overlay = built.map { RouteOverlay(dollhouse: $0.dollhouse) }
            loadError = nil
            explode = 0
            hiddenFloorIDs = []
            routePlan = nil
            selectedRoomID = nil
            selectedProfileID = nil
            overlayIssues = []
            fetchRoutes()
        } catch {
            loadError = "\(error)"
            built = nil
            homeModel = nil
        }
    }

    // MARK: - Routes (S2.3)

    private func fetchRoutes() {
        routesTask?.cancel()
        guard let homeModel else { return }
        routesError = nil
        isFetchingRoutes = true
        routesTask = Task {
            defer { isFetchingRoutes = false }
            do {
                let plan = try await apiClient.fetchRoutes(home: homeModel,
                                                          profileID: selectedProfileID)
                guard !Task.isCancelled, plan.home_id == homeModel.home_id else { return }
                routePlan = plan
                applyOverlay()
            } catch is CancellationError {
            } catch APIClientError.unexpectedResponse(let statusCode) where statusCode == 401 {
                routesError = "Backend rejected the request — check the bearer token in Settings."
            } catch {
                guard !Task.isCancelled else { return }
                routesError = "Couldn't fetch routes: \(error.localizedDescription)"
            }
        }
    }

    private func applyOverlay() {
        guard let overlay, let routePlan, let homeModel else { return }
        let rooms = selectedRoomID.map { id in routePlan.rooms.filter { $0.room_id == id } }
            ?? routePlan.rooms
        // "Everyone" draws primaries + badges only; both routes appear once a room is picked.
        overlayIssues = overlay.show(rooms: rooms, home: homeModel,
                                     includeSecondary: selectedRoomID != nil)
        sceneView?.setNeedsDisplay()
    }

    private func selectedRoom(in plan: RoutePlan) -> RoomRoutePlan? {
        guard let selectedRoomID else { return nil }
        return plan.rooms.first { $0.room_id == selectedRoomID }
    }

    private func shownFindings(in plan: RoutePlan) -> [RouteFinding] {
        let rooms = selectedRoomID.map { id in plan.rooms.filter { $0.room_id == id } } ?? plan.rooms
        return rooms.flatMap(\.findings)
    }

    // MARK: - Tour (S2.3)

    private func startTour(along route: Route) {
        guard let overlay, let view = sceneView else { return }
        // The tour flies the stacked house; explode/hidden floors would put the camera in
        // empty space or inside invisible geometry.
        explode = 0
        hiddenFloorIDs = []
        isTouring = true
        overlay.startTour(along: route, in: view) { isTouring = false }
    }

    private func stopTour() {
        overlay?.cancelTour()
        isTouring = false
    }
}

#Preview {
    PlanScreen()
        .environment(APIClient())
}
