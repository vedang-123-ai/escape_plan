//  HouseScreen.swift
//  escape_plan
//
//  THE house screen — the revamp's unified experience. One free-orbit translucent dollhouse
//  that is simultaneously the editor (rooms, openings, stairs, undo/redo — everything the old
//  EditorScreen did) and the route viewer (animated primary/secondary escape paths fetched
//  from the backend /routes engine, camera tour, profile picker — everything the old
//  PlanScreen did). Routes are NEVER computed client-side; any accepted edit invalidates the
//  shown plan and re-fetches from the engine.
//
//  Replaces EditorScreen + PlanScreen (deleted in the same change).

import SceneKit
import SwiftUI

/// What a tap in the 3D view currently means. `.select` is the ordinary select/drag mode;
/// `.placeOpening` is armed by Add Door / Add Window and disarms after one placement.
enum EditorTool: Equatable {
    case select
    case placeOpening(OpeningKind)
}

struct HouseScreen: View {
    /// nil = start a brand-new home; otherwise open an existing saved one.
    let homeID: String?
    /// Called after the editor creates or renames a home, so the caller (HomeScreen) can
    /// refresh its list without polling.
    var onModelChanged: (() -> Void)?
    /// When the caller owns a `HomeLibrary`, the session registers as its open editor so a
    /// home deleted from the list closes this screen and drops its undo history.
    var library: HomeLibrary?

    @Environment(APIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss

    @State private var session: EditorSession?
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var addStairsSheetPresented = false
    @State private var tool: EditorTool = .select
    @State private var rejection: String?
    @State private var renameTarget: RenameTarget?
    @State private var renameDraft = ""

    // Unified-view state.
    @State private var controller: UnifiedSceneController?
    /// The focused floor ALSO lives in a stable class box: the `onRebuild` closure is captured
    /// once (at attach) and reads through a stale copy of this struct — @State reads from that
    /// copy returned the values from attach time, so every editor rebuild silently reset the
    /// view back to defaults. The box is the same fix `RouteOverlayHolder` (below) already is
    /// for the overlay: closures read the live values through the reference.
    ///
    /// The exploded-view slider and the spotlight toggle both lived here and are gone: the
    /// White Model overhaul makes floor focus intrinsic to the render (active floor solid,
    /// the rest ghosted), which answers "let me see the floor under this one" without taking
    /// the model apart or spending permanent screen space on a slider.
    @MainActor
    private final class SceneViewStateHolder {
        var activeFloorID: String?
    }
    @State private var viewStateHolder = SceneViewStateHolder()

    /// Fullscreen viewing: dock, nav bar, and tab bar step aside and the scene card goes
    /// full-bleed. Purely presentational — no model or route state depends on it.
    @State private var isImmersive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Overlay lives in a stable class box, NOT directly in @State: `onRebuild` fires inside
    /// `updateUIView`, and reassigning an @State var there invalidates the view from within
    /// its own update — an endless rebuild loop that starves gesture handling.
    @MainActor
    private final class RouteOverlayHolder {
        var overlay: RouteOverlay?
        // The draw inputs live here too, for the SECOND half of the stale-closure problem
        // (2026-07-24): `onRebuild` captures the View struct once, so reading @State from
        // inside it returns the values as of attach time — `routePlan` perpetually nil.
        // `updateUIView` rebuilds the scene to a fresh empty one on every render, so a
        // stale-self redraw left the routes permanently wiped: the "controls appear but no
        // route draws" bug. Caching the last real inputs means `redraw()` never touches @State.
        var plan: RoutePlan?
        var selectedRoomID: String?
        var model: HomeModel?

        // The household figures live under the same stale-closure discipline as the routes:
        // a rebuild replaces the scene, so the layer is re-created and re-shown from cached
        // inputs rather than from @State the closure can't see.
        var people: PeopleLayer?
        var highlightedProfileID: String?

        func redrawPeople() {
            guard let people, let model else { return }
            people.show(profiles: model.profiles, home: model,
                        highlighted: highlightedProfileID)
        }

        /// Redraw from cached inputs only — safe to call from `onRebuild`. Returns the
        /// overlay's issues.
        @discardableResult
        func redraw() -> [String] {
            guard let overlay, let plan, let model else { return [] }
            let rooms = selectedRoomID.map { id in plan.rooms.filter { $0.room_id == id } }
                ?? plan.rooms
            // "Everyone" draws primaries + badges only; both routes appear once a room is picked.
            return overlay.show(rooms: rooms, home: model,
                                includeSecondary: selectedRoomID != nil)
        }
    }

    // Route layer (server truth — S2.3 semantics preserved).
    @State private var overlayHolder = RouteOverlayHolder()
    @State private var routePlan: RoutePlan?
    @State private var routesFailure: BackendFailure?
    @State private var isFetchingRoutes = false
    @State private var cachedPlanDate: Date?
    /// nil = "Everyone": primary routes + badges for the whole house.
    @State private var selectedRoomID: String?
    @State private var selectedProfileID: String?
    @State private var overlayIssues: [String] = []
    @State private var isTouring = false
    @State private var routesTask: Task<Void, Never>?
    /// Debounces the re-fetch while the user is mid-editing-burst.
    @State private var refetchDebounce: Task<Void, Never>?

    private let documentStore: HomeDocumentStore?

    init(homeID: String?, library: HomeLibrary? = nil, onModelChanged: (() -> Void)? = nil) {
        self.homeID = homeID
        self.library = library
        self.onModelChanged = onModelChanged
        self.documentStore = try? HomeDocumentStore()
    }

    /// House tab entry point: resumes the most recently modified saved home, or starts a new
    /// one if there isn't one yet.
    init() {
        let documentStore = try? HomeDocumentStore()
        self.homeID = documentStore?.list().first?.id
        self.onModelChanged = nil
        self.library = nil
        self.documentStore = documentStore
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(session?.store.model.name ?? "House")
                .toolbar { toolbarContent }
        }
        .task { loadIfNeeded() }
        .onDisappear {
            routesTask?.cancel()
            refetchDebounce?.cancel()
            unregisterFromLibrary()
        }
        .sheet(isPresented: $addStairsSheetPresented) {
            if let session {
                addStairsSheet(for: session.store)
            }
        }
        .alert(renameTarget?.title ?? "Rename", isPresented: renameAlertPresented,
               presenting: renameTarget) { target in
            TextField("Name", text: $renameDraft)
            Button("Rename") { commitRename(target) }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView("Couldn't open home", systemImage: "exclamationmark.triangle",
                                    description: Text(error))
        } else if let session {
            let store = session.store
            // The scene sits above a FIXED-HEIGHT dock. Chrome (inspector, placement hint,
            // route controls) appears and vanishes inside the dock, so the scene view's frame
            // never changes — a mid-gesture resize would shift the world under the user's
            // finger and break any in-flight drag.
            //
            // View controls (floors, spotlight, fullscreen) DO float over the scene: they are
            // a fixed-height strip pinned to the card's top edge, so they never resize it, and
            // the region they cover is empty sky above the model in every framing the camera
            // rig produces. Immersive mode is the one place the scene's frame changes, and it
            // is user-initiated from a button — never mid-drag.
            VStack(spacing: 0) {
                sceneCard(for: session)
                if !isImmersive {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if case .placeOpening(let kind) = tool {
                                placementHint(kind: kind)
                            }
                            inspector(for: store)
                            if let rejection {
                                Text(rejection).font(.caption).foregroundStyle(Theme.caution).padding(.horizontal)
                            }
                            if let saveError {
                                Text("Autosave failed: \(saveError)").font(.caption).foregroundStyle(Theme.warning)
                                    .padding(.horizontal)
                            }
                            viewControls(for: store)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 240)
                    .background(.regularMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .toolbar(isImmersive ? .hidden : .visible, for: .navigationBar, .tabBar)
            .statusBarHidden(isImmersive)
            .onChange(of: session.wasDeletedExternally) { _, deleted in
                if deleted { dismiss() }
            }
        } else {
            ProgressView("Loading…")
        }
    }

    // MARK: - Unified-view wiring

    /// Called once per created scene view: hook the rebuild cycle so the route overlay and
    /// view state (explode, spotlight) survive the editor's rebuild-on-every-commit strategy.
    private func attach(_ controller: UnifiedSceneController) {
        self.controller = controller
        // Tapping a ghosted floor in the model focuses it — the same path the chips take, so
        // the chips and the 3D can never disagree about which floor is active.
        controller.onFloorTapped = { id in
            session?.store.setActiveFloor(id)
            focusFloor(id)
        }
        // Seed focus from the store, not from "whatever the builder opened on". Without this the
        // chips said Ground Floor while the render kept the top floor solid.
        if viewStateHolder.activeFloorID == nil {
            viewStateHolder.activeFloorID = session?.store.activeFloorId
        }
        controller.onRebuild = { dollhouse in
            // A rebuild throws away the old scene (and its route tubes), so the overlay must
            // be re-created against the NEW dollhouse and the routes redrawn — from the
            // holder's cached inputs, never from this closure's captured (stale) @State.
            overlayHolder.overlay = RouteOverlay(dollhouse: dollhouse)
            overlayHolder.people = PeopleLayer(dollhouse: dollhouse)
            applyViewState(to: dollhouse)
            overlayHolder.redraw()
            overlayHolder.redrawPeople()
        }
        if let dollhouse = controller.dollhouse {
            controller.onRebuild?(dollhouse)
        }
    }

    /// Reads through `viewStateHolder`, never the @State vars — this runs from the captured
    /// `onRebuild` closure, where @State reads are stale (see SceneViewStateHolder).
    private func applyViewState(to dollhouse: DollhouseScene) {
        guard let id = viewStateHolder.activeFloorID ?? dollhouse.floors.last?.id else { return }
        // A rebuild produces a brand-new scene, so there is nothing to animate FROM — snap.
        dollhouse.setActiveFloor(id, animated: false)
        overlayHolder.overlay?.refreshFloorFocus()
    }

    /// The one path floor focus changes through, whether it came from a chip or from a tap on
    /// the model itself — both must land in the same place or the chips and the 3D disagree.
    private func focusFloor(_ id: String) {
        viewStateHolder.activeFloorID = id
        controller?.dollhouse?.setActiveFloor(id)
        controller?.focusCamera(onFloor: id)
        overlayHolder.overlay?.refreshFloorFocus()
        controller?.scnView.setNeedsDisplay()
    }

    private func reapplyViewState() {
        guard let dollhouse = controller?.dollhouse else { return }
        applyViewState(to: dollhouse)
        controller?.scnView.setNeedsDisplay()
    }

    // MARK: - Scene card

    /// The dollhouse as a card: rounded continuous corners, its own shadow, with the view
    /// controls floating on it in glass. Going immersive squares the corners and drops the
    /// insets so the model runs to the screen edges.
    @ViewBuilder
    private func sceneCard(for session: EditorSession) -> some View {
        let store = session.store
        ZStack {
            EditorSceneView(store: store,
                            model: store.model,
                            activeFloorId: store.activeFloorId,
                            selection: store.selection,
                            tool: tool,
                            interactionEnabled: !isTouring,
                            undoStack: session.undoStack,
                            onOpeningPlaced: { tool = .select },
                            onControllerReady: { attach($0) })

            VStack(spacing: 8) {
                floatingSceneControls(for: store)
                routesBanner
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, isImmersive ? 28 : 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: isImmersive ? 0 : 26, style: .continuous))
        .shadow(color: .black.opacity(isImmersive ? 0 : 0.10), radius: 14, y: 5)
        .padding(.horizontal, isImmersive ? 0 : 12)
        .padding(.bottom, isImmersive ? 0 : 10)
        .ignoresSafeArea(edges: isImmersive ? .bottom : [])
        // Immersive keeps its controls inside the safe area (nothing tucked under the
        // Dynamic Island), so the status-bar strip is painted in the scene's own backdrop
        // instead — full-bleed to the eye, with no layout hidden behind the notch.
        .background {
            if isImmersive {
                Color(DollhousePalette.background).ignoresSafeArea()
            }
        }
    }

    /// Floor picker + spotlight + fullscreen, floating on the model's top edge. Fixed height,
    /// so it never resizes the scene underneath it.
    @ViewBuilder
    private func floatingSceneControls(for store: HomeModelStore) -> some View {
        let floors = store.model.floorsByLevel
        HStack(spacing: 8) {
            if floors.count > 1 {
                ForEach(floors) { floor in
                    let isActive = store.activeFloorId == floor.id
                    Button {
                        store.setActiveFloor(floor.id)
                        focusFloor(floor.id)
                    } label: {
                        Text(floor.name.isEmpty ? "Level \(floor.level)" : floor.name)
                    }
                    .buttonStyle(GlassChipButtonStyle(isSelected: isActive))
                    .disabled(isTouring)
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
                }

            }

            Spacer(minLength: 0)

            Button {
                controller?.recenterCamera()
            } label: {
                Image(systemName: "location.viewfinder")
            }
            .buttonStyle(GlassChipButtonStyle(isCompact: true))
            .disabled(isTouring)
            .accessibilityLabel("Recenter on the home")
            .accessibilityIdentifier("house.recenter")

            Button {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2)
                                           : .spring(response: 0.42, dampingFraction: 1.0)) {
                    isImmersive.toggle()
                }
            } label: {
                Image(systemName: isImmersive
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(GlassChipButtonStyle(isCompact: true))
            // Resizing the scene mid-tour would fight the tour camera for the frame.
            .disabled(isTouring)
            .accessibilityLabel(isImmersive ? "Exit full screen" : "View full screen")
            .accessibilityIdentifier("house.fullscreen")
        }
        .glassGroup()
    }

    // MARK: - View controls (routes)

    /// Quiet section header — the dock's wayfinding. Sentence case, secondary, no chrome.
    private func dockHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func viewControls(for store: HomeModelStore) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Floor picking lives on the model itself (floatingSceneControls) and focus is now
            // intrinsic to the render, so the dock is purely route content.
            if let routePlan {
                routeControls(for: routePlan)
            }
        }
        .padding()
        .padding(.bottom, 6)
    }

    /// Non-blocking status strip over the scene — the house stays fully interactive while
    /// routes are fetched (server cold starts can take ~30 s) or after a failure.
    @ViewBuilder
    private var routesBanner: some View {
        if needsDraftReview {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text("AI draft — review the layout, then confirm to compute escape routes.")
                    .font(.caption)
                Button("Confirm draft") {
                    dispatch(.confirmAIDraft)
                    fetchRoutes()
                }
                .font(.caption.bold())
                .accessibilityIdentifier("house.confirmDraft")
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        } else if isFetchingRoutes {
            HStack(spacing: 8) {
                ProgressView()
                Text("Planning your escape routes… the first time can take about 30 seconds "
                     + "while the server wakes up.")
                    .font(.caption)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        } else if let routesFailure {
            BackendFailureBanner(failure: routesFailure, retry: { fetchRoutes() })
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func routeControls(for plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            dockHeader("Escape routes")

            // Picking a family member re-runs the engine with that profile's constraints
            // (server-side) and jumps to their bedroom. The client sends profile_id,
            // nothing else.
            let model = session?.store.model
            if let model, !model.profiles.isEmpty {
                Picker("Who", selection: $selectedProfileID) {
                    Text("Everyone").tag(String?.none)
                    ForEach(model.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isTouring || isFetchingRoutes)
                .onChange(of: selectedProfileID) { _, newValue in
                    selectedRoomID = newValue.flatMap { id in
                        model.profiles.first { $0.id == id }?.bedroom_room_id
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
                .accessibilityIdentifier("plan.route.picker")
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
                    .accessibilityIdentifier("plan.tour.button")
                } else if selectedRoomID == nil {
                    Text("Pick a room to tour").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }

        let findings = shownFindings(in: plan)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                dockHeader("Route check")
                if !findings.isEmpty {
                    Text("\(findings.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color(DollhousePalette.warningBadge), in: Capsule())
                        .accessibilityLabel("\(findings.count) issues")
                }
            }
            if findings.isEmpty {
                RouteAllClearRow()
            } else {
                // Cards title the machine `kind`; the detail inside stays verbatim from
                // the engine — the app never writes its own safety judgments.
                ForEach(findings.indices, id: \.self) { i in
                    RouteFindingCard(finding: findings[i],
                                     roomName: roomName(for: findings[i].room_id, in: plan))
                }
            }
            if !overlayIssues.isEmpty {
                Text("Some routes couldn't be drawn on the model.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Resolve a finding's room id for its chip — plan first (already localized names),
    /// model second, raw id as the honest last resort.
    private func roomName(for roomID: String, in plan: RoutePlan) -> String {
        if let room = plan.rooms.first(where: { $0.room_id == roomID }) {
            return room.room_name
        }
        if let located = session?.store.model.locateRoom(roomID) {
            return located.room.name
        }
        return roomID
    }

    // MARK: - Routes (server truth)

    /// The review gate (revamp C2): while ANY element is an unconfirmed AI draft, routes
    /// are never fetched. The builder can only emit ai_plan elements, so this cannot be
    /// bypassed by prompt behavior — confirming in the editor is the only way through.
    private var needsDraftReview: Bool {
        session?.store.model.hasAIDraftContent ?? false
    }

    private func fetchRoutes() {
        routesTask?.cancel()
        guard let model = session?.store.model else { return }
        guard !needsDraftReview else {
            routePlan = nil
            return
        }
        routesFailure = nil
        isFetchingRoutes = true
        routesTask = Task {
            defer { isFetchingRoutes = false }
            do {
                let result = try await apiClient.fetchRoutesCached(home: model,
                                                                   profileID: selectedProfileID)
                guard !Task.isCancelled else { return }
                switch result {
                case .live(let plan):
                    guard plan.home_id == model.home_id else { return }
                    cachedPlanDate = nil
                    routePlan = plan
                    Haptics.tick()
                case .cached(let cached):
                    guard cached.plan.home_id == model.home_id else { return }
                    cachedPlanDate = cached.savedAt
                    routePlan = cached.plan
                    routesFailure = .showingCachedRoutes(savedAt: cached.savedAt)
                }
                applyOverlay()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                routesFailure = BackendFailure(error, while: .routes)
            }
        }
    }

    /// An accepted edit means the shown plan no longer matches the model: drop it and
    /// re-fetch once the editing burst settles.
    private func invalidateRoutes() {
        routesTask?.cancel()
        routePlan = nil
        overlayIssues = []
        overlayHolder.plan = nil
        overlayHolder.overlay?.clear()
        controller?.scnView.rendersContinuously = false
        refetchDebounce?.cancel()
        refetchDebounce = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            fetchRoutes()
        }
    }

    /// Fresh-`self` entry point: sync the draw inputs into the holder, then redraw from it.
    /// Never call this from the captured `onRebuild` closure — it would read stale @State;
    /// that path calls `overlayHolder.redraw()` instead.
    private func applyOverlay() {
        overlayHolder.plan = routePlan
        overlayHolder.selectedRoomID = selectedRoomID
        overlayHolder.model = session?.store.model
        // Selecting a person lights their figure in the accent green — the same signal the
        // selection ring uses — so the picker's effect is visible in the model, not just in
        // the line that gets drawn.
        overlayHolder.highlightedProfileID = selectedProfileID
        overlayHolder.redrawPeople()
        let issues = overlayHolder.redraw()
        // May run inside updateUIView (via onRebuild): only touch @State when the value
        // actually changed, or the view invalidates itself from within its own update forever.
        if issues != overlayIssues {
            overlayIssues = issues
        }
        // The pulse shader animates on u_time, which only advances while the view redraws —
        // and only routes need it, so idle scenes stay still.
        controller?.scnView.rendersContinuously = routePlan != nil
        controller?.scnView.setNeedsDisplay()
    }

    private func selectedRoom(in plan: RoutePlan) -> RoomRoutePlan? {
        guard let selectedRoomID else { return nil }
        return plan.rooms.first { $0.room_id == selectedRoomID }
    }

    private func shownFindings(in plan: RoutePlan) -> [RouteFinding] {
        let rooms = selectedRoomID.map { id in plan.rooms.filter { $0.room_id == id } } ?? plan.rooms
        return rooms.flatMap(\.findings)
    }

    // MARK: - Tour

    private func startTour(along route: Route) {
        guard let overlay = overlayHolder.overlay, let controller else { return }
        // The tour flies the whole stacked house at eye level, so it must not fly through
        // ghosted floors: solidify everything for the duration.
        controller.dollhouse?.setAllFloorsSolid()
        isTouring = true
        Haptics.begin()
        overlay.startTour(along: route, in: controller.scnView,
                          restoreTo: controller.rig.node) { isTouring = false }
    }

    private func stopTour() {
        overlayHolder.overlay?.cancelTour()
        isTouring = false
        // Restore floor focus the tour suspended.
        reapplyViewState()
    }

    // MARK: - Placement hint

    @ViewBuilder
    private func placementHint(kind: OpeningKind) -> some View {
        HStack {
            Image(systemName: kind == .door ? "door.left.hand.open" : "window.vertical.open")
            Text("Tap a wall to place the \(kind.rawValue). Interior vs. exterior is automatic.")
                .font(.caption)
            Spacer()
            Button("Cancel") { tool = .select }.font(.caption.bold())
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }

    // MARK: - Inspector (selection-driven entry points)

    @ViewBuilder
    private func inspector(for store: HomeModelStore) -> some View {
        switch store.selection {
        case .room(let roomId):
            if let (_, room) = store.model.locateRoom(roomId) {
                inspectorBar {
                    Button {
                        beginRename(.room(roomId), currentName: room.name)
                    } label: {
                        Label(room.name, systemImage: "pencil")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    Picker("Type", selection: Binding(
                        get: { room.type },
                        set: { dispatch(.setRoomType(roomId: roomId, type: $0)) }
                    )) {
                        ForEach(RoomType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button(role: .destructive) {
                        dispatch(.deleteRoom(roomId: roomId))
                    } label: {
                        Label("Delete Room", systemImage: "trash").labelStyle(.iconOnly)
                    }
                }
            }
        case .opening(let openingId):
            if let opening = store.activeFloor.openings.first(where: { $0.id == openingId }) {
                inspectorBar {
                    Picker("Kind", selection: Binding(
                        get: { opening.kind },
                        set: { dispatch(.setOpeningKind(openingId: openingId, kind: $0)) }
                    )) {
                        ForEach(OpeningKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                    Text(opening.isExit ? "Exterior" : "Interior")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        dispatch(.deleteOpening(openingId: openingId))
                    } label: {
                        Label("Delete Opening", systemImage: "trash").labelStyle(.iconOnly)
                    }
                }
            }
        case .stairs(let stairsId):
            inspectorBar {
                Label("Stairs", systemImage: "figure.stairs").font(.caption)
                Spacer()
                Button(role: .destructive) {
                    dispatch(.deleteStairs(stairsId: stairsId))
                } label: {
                    Label("Delete Stairs", systemImage: "trash").labelStyle(.iconOnly)
                }
            }
        case .object(let objectId):
            if let object = store.model.floors.flatMap(\.objects).first(where: { $0.id == objectId }) {
                inspectorBar {
                    Picker("Type", selection: Binding(
                        get: { object.category },
                        set: { dispatch(.setObjectCategory(objectId: objectId, category: $0)) }
                    )) {
                        ForEach(ObjectCategory.allCases, id: \.self) { category in
                            Text(category.rawValue.capitalized).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    Button {
                        dispatch(.rotateObject(objectId: objectId,
                                               rotation_deg: (object.rotation_deg + 45)
                                                   .truncatingRemainder(dividingBy: 360)))
                    } label: {
                        Label("Rotate 45°", systemImage: "rotate.right")
                            .labelStyle(.iconOnly)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        dispatch(.deleteObject(objectId: objectId))
                    } label: {
                        Label("Delete Object", systemImage: "trash").labelStyle(.iconOnly)
                    }
                }
            }
        case .none, .wall, .vertex:
            EmptyView()
        }
    }

    @ViewBuilder
    private func inspectorBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!(session?.undoStack.canUndo ?? false))
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!(session?.undoStack.canRedo ?? false))
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    addRoom()
                } label: {
                    Label("Add Room", systemImage: "plus.square.on.square")
                }
                Button {
                    tool = .placeOpening(.door)
                } label: {
                    Label("Add Door", systemImage: "door.left.hand.open")
                }
                Button {
                    tool = .placeOpening(.window)
                } label: {
                    Label("Add Window", systemImage: "window.vertical.open")
                }
                Button {
                    addObject()
                } label: {
                    Label("Add Object", systemImage: "cube")
                }
                Button {
                    addStairsSheetPresented = true
                } label: {
                    Label("Add Stairs", systemImage: "figure.stairs")
                }
                .disabled(!canAddStairs)
                Divider()
                Button {
                    addFloor(above: true)
                } label: {
                    Label("Add Floor Above", systemImage: "square.3.layers.3d.top.filled")
                }
                Button {
                    addFloor(above: false)
                } label: {
                    Label("Add Floor Below", systemImage: "square.3.layers.3d.bottom.filled")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .disabled(session == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    beginRename(.home, currentName: session?.store.model.name ?? "")
                } label: {
                    Label("Rename Home", systemImage: "pencil")
                }
                Button {
                    guard let store = session?.store else { return }
                    beginRename(.floor(store.activeFloorId), currentName: store.activeFloor.name)
                } label: {
                    Label("Rename Floor", systemImage: "pencil.line")
                }
                Button(role: .destructive) {
                    guard let store = session?.store else { return }
                    dispatch(.deleteFloor(floorId: store.activeFloorId))
                } label: {
                    Label("Delete This Floor", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(session == nil)
        }
    }

    // MARK: - Loading & saving

    private func loadIfNeeded() {
        guard session == nil, loadError == nil else { return }
        do {
            let model: HomeModel
            if let homeID, let documentStore, documentStore.exists(homeID: homeID) {
                model = try documentStore.load(homeID: homeID, as: HomeModel.self)
            } else {
                model = Self.blankHome()
            }
            let newStore = try HomeModelStore(model: model)
            let newSession = EditorSession(store: newStore)
            newStore.onCommit = { [documentStore] _commit in
                newSession.undoStack.recordCommit(_commit)
                autosave(newStore, documentStore: documentStore)
                invalidateRoutes()
            }
            session = newSession
            library?.editor = newSession
            // A brand-new home has nothing on disk yet — write it immediately so it shows up
            // in the home list without waiting for the first edit.
            if homeID == nil {
                autosave(newStore, documentStore: documentStore)
            }
            fetchRoutes()
        } catch {
            loadError = "\(error)"
        }
    }

    private func unregisterFromLibrary() {
        if let library, library.editor === session {
            library.editor = nil
        }
    }

    private func autosave(_ store: HomeModelStore, documentStore: HomeDocumentStore?) {
        do {
            try documentStore?.save(model: store.model)
            saveError = nil
        } catch {
            saveError = "\(error)"
        }
        onModelChanged?()
    }

    // MARK: - Dispatch

    /// Screen-level dispatch: forwards to the store and surfaces a rejection's reasons in the
    /// UI (the store guarantees a rejected action left the model untouched).
    private func dispatch(_ action: EditAction) {
        guard let store = session?.store else { return }
        switch store.dispatch(action) {
        case .applied:
            rejection = nil
        case .rejected(let issues):
            rejection = issues.first?.message
        }
    }

    private func addRoom() {
        guard let store = session?.store else { return }
        // Stagger new rooms so they don't land exactly on top of each other; not spatially
        // clever, just enough that the new room is visibly separate and grabbable.
        let count = store.activeFloor.rooms.count
        let offset = Double(count) * (HomeModelStore.defaultRoomSize.width + 0.5)
        dispatch(.addRoom(
            floorId: store.activeFloorId,
            origin: Point(x: offset, y: 0),
            width_m: HomeModelStore.defaultRoomSize.width,
            height_m: HomeModelStore.defaultRoomSize.height,
            type: .other,
            name: "New Room"
        ))
    }

    private func addFloor(above: Bool) {
        guard let store = session?.store else { return }
        dispatch(.addFloor(relativeTo: store.activeFloorId, above: above))
    }

    /// Drops a default box in the middle of the selected room (or the active floor's first
    /// room), selected so the user can immediately drag it where it belongs.
    private func addObject() {
        guard let store = session?.store else { return }
        let room = store.selection.roomId.flatMap { store.activeFloor.room($0) }
            ?? store.activeFloor.rooms.first
        guard let room else { return }
        let sum = room.polygon.reduce(Point(0, 0)) { Point($0.x + $1.x, $0.y + $1.y) }
        let center = Point(sum.x / Double(room.polygon.count), sum.y / Double(room.polygon.count))
        let objectId = UUID().uuidString
        dispatch(.addObject(objectId: objectId, floorId: store.activeFloorId, category: .other,
                            center: center, size_m: [1.2, 0.6], height_m: 0.8))
        store.select(.object(objectId: objectId))
    }

    // MARK: - Undo/redo

    private func undo() {
        guard let session, session.undoStack.undo(on: session.store) else { return }
        // replaceModel does NOT fire onCommit (undoing must not push its own undo entry), so
        // autosave and invalidate explicitly.
        autosave(session.store, documentStore: documentStore)
        invalidateRoutes()
    }

    private func redo() {
        guard let session, session.undoStack.redo(on: session.store) else { return }
        autosave(session.store, documentStore: documentStore)
        invalidateRoutes()
    }

    // MARK: - Rename

    private enum RenameTarget: Equatable {
        case home
        case floor(String)
        case room(String)

        var title: String {
            switch self {
            case .home: return "Rename Home"
            case .floor: return "Rename Floor"
            case .room: return "Rename Room"
            }
        }
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private func beginRename(_ target: RenameTarget, currentName: String) {
        renameDraft = currentName
        renameTarget = target
    }

    private func commitRename(_ target: RenameTarget) {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !name.isEmpty else { return }
        switch target {
        case .home: dispatch(.setHomeName(name))
        case .floor(let floorId): dispatch(.renameFloor(floorId: floorId, name: name))
        case .room(let roomId): dispatch(.renameRoom(roomId: roomId, name: name))
        }
    }

    // MARK: - Stairs

    private var canAddStairs: Bool {
        guard let store = session?.store else { return false }
        let hasFloorAbove = store.model.floors.contains { $0.level == store.activeFloor.level + 1 }
        return hasFloorAbove && store.selection.roomId != nil
    }

    @ViewBuilder
    private func addStairsSheet(for store: HomeModelStore) -> some View {
        NavigationStack {
            List {
                if let above = store.model.floors.first(where: { $0.level == store.activeFloor.level + 1 }) {
                    ForEach(above.rooms) { room in
                        Button(room.name) {
                            addStairs(toFloorId: above.id, toRoomId: room.id)
                        }
                    }
                }
            }
            .navigationTitle("Add Stairs To…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { addStairsSheetPresented = false }
                }
            }
        }
    }

    private func addStairs(toFloorId: String, toRoomId: String) {
        guard let store = session?.store, let fromRoomId = store.selection.roomId,
              let fromRoom = store.activeFloor.room(fromRoomId) else { return }
        let sum = fromRoom.polygon.reduce(Point(0, 0)) { Point($0.x + $1.x, $0.y + $1.y) }
        let centroid = Point(sum.x / Double(fromRoom.polygon.count), sum.y / Double(fromRoom.polygon.count))
        let footprint: Polygon = [
            Point(centroid.x - 0.5, centroid.y - 0.5),
            Point(centroid.x + 0.5, centroid.y - 0.5),
            Point(centroid.x + 0.5, centroid.y + 0.5),
            Point(centroid.x - 0.5, centroid.y + 0.5)
        ]
        dispatch(.addStairs(fromFloorId: store.activeFloorId, fromRoomId: fromRoomId,
                            toFloorId: toFloorId, toRoomId: toRoomId,
                            footprint: footprint, kind: .straight))
        addStairsSheetPresented = false
    }

    private static func blankHome() -> HomeModel {
        let now = Date()
        return HomeModel(
            schema_version: HomeModel.currentSchemaVersion,
            home_id: UUID().uuidString,
            name: "New Home",
            floors: [
                Floor(id: "floor-\(UUID().uuidString.prefix(8))", level: 0, name: "Ground Floor",
                      height_m: HomeModelStore.defaultFloorHeightM,
                      rooms: [Room(id: "room-\(UUID().uuidString.prefix(8))", name: "Room 1", type: .other,
                                   polygon: [Point(x: 0, y: 0), Point(x: 3, y: 0), Point(x: 3, y: 3), Point(x: 0, y: 3)],
                                   source: .manual, confidence: nil)],
                      openings: [])
            ],
            stairs: [],
            meta: Meta(created: now, modified: now)
        )
    }
}

#Preview {
    HouseScreen(homeID: nil)
        .environment(APIClient())
}
