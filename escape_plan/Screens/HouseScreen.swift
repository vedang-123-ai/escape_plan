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
    /// The checklist row that opened this screen, if any. Resolved to an object against the
    /// loaded model — never parsed into a selection by the caller, because only this screen
    /// knows which object ids the home actually has (S7.7).
    var initialFocusItemID: String? = nil
    @State private var initialSelection: Selection?
    @State private var hasFocusedInitial = false

    @Environment(APIClient.self) private var apiClient
    @Environment(\.dismiss) private var dismiss

    /// App-scoped, so sync knows which home is open regardless of which entry point opened it.
    /// `HouseEditorAppRegistration` sets its `openHomeID` on every appear and clears it on
    /// disappear (S11.19); before that it was set once at load and lost on the first tab switch.
    @Environment(HomeDocumentSyncRepository.self) private var syncRepository


    @State private var session: EditorSession?
    /// The session's load/save lifecycle (S11.19, AUD-013): re-arms the open-home guard on every
    /// appear and never autosaves over a file another writer changed. Nil until loaded.
    @State private var sessionController: HouseEditorSessionController?
    /// One line after House reloaded a home that changed elsewhere. Cleared by the next save.
    @State private var externalChangeNotice: String?
    /// The home's file was deleted while House held it. The session is closed for good.
    @State private var homeWasDeleted = false
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
    /// How far the dock has scrolled, clamped to the collapse range. The model card gives up
    /// height 1:1 against it — the design's 400pt down to 190pt — and the dock's leading
    /// spacer takes that height back so content tracks the finger exactly.
    @State private var dockScrollOffset: CGFloat = 0
    /// 0 at rest, 1 fully collapsed; fades the status banners out of the shrinking card.
    @State private var collapseProgress: Double = 0
    @State private var isCardCollapsed = false
    private static let designCardHeight: CGFloat = 400
    private static let collapsedCardHeight: CGFloat = 190
    /// Which job the dock is doing. The design (1a) gives the dock one job at a time — routes
    /// or the fire simulation — behind a segmented switch, instead of stacking both.
    private enum DockMode: Hashable { case routes, fire }
    @State private var dockMode: DockMode = .routes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The dock's height tracks the text size instead of being a hard 240. At the accessibility
    /// sizes a 240pt box shows about one and a half rows of the route controls; scaled it shows
    /// the same content it always did. Capped so the scene never loses more than it must — the
    /// dock scrolls internally, so the cap costs nothing but a scroll.

    /// The ordered-steps sheet: the VoiceOver alternative to reading a glowing line, and a
    /// perfectly good way for anyone to get the route as text.
    @State private var routeStepsPresented = false
    /// Reduce Motion replaces the camera fly-through with a stop-by-stop walk. `nil` = not
    /// running; otherwise the index of the stop being shown.
    @State private var steppedTourIndex: Int?

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

        /// Last issue list the evacuation renderer reported. It lives in the box for the same
        /// reason everything else here does: the handler can fire from inside a rebuild, where
        /// a captured @State *read* is stale. Comparing against the box instead means the
        /// change-check is made against a fresh value, so a genuine change is never swallowed
        /// and an unchanged list never invalidates the view from within its own update.
        var evacuationIssues: [String] = []

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
    /// Mirrors `RouteOverlayHolder.evacuationIssues` for display. Deliberately NOT merged into
    /// `overlayIssues`: `applyOverlay` overwrites that one wholesale with the route layer's
    /// issues, so two writers to one array would erase each other on every redraw.
    @State private var evacuationIssues: [String] = []
    @State private var isTouring = false
    @State private var routesTask: Task<Void, Never>?
    /// Debounces the re-fetch while the user is mid-editing-burst.
    @State private var refetchDebounce: Task<Void, Never>?

    // MARK: Fire-origin simulation (POST /evacuate)
    //
    // Ignite a room and the engine re-solves every escape route around the spreading hazard.
    // Exactly like /routes, the timeline is ALWAYS the server's — there is no client-side
    // fallback and no fabricated timeline when the network is down.

    /// The clock and derived state for the loaded timeline. The renderer lane binds to this
    /// object; this screen only drives it.
    @State private var playback = EvacuationPlaybackModel()
    @State private var isSimulating = false
    @State private var simulationFailure: BackendFailure?
    @State private var evacuateTask: Task<Void, Never>?
    /// The room the last ignition used, so Retry re-runs the same one rather than guessing.
    @State private var lastIgnitedRoomID: String?
    /// The VoiceOver-friendly alternative to tapping a room in the 3D model.
    @State private var ignitePickerPresented = false
    /// Set while the user drags the scrubber, so playback resumes only if it was playing.
    @State private var wasPlayingBeforeScrub = false
    /// "Who does what": the loaded timeline's tracks in words, set with the timeline.
    @State private var simulationJourneys: [EvacuationJourney] = []

    /// The library's store, the one store for this launch (AUD-019). Nil only without a
    /// library, which is the preview alone, and then nothing is saved.
    let documentStore: HomeDocumentStore?

    /// `startsOnFireSimulation`: open with the dock on "Fire simulation" instead of "Escape
    /// routes". Home's "Run a fire drill" sets it (trim 2, 2026-10-03: the drill IS this playback).
    init(homeID: String?, library: HomeLibrary? = nil, initialFocusItemID: String? = nil,
         startsOnFireSimulation: Bool = false, onModelChanged: (() -> Void)? = nil) {
        self.homeID = homeID
        self.library = library
        self.initialFocusItemID = initialFocusItemID
        self.onModelChanged = onModelChanged
        self.documentStore = library?.store
        _dockMode = State(initialValue: startsOnFireSimulation ? .fire : .routes)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(session?.store.model.name ?? "House")
                .toolbar { toolbarContent }
        }
        .task { loadIfNeeded() }
        // Reduce Motion degrades playback to discrete steps — it never disables the feature.
        // The flag is read HERE (the view layer): EvacuationPlaybackModel lives in Models/,
        // which is compiled into the pure-Foundation editorcore package with no UIKit.
        .onAppear {
            playback.isSteppedMode = reduceMotion
            // The TabView keeps this screen and its session alive across tab switches, and
            // onDisappear lifts the sync guard (verified in the simulator, S11.19). The first
            // appear has no session yet; `.task` loads it.
            resumeSession()
        }
        .onChange(of: controller) { _, newController in
            focusInitialSelection(controller: newController)
        }
        .onChange(of: reduceMotion) { _, newValue in
            playback.isSteppedMode = newValue
            // `RouteOverlay` reads the flag once, at construction, so a user who turns Reduce
            // Motion on while looking at a pulsing route would keep the pulse until the next
            // scene rebuild. Rebuild the overlay instead — same routes, same numbers, motion
            // dropped immediately.
            rebuildOverlayForMotionPreference(newValue)
            // A fly-through in progress is exactly what the setting is asking us to stop.
            if newValue, isTouring { stopTour() }
        }
        .onDisappear {
            routesTask?.cancel()
            refetchDebounce?.cancel()
            evacuateTask?.cancel()
            playback.pause()
            sessionController?.disappear()
            // A notice about the last visit; the next appear says again if anything changed.
            externalChangeNotice = nil
        }
        .sheet(isPresented: $addStairsSheetPresented) {
            if let session {
                addStairsSheet(for: session.store)
            }
        }
        .sheet(isPresented: $ignitePickerPresented) {
            if let session {
                ignitePickerSheet(for: session.store)
            }
        }
        .sheet(isPresented: $routeStepsPresented) {
            routeStepsSheet
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
        } else if homeWasDeleted {
            ContentUnavailableView("This home was deleted", systemImage: "trash",
                                    description: Text("Choose another home on the Home tab."))
        } else if let session {
            let store = session.store
            // The scene card collapses as the dock scrolls (the design's 1a artboard): 400pt
            // at rest, shrinking 1:1 with the dock's scroll offset down to 190pt, where it
            // holds. Dock chrome (inspector, placement hint, route controls) still appears
            // and vanishes INSIDE the dock and never resizes the scene — the only thing that
            // does is the user's own scroll, which cannot coincide with an in-flight drag on
            // the model, so the world never shifts under a finger that is touching it.
            //
            // View controls (floors, spotlight, fullscreen) float over the scene as a
            // fixed-height strip pinned to the card's top edge; at the collapsed height the
            // status banners fade so the strip and the illustrative notice keep their room.
            GeometryReader { geo in
            VStack(spacing: 0) {
                sceneCard(for: session)
                    .frame(height: isImmersive ? nil : cardHeight(in: geo.size.height))
                if !isImmersive {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // The design's sticky trick: whatever height the card gave up,
                            // this spacer takes back, so the content under the finger moves
                            // exactly as far as the finger did.
                            Color.clear
                                .frame(height: collapseDistance(in: geo.size.height))
                            if case .placeOpening(let kind) = tool {
                                placementHint(kind: kind)
                            }
                            inspector(for: store)
                            if let rejection {
                                Text(rejection).font(.caption).foregroundStyle(Theme.caution).padding(.horizontal)
                            }
                            if let externalChangeNotice {
                                Text(externalChangeNotice).font(.caption).foregroundStyle(Theme.caution)
                                    .padding(.horizontal)
                                    .accessibilityIdentifier("house.externalChangeNotice")
                            }
                            if let saveError {
                                Text("Autosave failed: \(saveError)").font(.caption).foregroundStyle(Theme.warning)
                                    .padding(.horizontal)
                            }
                            viewControls(for: store)
                            // Scroll room for the full collapse even when the dock's own
                            // content barely overflows — the design pads its dock bottom
                            // for the same reason. Blank space past the last control.
                            Color.clear
                                .frame(height: collapseRange(in: geo.size.height))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Both edges are read in the same (global) space and subtracted, so
                        // the offset needs no named coordinate space to resolve.
                        .background(GeometryReader { content in
                            Color.clear.preference(key: DockContentTopKey.self,
                                                   value: content.frame(in: .global).minY)
                        })
                    }
                    .modifier(DockScrollOffsetReader { offset in
                        updateCollapse(offset: offset, containerHeight: geo.size.height)
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            }
            .dsPage()
            .toolbar(isImmersive ? .hidden : .visible, for: .navigationBar, .tabBar)
            .statusBarHidden(isImmersive)
            .onChange(of: session.wasDeletedExternally) { _, deleted in
                guard deleted else { return }
                closeForDeletedHome(session, controller: sessionController)
                dismiss()
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

        // The renderer half of the simulation. Both parallel lanes built to this seam and
        // neither could call it: the engine lane owns `playback` but not the scene, the
        // renderer lane owns the figures, hazard and playback camera but not this screen. The
        // coordinator drives those layers from `playback`, which stays the single clock — the
        // renderer never decides where anyone goes or when a room burns.
        //
        // Bound AFTER `onRebuild` is installed, on purpose: the coordinator wraps that closure,
        // so a scene rebuild re-attaches the animated layers exactly the way it already
        // re-attaches the route overlay. Binding earlier would wrap a closure that is about to
        // be replaced.
        //
        // Safe to bind with nothing loaded — the coordinator no-ops until a timeline arrives,
        // and only then suspends the ordinary route.
        controller.bindEvacuationPlayback(
            playback,
            // A provider, not the layer itself: `onRebuild` replaces `overlayHolder.people`,
            // so the coordinator has to ask again after every rebuild.
            staticPeopleLayer: { overlayHolder.people },
            suspendOrdinaryRoutes: {
                // The pre-fire route answers a different question than the fire-aware one.
                // Drawing both at once is the one way this screen could actively mislead, so
                // the ordinary overlay goes away for the duration of the simulation.
                // Idempotent: clearing an already-cleared overlay is a no-op.
                overlayHolder.overlay?.clear()
            },
            restoreOrdinaryRoutes: {
                // Redraw from the holder's cached inputs — never from @State, which is stale
                // on the rebuild path.
                overlayHolder.redraw()
            },
            onIssues: { issues in
                guard issues != overlayHolder.evacuationIssues else { return }
                overlayHolder.evacuationIssues = issues
                evacuationIssues = issues
            }
        )
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

    @State private var hazardObjectIDs: Set<String> = []

    private func focusInitialSelection(controller: UnifiedSceneController?) {
        guard let controller else { return }
        if !hazardObjectIDs.isEmpty {
            controller.setHazardObjects(hazardObjectIDs)
        }
        guard let initialSelection, !hasFocusedInitial else { return }
        controller.focusCamera(on: initialSelection)
        hasFocusedInitial = true
    }

    /// Re-creates the route overlay against the live dollhouse with the new motion preference
    /// and redraws it from the holder's cached inputs.
    private func rebuildOverlayForMotionPreference(_ reduceMotion: Bool) {
        guard let dollhouse = controller?.dollhouse else { return }
        overlayHolder.overlay?.clear()
        overlayHolder.overlay = RouteOverlay(dollhouse: dollhouse, reduceMotion: reduceMotion)
        overlayHolder.redraw()
        // The motion preference decides whether anything in the scene still animates, so the
        // continuous-rendering answer changes with it.
        syncContinuousRendering()
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
                // A SceneKit surface is an unlabelled rectangle to VoiceOver: nothing to swipe
                // to, nothing to read, and its content is not reachable by touch exploration in
                // any meaningful way. So it becomes ONE element that says what it is showing,
                // with custom actions for the two things a screen-reader user actually needs
                // from it. Every one of those actions is also a real on-screen control — the
                // 3D is never the only way to do anything.
                .accessibilityElement()
                .accessibilityLabel(sceneAccessibilityLabel)
                .accessibilityHint("Use the actions to hear this route as numbered steps.")
                .accessibilityIdentifier("house.scene")
                .accessibilityAction(named: Text("Route steps")) {
                    routeStepsPresented = true
                }
                .accessibilityAction(named: Text("Recenter on the home")) {
                    controller?.recenterCamera()
                }

            // INTEGRATION POINT (renderer lane): the figures-and-hazard layer binds to
            // `playback` — it reads `playback.currentTime_s` for the playhead and
            // `playback.untenableRoomIDsNow` for the hazard, and derives figure positions
            // itself via PathSampler. Nothing in this screen draws either; it owns the data,
            // the clock, and the controls only.
            PlaybackClock(playback: playback)

            VStack(spacing: 8) {
                floatingSceneControls(for: store)
                // Collapsed, the card is a 190pt strip: the status banners fade so the chip
                // strip and the illustrative notice keep their room. Scrolling back restores them.
                Group {
                    routesBanner
                    simulationBanner
                }
                .opacity(isImmersive ? 1 : 1 - collapseProgress)
                .allowsHitTesting(isImmersive || collapseProgress < 0.5)
                // Non-negotiable: while a timeline is on screen, this notice is on screen.
                // It floats over the model, so it survives immersive mode and cannot be
                // scrolled away in the dock.
                illustrativeNotice
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

    // MARK: - Collapsing card

    /// The design's 400pt, capped so a short phone still shows a usable strip of dock at rest.
    private func expandedCardHeight(in containerHeight: CGFloat) -> CGFloat {
        min(Self.designCardHeight, max(Self.collapsedCardHeight + 40, containerHeight - 230))
    }

    /// How far the card can shrink: expanded minus collapsed height.
    private func collapseRange(in containerHeight: CGFloat) -> CGFloat {
        expandedCardHeight(in: containerHeight) - Self.collapsedCardHeight
    }

    private func cardHeight(in containerHeight: CGFloat) -> CGFloat {
        max(Self.collapsedCardHeight, expandedCardHeight(in: containerHeight) - dockScrollOffset)
    }

    private func collapseDistance(in containerHeight: CGFloat) -> CGFloat {
        expandedCardHeight(in: containerHeight) - cardHeight(in: containerHeight)
    }

    private func updateCollapse(offset: CGFloat, containerHeight: CGFloat) {
        let range = collapseRange(in: containerHeight)
        let clamped = min(max(0, offset), range)
        // Past the collapsed height nothing changes, so stop re-rendering per scroll frame.
        guard abs(clamped - dockScrollOffset) >= 0.5 else { return }
        dockScrollOffset = clamped
        collapseProgress = range > 0 ? Double(clamped / range) : 0
        let collapsed = clamped >= range - 0.5
        if collapsed != isCardCollapsed {
            isCardCollapsed = collapsed
            Haptics.selection()   // the card seats into place, either way
        }
    }

    /// Floor picker + spotlight + fullscreen, floating on the model's top edge. Fixed height,
    /// so it never resizes the scene underneath it.
    @ViewBuilder
    private func floatingSceneControls(for store: HomeModelStore) -> some View {
        let floors = store.model.floorsByLevel
        HStack(spacing: 8) {
            if floors.count > 1 {
                ForEach(Array(floors.enumerated()), id: \.element.id) { index, floor in
                    let isActive = store.activeFloorId == floor.id
                    let name = floor.name.isEmpty ? "Level \(floor.level)" : floor.name
                    Button {
                        store.setActiveFloor(floor.id)
                        focusFloor(floor.id)
                    } label: {
                        // The chip strip is fixed-height so it can never resize the scene; at
                        // the accessibility sizes a long floor name must therefore shorten
                        // rather than grow the strip. It still reads in full to VoiceOver.
                        Text(name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(GlassChipButtonStyle(isSelected: isActive))
                    .disabled(isTouring)
                    .accessibilityLabel("\(name), floor \(index + 1) of \(floors.count)")
                    .accessibilityHint("Shows this floor solid and ghosts the others.")
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
                    .accessibilityIdentifier("house.floorChip.\(floor.id)")
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
        Text(title).sectionHeaderStyle()
    }

    /// The design's two-segment card: one job at a time.
    private var dockModeSwitch: some View {
        HStack(spacing: 0) {
            ForEach([DockMode.routes, .fire], id: \.self) { mode in
                let selected = dockMode == mode
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { dockMode = mode }
                } label: {
                    Text(mode == .routes ? "Escape routes" : "Fire simulation")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .white : DS.bodyInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selected ? Theme.accent : .clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(HapticPlainButtonStyle())
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier(mode == .routes ? "house.dock.routes" : "house.dock.fire")
            }
        }
        .dsCard(radius: 12, padding: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dock shows")
    }

    @ViewBuilder
    private func viewControls(for store: HomeModelStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Floor picking lives on the model itself (floatingSceneControls). The dock does
            // one job at a time behind the switch: routes, or the fire simulation — which
            // stays reachable whether or not a route plan has loaded.
            dockModeSwitch
            switch dockMode {
            case .routes:
                // Hazard Hunt sat here until it was cut from the demo app (2026-10-02). The
                // object inspector still sets everything it did (type, strapped, mounted).
                if let routePlan {
                    routeControls(for: routePlan)
                } else if isFetchingRoutes {
                    Text("Planning your escape routes…")
                        .font(.subheadline)
                        .foregroundStyle(DS.supporting)
                        .padding(.top, 4)
                } else if routesFailure != nil {
                    // The banner over the model fades (`autoHides`); this keeps a way to try again.
                    Button("Try loading routes again") { fetchRoutes() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentText)
                        .minimumTapTarget()
                        .padding(.top, 4)
                        .accessibilityIdentifier("house.routesRetry")
                }
            case .fire:
                simulationControls(for: store)
            }
        }
        .padding(DS.pagePadding)
        .padding(.bottom, 6)
    }

    /// Non-blocking status strip over the scene — the house stays fully interactive while
    /// routes are fetched (server cold starts can take ~30 s) or after a failure.
    @ViewBuilder
    private var routesBanner: some View {
        if needsDraftReview {
            let draftText = "AI draft — review the layout, then confirm to compute escape routes."
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { draftIcon; draftMessage(draftText); confirmDraftButton }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        draftIcon
                        draftMessage(draftText)
                    }
                    confirmDraftButton
                }
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
            BackendFailureBanner(failure: routesFailure, retry: { fetchRoutes() }, autoHides: true)
                .padding(.top, 8)
        }
    }

    private var draftIcon: some View {
        Image(systemName: "wand.and.stars").accessibilityHidden(true)
    }

    private func draftMessage(_ text: String) -> some View {
        Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
    }

    private var confirmDraftButton: some View {
        Button("Confirm draft") {
            dispatch(.confirmAIDraft)
            fetchRoutes()
        }
        .font(.caption.bold())
        .minimumTapTarget()
        .accessibilityLabel("Confirm the AI draft")
        .accessibilityHint("Accepts the drafted layout so the routing engine can plan on it.")
        .accessibilityIdentifier("house.confirmDraft")
    }

    // MARK: - Fire-origin simulation: chrome

    /// Drives the playhead off the display's cadence without a `CADisplayLink` and without
    /// putting a timer in the model. `TimelineView(.animation)` re-evaluates per frame while
    /// playing and stops entirely when paused, so an idle screen costs nothing.
    ///
    /// The delta is capped: `.animation(paused:)` freezes its date while paused and while the
    /// app is backgrounded, so the first frame after a resume can report many seconds and
    /// would otherwise skip the whole animation in one tick. `tick` itself accepts any
    /// positive delta — the cap is a property of this clock, not of the model.
    private struct PlaybackClock: View {
        let playback: EvacuationPlaybackModel
        /// Roughly three frames at 30 fps. Long enough to absorb a hitch, short enough that a
        /// resume never jumps.
        private static let maxFrameDelta_s: Double = 0.1

        var body: some View {
            TimelineView(.animation(minimumInterval: playback.isSteppedMode ? 0.2 : nil,
                                    paused: !playback.isPlaying)) { context in
                Color.clear
                    .frame(width: 0, height: 0)
                    .onChange(of: context.date) { oldDate, newDate in
                        let delta = newDate.timeIntervalSince(oldDate)
                        playback.tick(deltaTime: min(delta, Self.maxFrameDelta_s))
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The mandatory disclaimer, floating on the model itself.
    ///
    /// Presence is unconditional while a timeline is loaded — deliberately not gated on
    /// `is_illustrative`, because a backend that ever sent `false` (or a decoder default that
    /// ever changed) would silently remove a safety-critical caveat. `is_illustrative` drives
    /// the WORDING; the notice being there at all is guaranteed by `playback.hasTimeline`.
    ///
    /// It says what the animation is (geometry plus assumed speeds) and, explicitly, what it
    /// is not (a prediction of survival). Anything softer invites a judge — or a family — to
    /// read a green figure reaching the door as a promise.
    @ViewBuilder
    private var illustrativeNotice: some View {
        if playback.hasTimeline {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(Theme.caution)
                    .accessibilityHidden(true)
                Text(illustrativeNoticeText)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .glassPanel(cornerRadius: 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(illustrativeNoticeText)
            .accessibilityIdentifier("house.simulation.disclaimer")
        }
    }

    private var illustrativeNoticeText: String {
        playback.isIllustrative
            ? "Illustrative only: this animates your floor plan and assumed walking speeds. "
            + "It is not a prediction of how a real fire would spread or who would get out."
            : "This simulation is a visualization of your floor plan and assumed walking "
            + "speeds. Treat it as illustrative, not as a prediction of a real fire."
    }

    /// Progress / failure strip for the simulation, kept separate from `routesBanner` so a
    /// routes problem and a simulation problem never overwrite each other.
    @ViewBuilder
    private var simulationBanner: some View {
        if isSimulating {
            HStack(spacing: 8) {
                ProgressView()
                Text("Simulating a fire in \(pendingOriginRoomName)…")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        } else if let simulationFailure {
            // One classifier, one banner: a 502 (an operator must act) gets no Retry, a 503
            // does. Nothing is invented client-side to paper over either.
            BackendFailureBanner(failure: simulationFailure,
                                 retry: lastIgnitedRoomID.map { id in { ignite(roomID: id) } },
                                 autoHides: true)
        }
    }

    /// The dock's simulation section: ignite when there is nothing loaded, playback and
    /// findings when there is.
    @ViewBuilder
    private func simulationControls(for store: HomeModelStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            dockHeader("Fire simulation")

            if store.model.profiles.isEmpty {
                // The engine puts one stand-in per room when nobody is added (hazard.py), named
                // after the room. Say so, and where people are added, so "Kitchen" walking out
                // is not mistaken for a family member (this note replaces the old drill's
                // empty state, AUD-020).
                Text("No one is added to this home yet, so the simulation puts one person in "
                     + "each room. Add your household from the Home tab.")
                    .font(.caption)
                    .foregroundStyle(DS.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("house.simulation.noPeople")
            }

            if playback.hasTimeline {
                loadedSimulationControls(for: store)
            } else {
                igniteControls(for: store)
            }

            // Same honesty as the route overlay's notice: if a figure or a burning room could
            // not be placed on the model, say so rather than letting the animation read as
            // complete. The timeline itself is still correct — this is a drawing failure.
            if !evacuationIssues.isEmpty {
                Text("Some of the simulation couldn't be drawn on the model.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Ignite

    /// Two ways in, on purpose. Tapping a room in the 3D model already selects it (the editor's
    /// existing hit-testing), so "selected room → Ignite" needs no new tap handling — and a
    /// VoiceOver user, who cannot reliably hit a room in a 3D scene, gets an equivalent room
    /// list instead. Neither path is the "real" one.
    @ViewBuilder
    private func igniteControls(for store: HomeModelStore) -> some View {
        let selected = store.selection.roomId.flatMap { store.model.locateRoom($0) }

        VStack(alignment: .leading, spacing: 8) {
            Text("Start a fire in one room and the engine re-plans everyone's way out around "
                 + "it. Nothing about your saved plan changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    igniteSelectedButton(selected)
                    choosePickerButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    igniteSelectedButton(selected)
                    choosePickerButton
                }
            }

            if selected == nil {
                Text("Tap a room in the model to pick it, or choose one from the list.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(needsDraftReview)
    }

    @ViewBuilder
    private func igniteSelectedButton(_ selected: (floorId: String, room: Room)?) -> some View {
        Button {
            if let selected { ignite(roomID: selected.room.id) }
        } label: {
            Label(selected.map { "Ignite \($0.room.name)" } ?? "Ignite selected room",
                  systemImage: "flame.fill")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent).hapticTap()
        .tint(Theme.warning)
        .disabled(selected == nil || isSimulating)
        .accessibilityLabel(selected.map { "Ignite \($0.room.name)" } ?? "Ignite selected room")
        .accessibilityHint(selected == nil
            ? "Unavailable until a room is selected. Choose a room from the list instead."
            : "Simulates a fire starting in this room and re-plans everyone's escape around it.")
        .accessibilityIdentifier("house.simulation.ignite")
    }

    private var choosePickerButton: some View {
        Button {
            ignitePickerPresented = true
        } label: {
            Label("Choose a room…", systemImage: "list.bullet")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered).hapticTap()
        .disabled(isSimulating)
        .accessibilityLabel("Choose a room to ignite")
        .accessibilityHint("Opens a list of every room in the home.")
        .accessibilityIdentifier("house.simulation.choose")
    }

    /// The accessible ignition path: a plain list of every room, grouped by floor. Present
    /// whether or not VoiceOver is on — a one-handed user on a moving bus benefits too.
    @ViewBuilder
    private func ignitePickerSheet(for store: HomeModelStore) -> some View {
        NavigationStack {
            List {
                ForEach(store.model.floorsByLevel) { floor in
                    Section(floor.name.isEmpty ? "Level \(floor.level)" : floor.name) {
                        ForEach(floor.rooms) { room in
                            Button {
                                ignitePickerPresented = false
                                ignite(roomID: room.id)
                            } label: {
                                Label(room.name, systemImage: "flame")
                            }
                            .accessibilityLabel("Start the fire in \(room.name)")
                            .accessibilityHint("Simulates a fire beginning in this room.")
                        }
                    }
                }
            }
            .navigationTitle("Start the fire in…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { ignitePickerPresented = false }
                }
            }
        }
    }

    // MARK: Playback

    @ViewBuilder
    private func loadedSimulationControls(for store: HomeModelStore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Reversibility, stated plainly and always reachable — igniting is a view mode,
            // not an edit, and the user must never wonder whether they broke their plan.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    simulationOriginLabel
                    Spacer(minLength: 8)
                    clearSimulationButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    simulationOriginLabel
                    clearSimulationButton
                }
            }

            transportControls
            scrubber

            if reduceMotion {
                Text("Reduce Motion is on, so the simulation steps forward in one-second jumps "
                     + "instead of animating. Scrubbing works the same.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Narrates the engine's tracks; never computes a route (EvacuationJourney.swift).
            if !simulationJourneys.isEmpty {
                EvacuationPeoplePanel(journeys: simulationJourneys)
            }

            simulationFindings(for: store)
        }
    }

    private var simulationOriginLabel: some View {
        Text("Fire starts in \(originRoomName)")
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var clearSimulationButton: some View {
        Button(role: .destructive) {
            clearSimulation()
        } label: {
            Label("Clear simulation", systemImage: "xmark.circle")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered).hapticTap()
        .accessibilityLabel("Clear simulation")
        .accessibilityHint("Removes the fire and returns to your normal escape routes.")
        .accessibilityIdentifier("house.simulation.clear")
    }

    /// Play/pause, replay, and speed. Speed is a menu rather than a segmented control so it
    /// cannot clip at the accessibility text sizes.
    private var transportControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                playPauseButton
                replayButton
                Spacer(minLength: 8)
                rateMenu
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    playPauseButton
                    replayButton
                }
                rateMenu
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            playback.togglePlayback()
            Haptics.tick()
        } label: {
            Label(playback.isPlaying ? "Pause" : "Play",
                  systemImage: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
        }
        .buttonStyle(HapticPlainButtonStyle())
        .foregroundStyle(Theme.accent)
        .accessibilityLabel(playback.isPlaying ? "Pause simulation" : "Play simulation")
        .accessibilityValue("\(playback.elapsedLabel) of \(playback.durationLabel)")
        .accessibilityHint(playback.isPlaying
            ? "Stops the simulation where it is."
            : "Runs the simulation forward from the current time.")
        .accessibilityAddTraits(.startsMediaSession)
        .accessibilityIdentifier("house.simulation.playPause")
    }

    private var replayButton: some View {
        Button {
            playback.restart()
        } label: {
            Label("Replay", systemImage: "arrow.counterclockwise.circle")
                .labelStyle(.iconOnly)
                .font(.title3)
        }
        .buttonStyle(HapticPlainButtonStyle())
        .foregroundStyle(Theme.accent)
        .accessibilityLabel("Replay from the start")
        .accessibilityHint("Moves back to the moment of ignition and plays.")
        .accessibilityIdentifier("house.simulation.replay")
    }

    private var rateMenu: some View {
        Menu {
            Picker("Speed", selection: Binding(get: { playback.playbackRate },
                                               set: { playback.playbackRate = $0 })) {
                ForEach(EvacuationPlaybackModel.supportedRates, id: \.self) { rate in
                    Text(EvacuationPlaybackModel.rateLabel(rate)).tag(rate)
                }
            }
        } label: {
            Label("Speed \(EvacuationPlaybackModel.rateLabel(playback.playbackRate))",
                  systemImage: "speedometer")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(EvacuationPlaybackModel.spokenRateLabel(playback.playbackRate))
        .accessibilityHint("Choose how fast the simulation runs.")
        .accessibilityIdentifier("house.simulation.rate")
    }

    /// Elapsed and total are rendered as TEXT, not inferred from the bar's position — the
    /// scrubber is a second way to read the time, never the only way.
    private var scrubber: some View {
        let span = max(playback.duration_s, 0.001)
        // A twentieth of the timeline per VoiceOver swipe: enough steps to reach any moment,
        // few enough that crossing a 90-second timeline isn't a chore.
        let step = max(playback.duration_s / 20, 1)

        return VStack(alignment: .leading, spacing: 4) {
            Slider(
                value: Binding(get: { playback.currentTime_s },
                               set: { playback.seek(to: $0) }),
                in: 0...span,
                onEditingChanged: { editing in
                    if editing {
                        wasPlayingBeforeScrub = playback.isPlaying
                        playback.pause()
                    } else if wasPlayingBeforeScrub {
                        playback.play()
                    }
                }
            )
            .tint(Theme.accent)
            // Replaces the Slider's own element so the adjustable action, the label, and the
            // spoken value are all ours and all agree with the visible text below.
            .accessibilityElement()
            .accessibilityLabel("Simulation time")
            .accessibilityValue(
                "\(EvacuationPlaybackModel.spokenTimeLabel(playback.currentTime_s)) of "
                + "\(EvacuationPlaybackModel.spokenTimeLabel(playback.duration_s))")
            .accessibilityHint("Swipe up or down to move through the simulation.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: playback.seek(to: playback.currentTime_s + step)
                case .decrement: playback.seek(to: playback.currentTime_s - step)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("house.simulation.scrubber")

            HStack {
                Text(playback.elapsedLabel)
                Spacer(minLength: 8)
                Text(playback.durationLabel)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)  // the scrubber already speaks both values
        }
    }

    // MARK: Simulation findings

    /// `overtaken_by_hazard` surfaced in the same component, the same severity vocabulary, and
    /// the same tier as the routing engine's worst finding. It is an honest negative result:
    /// it is never hidden, never downgraded, and never delayed until the animation finishes.
    @ViewBuilder
    private func simulationFindings(for store: HomeModelStore) -> some View {
        let overtaken = playback.overtakenTracks
        let engineFindings = playback.findings

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                dockHeader("Simulation check")
                let count = overtaken.count + engineFindings.count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color(DollhousePalette.warningBadgeSevere), in: Capsule())
                        .accessibilityLabel("\(count) issues")
                }
            }

            if overtaken.isEmpty && engineFindings.isEmpty {
                RouteAllClearRow()
            } else {
                ForEach(overtaken) { track in
                    OvertakenFindingCard(track: track, originRoomName: originRoomName)
                }
                // Anything the engine attached to the timeline renders verbatim, exactly like
                // a /routes finding.
                ForEach(engineFindings.indices, id: \.self) { i in
                    RouteFindingCard(finding: engineFindings[i],
                                     roomName: simulationRoomName(engineFindings[i].room_id,
                                                                  in: store))
                }
            }
        }
    }

    // MARK: Simulation naming helpers

    /// Name of the room the loaded timeline's fire starts in. Falls back to the raw id rather
    /// than inventing a friendlier one.
    private var originRoomName: String {
        guard let id = playback.originRoomID else { return "this room" }
        return session?.store.model.locateRoom(id)?.room.name ?? id
    }

    /// Name of the room the in-flight ignition is for (the banner reads better than "a room").
    private var pendingOriginRoomName: String {
        guard let id = lastIgnitedRoomID else { return "your home" }
        return session?.store.model.locateRoom(id)?.room.name ?? id
    }

    private func simulationRoomName(_ roomID: String, in store: HomeModelStore) -> String {
        store.model.locateRoom(roomID)?.room.name ?? roomID
    }

    // MARK: - Accessibility: the 3D scene, and the route as ordered steps

    /// The summary VoiceOver reads for the SceneKit surface. Assembled here, worded in
    /// `HouseSceneAccessibility` (which is unit-tested).
    private var sceneAccessibilityLabel: String {
        guard let store = session?.store else { return "3D model of your home. Loading." }
        let model = store.model
        let floors = model.floorsByLevel
        let activeIndex = floors.firstIndex { $0.id == store.activeFloorId } ?? 0
        let activeFloor = floors.indices.contains(activeIndex) ? floors[activeIndex] : nil

        return HouseSceneAccessibility.sceneLabel(
            homeName: model.name,
            floorName: activeFloor.map { $0.name.isEmpty ? "Level \($0.level)" : $0.name } ?? "",
            floorNumber: activeIndex + 1,
            floorCount: floors.count,
            roomCount: activeFloor?.rooms.count ?? 0,
            personName: selectedProfileID.flatMap { id in
                model.profiles.first { $0.id == id }?.name
            },
            roomName: narrationRoom?.room_name,
            hasRoutes: routePlan != nil,
            simulation: simulationAccessibilityState(in: model))
    }

    /// nil when nothing is simulated — the summary then says nothing about a fire, rather than
    /// saying "no fire", which would be noise on every other screen read.
    private func simulationAccessibilityState(in model: HomeModel)
        -> HouseSceneAccessibility.SimulationState? {
        guard playback.hasTimeline else { return nil }
        let untenable = playback.untenableRoomIDsNow
            .map { model.locateRoom($0)?.room.name ?? $0 }
            .sorted()
        return HouseSceneAccessibility.SimulationState(
            originRoomName: originRoomName,
            isPlaying: playback.isPlaying,
            elapsedSpoken: EvacuationPlaybackModel.spokenTimeLabel(playback.currentTime_s),
            durationSpoken: EvacuationPlaybackModel.spokenTimeLabel(playback.duration_s),
            untenableRoomNames: untenable,
            overtakenPeopleNames: playback.overtakenTracks.map(\.profile_name))
    }

    /// Which room's route the steps describe. The selected room when there is one; otherwise
    /// the selected person's bedroom; otherwise the first room the engine returned — so the
    /// affordance is never dead, and it never guesses a route the engine did not compute.
    private var narrationRoom: RoomRoutePlan? {
        guard let plan = routePlan else { return nil }
        if let selectedRoomID, let room = plan.rooms.first(where: { $0.room_id == selectedRoomID }) {
            return room
        }
        if let profileID = selectedProfileID,
           let bedroom = session?.store.model.profiles.first(where: { $0.id == profileID })?
               .bedroom_room_id,
           let room = plan.rooms.first(where: { $0.room_id == bedroom }) {
            return room
        }
        return plan.rooms.first { $0.primary != nil } ?? plan.rooms.first
    }

    /// The chips currently drawn for that room, so the spoken numbering IS the drawn numbering.
    private var narrationDrawnStops: [RouteGeometry.Stop]? {
        guard let id = narrationRoom?.room_id else { return nil }
        return overlayHolder.overlay?.drawnSteps[id]
    }

    private var narrationSteps: [HouseSceneAccessibility.StepLine] {
        guard let room = narrationRoom, let model = session?.store.model else { return [] }
        return HouseSceneAccessibility.steps(for: room, in: model,
                                             drawn: narrationDrawnStops,
                                             meetingPoint: savedMeetingPoint)
    }

    /// The household's outside meeting place, if they have entered one in the export sheet. It
    /// becomes the last spoken step — the same last step the printed plan carries.
    private var savedMeetingPoint: String? {
        guard let id = session?.store.model.home_id else { return nil }
        let text = MeetingPointStore().meetingPoint(forHomeID: id)
        return text.isEmpty ? nil : text
    }

    /// The affordance itself. A real, focusable button in the dock — not a gesture on the 3D,
    /// not a hidden accessibility-only element. Anyone can use it; a VoiceOver user must.
    private var routeStepsButton: some View {
        Button {
            routeStepsPresented = true
        } label: {
            Label("Route steps", systemImage: "list.number")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered).hapticTap()
        .minimumTapTarget()
        .disabled(narrationRoom == nil)
        .accessibilityLabel(narrationRoom.map { "Route steps for the \($0.room_name)" }
                            ?? "Route steps")
        .accessibilityHint("Reads the escape route as a numbered list you can move through "
                           + "one step at a time.")
        .accessibilityIdentifier("house.routeSteps")
    }

    /// The steps as text. Numbers match the chips on the model; the sentences are the same
    /// narrator the printable PDF uses.
    @ViewBuilder
    private var routeStepsSheet: some View {
        NavigationStack {
            List {
                if let room = narrationRoom, let plan = routePlan {
                    routeStepsContent(room: room, plan: plan)
                } else {
                    Section {
                        Text("No escape routes have been computed for this home yet. The app "
                             + "never invents one — the routing engine has to return it first.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .navigationTitle("Route steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { routeStepsPresented = false }
                        .accessibilityHint("Closes the route steps.")
                }
            }
        }
    }

    @ViewBuilder
    private func routeStepsContent(room: RoomRoutePlan, plan: RoutePlan) -> some View {
        let steps = narrationSteps

        Section {
            Text(room.room_name)
                .font(Theme.screenTitle)
                .fixedSize(horizontal: false, vertical: true)
            if let primary = room.primary {
                Text(RouteNarration.summaryLine(for: primary))
                    .font(.callout)
                    .foregroundStyle(Theme.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Primary route")
        } footer: {
            Text("The numbers here are the numbers on the model — step 3 spoken is the "
                 + "circled 3 you can see.")
        }

        if steps.isEmpty {
            Section {
                Text("The routing engine returned no route for the \(room.room_name).")
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Section("Steps") {
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(step.number). \(step.title)")
                            .font(.callout.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = step.detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.supporting)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(step.spoken)
                }
            }
        }

        // The engine's findings, verbatim, in the same place — a route you can hear but whose
        // warning you cannot would be worse than no route at all.
        if !room.findings.isEmpty, let model = session?.store.model {
            Section("Route check") {
                ForEach(room.findings.indices, id: \.self) { i in
                    Text(RouteNarration.findingSentence(room.findings[i], in: model))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if let secondary = room.secondary, let model = session?.store.model {
            Section {
                ForEach(Array(RouteNarration.sentences(for: secondary, from: room.room_id,
                                                       in: model,
                                                       meetingPoint: savedMeetingPoint)
                              .enumerated()), id: \.offset) { index, sentence in
                    Text("\(index + 1). \(sentence)")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Backup route")
            } footer: {
                Text("Drawn as a dashed line on the model. Numbered separately from the "
                     + "primary route, because it is a different walk.")
            }
        }

        if plan.rooms.count > 1 {
            Section {
                Text("Pick a different room in Escape routes to hear its steps.")
                    .font(.footnote)
                    .foregroundStyle(Theme.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Fire-origin simulation: fetch

    /// Asks the engine for a timeline. There is no offline path on purpose: a fabricated
    /// timeline would be the app inventing a safety claim, which is the one thing the whole
    /// architecture exists to prevent. Offline fails honestly through `BackendFailure`, which
    /// distinguishes "retry may work" (503) from "an operator must act" (502).
    private func ignite(roomID: String) {
        evacuateTask?.cancel()
        guard let model = session?.store.model else { return }
        guard !needsDraftReview else { return }
        simulationFailure = nil
        lastIgnitedRoomID = roomID
        isSimulating = true
        Haptics.begin()
        evacuateTask = Task {
            defer { isSimulating = false }
            do {
                let timeline = try await apiClient.evacuate(home: model, originRoomID: roomID)
                guard !Task.isCancelled else { return }
                // A response for a different home means the model moved under an in-flight
                // request; showing it would animate the wrong house.
                guard timeline.home_id == model.home_id else { return }
                playback.load(timeline)
                // Worked out once per timeline, not per frame: the dock re-renders every tick.
                simulationJourneys = EvacuationJourneyNarrator.journeys(for: timeline, in: model)
                playback.isSteppedMode = reduceMotion
                playback.play()
                syncContinuousRendering()
                Haptics.tick()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                simulationFailure = BackendFailure(error, while: .simulation)
            }
        }
    }

    /// Igniting is fully reversible and this is the one path back — used by the Clear button
    /// and by any edit that invalidates the plan the timeline was solved against.
    private func clearSimulation() {
        evacuateTask?.cancel()
        isSimulating = false
        simulationFailure = nil
        lastIgnitedRoomID = nil
        playback.load(nil)
        simulationJourneys = []
        syncContinuousRendering()
    }

    /// The pulse shader and any playback animation only advance while the view redraws, so
    /// continuous rendering follows "is there anything moving", not any one feature.
    private func syncContinuousRendering() {
        // `wantsContinuousRendering`, not `scnView.rendersContinuously`: the camera rig writes
        // the same SCNView property while it is moving, and the two used to clobber each other
        // — the rig set it false when inertia stopped and silently froze the route pulse. The
        // controller ORs the two reasons.
        // Routes need continuous rendering ONLY because the pulse shader advances on `u_time`.
        // Under Reduce Motion `RouteOverlay` does not install that shader and does not run the
        // repeating action — so the scene is fully static and this was pinning the renderer at
        // 60 fps forever, for nothing, on exactly the setting most likely to be chosen for
        // battery and thermal relief.
        controller?.wantsContinuousRendering = (routePlan != nil && !reduceMotion)
            || playback.hasTimeline
        controller?.scnView.setNeedsDisplay()
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
                .accessibilityLabel("Who is escaping")
                .accessibilityHint("Re-runs the routing engine with this person's constraints "
                                   + "and jumps to their bedroom.")
                .accessibilityIdentifier("plan.profile.picker")
                .onChange(of: selectedProfileID) { _, newValue in
                    Haptics.selection()
                    selectedRoomID = newValue.flatMap { id in
                        model.profiles.first { $0.id == id }?.bedroom_room_id
                    }
                    fetchRoutes()
                }
            }

            let routePicker = Picker("Route", selection: $selectedRoomID) {
                Text("Everyone").tag(String?.none)
                ForEach(plan.rooms) { room in
                    Text(room.room_name).tag(Optional(room.room_id))
                }
            }
            .accessibilityIdentifier("plan.route.picker")
            .accessibilityLabel("Route to show")
            .accessibilityHint("Choose whose route is drawn on the model.")
            .disabled(isTouring)
            .onChange(of: selectedRoomID) { _, _ in Haptics.selection(); applyOverlay() }

            // At the accessibility text sizes the picker and the buttons cannot share a line;
            // they stack rather than truncate.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    routePicker
                    Spacer(minLength: 8)
                    routeStepsButton
                    tourButton(in: plan)
                }
                VStack(alignment: .leading, spacing: 10) {
                    routePicker
                    HStack(spacing: 10) {
                        routeStepsButton
                        tourButton(in: plan)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    routePicker
                    routeStepsButton
                    tourButton(in: plan)
                }
            }

            steppedTourControls(in: plan)
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
        steppedTourIndex = nil
        overlayHolder.plan = nil
        overlayHolder.overlay?.clear()
        // The timeline was solved against the model as it was; an accepted edit makes it a
        // picture of a house that no longer exists. Drop it rather than keep animating a
        // stale answer — the user re-ignites when they're ready.
        clearSimulation()
        controller?.wantsContinuousRendering = false
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
        // The pulse shader animates on u_time, which only advances while the view redraws, so
        // idle scenes stay still. A loaded evacuation timeline needs the same thing.
        syncContinuousRendering()
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
    //
    // Reduce Motion does not turn the tour off. A camera flying through a house at eye level is
    // exactly the vestibular trigger the setting exists for, so under Reduce Motion the tour
    // becomes what it always was underneath: a walk through the route's numbered stops, one at
    // a time, user-paced. Same stops, same numbers, same route drawn on the model — the only
    // thing removed is the continuous camera motion between them.

    @ViewBuilder
    private func tourButton(in plan: RoutePlan) -> some View {
        if let room = selectedRoom(in: plan), let primary = room.primary {
            Button {
                if reduceMotion {
                    steppedTourIndex == nil ? startSteppedTour(in: plan) : stopSteppedTour()
                } else {
                    isTouring ? stopTour() : startTour(along: primary)
                }
            } label: {
                Label(isTourRunning ? "Stop" : (reduceMotion ? "Walk it" : "Tour"),
                      systemImage: isTourRunning ? "stop.circle" : "play.circle")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderedProminent).hapticTap()
            .minimumTapTarget()
            .accessibilityLabel(isTourRunning
                ? "Stop the tour"
                : (reduceMotion ? "Walk the route stop by stop" : "Tour the route"))
            .accessibilityHint(reduceMotion
                ? "Reduce Motion is on, so this steps between the numbered stops instead of "
                  + "flying the camera along the route."
                : "Flies the camera along the primary route at eye level.")
            .accessibilityIdentifier("plan.tour.button")
        } else if selectedRoomID == nil {
            Text("Pick a room to tour")
                .font(.caption2)
                .foregroundStyle(Theme.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isTourRunning: Bool { isTouring || steppedTourIndex != nil }

    /// The stops the stepped tour walks — the SAME list the chips are drawn from, so "stop 3"
    /// here is the circled 3 on the model and the third line in the route-steps sheet.
    private func steppedTourStops(in plan: RoutePlan) -> [RouteGeometry.Stop] {
        guard let room = selectedRoom(in: plan), let primary = room.primary else { return [] }
        return overlayHolder.overlay?.drawnSteps[room.room_id]
            ?? RouteGeometry.numberedStops(for: primary)
    }

    @ViewBuilder
    private func steppedTourControls(in plan: RoutePlan) -> some View {
        let stops = steppedTourStops(in: plan)
        if let index = steppedTourIndex, stops.indices.contains(index) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stop \(index + 1) of \(stops.count): \(stops[index].kind.title)")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("plan.tour.steppedStatus")

                Text("Reduce Motion is on, so the tour steps between stops instead of flying "
                     + "the camera. The route on the model is unchanged.")
                    .font(.caption2)
                    .foregroundStyle(Theme.supporting)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        showSteppedStop(index - 1, in: plan)
                    } label: {
                        Label("Previous stop", systemImage: "chevron.backward")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered).hapticTap()
                    .minimumTapTarget()
                    .disabled(index == 0)
                    .accessibilityLabel("Previous stop")
                    .accessibilityIdentifier("plan.tour.previousStop")

                    Button {
                        showSteppedStop(index + 1, in: plan)
                    } label: {
                        Label("Next stop", systemImage: "chevron.forward")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered).hapticTap()
                    .minimumTapTarget()
                    .disabled(index >= stops.count - 1)
                    .accessibilityLabel("Next stop")
                    .accessibilityIdentifier("plan.tour.nextStop")

                    Spacer(minLength: 8)
                }
            }
        }
    }

    private func startSteppedTour(in plan: RoutePlan) {
        guard !steppedTourStops(in: plan).isEmpty else { return }
        Haptics.begin()
        showSteppedStop(0, in: plan)
    }

    private func stopSteppedTour() {
        steppedTourIndex = nil
        reapplyViewState()
    }

    /// Moves the walk to one stop. Floor focus is a CUT, never a glide — Reduce Motion is the
    /// whole reason this path exists, so it must not reintroduce the motion by the back door.
    private func showSteppedStop(_ index: Int, in plan: RoutePlan) {
        let stops = steppedTourStops(in: plan)
        guard stops.indices.contains(index) else { return }
        steppedTourIndex = index
        Haptics.tick()

        let floorID = stops[index].waypoint.floor_id
        guard let store = session?.store, store.activeFloorId != floorID,
              store.model.floors.contains(where: { $0.id == floorID }) else { return }
        store.setActiveFloor(floorID)
        viewStateHolder.activeFloorID = floorID
        controller?.dollhouse?.setActiveFloor(floorID, animated: false)
        overlayHolder.overlay?.refreshFloorFocus()
        controller?.scnView.setNeedsDisplay()
    }

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
        steppedTourIndex = nil
        // Restore floor focus the tour suspended.
        reapplyViewState()
    }

    // MARK: - Placement hint

    @ViewBuilder
    private func placementHint(kind: OpeningKind) -> some View {
        let text = "Tap a wall to place the \(kind.rawValue). "
            + "Interior vs. exterior is automatic."
        let icon = Image(systemName: kind == .door ? "door.left.hand.open"
                                                   : "window.vertical.open")
            .accessibilityHidden(true)
        let message = Text(text)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        let cancel = Button("Cancel") { tool = .select }
            .font(.caption.bold())
            .minimumTapTarget()
            .accessibilityLabel("Cancel placing the \(kind.rawValue)")
            .accessibilityIdentifier("house.placement.cancel")

        return ViewThatFits(in: .horizontal) {
            HStack {
                icon
                message
                Spacer()
                cancel
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    icon
                    message
                }
                cancel
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
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
                            // Was a hard `.lineLimit(1)`: at the accessibility text sizes a
                            // real room name ("Downstairs Back Bedroom") lost its tail, and the
                            // truncation hid which room you were about to rename or delete.
                            .lineLimit(dynamicTypeSize >= .accessibility1 ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .minimumTapTarget()
                    .accessibilityLabel("Rename \(room.name)")
                    .accessibilityHint("Opens a text field for a new room name.")
                    .accessibilityIdentifier("house.inspector.renameRoom")
                    Picker("Type", selection: Binding(
                        get: { room.type },
                        set: { dispatch(.setRoomType(roomId: roomId, type: $0)) }
                    )) {
                        ForEach(RoomType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Room type")
                    .accessibilityValue(room.type.rawValue.capitalized)
                    .accessibilityHint("Bedrooms and kitchens change how the engine plans "
                                       + "around this room.")
                    .accessibilityIdentifier("house.inspector.roomType")
                    Spacer()
                    Button(role: .destructive) {
                        dispatch(.deleteRoom(roomId: roomId))
                    } label: {
                        Label("Delete Room", systemImage: "trash").labelStyle(.iconOnly)
                    }
                    .minimumTapTarget()
                    .accessibilityLabel("Delete \(room.name)")
                    .accessibilityHint("Removes the room and everything attached to it.")
                    .accessibilityIdentifier("house.inspector.deleteRoom")
                }
            }
        case .opening(let openingId):
            if let opening = store.activeFloor.openings.first(where: { $0.id == openingId }) {
                VStack(spacing: 0) {
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
                        // A hard 180pt segmented control clipped "Window" at the accessibility
                        // sizes; the cap only applies while the text still fits inside it.
                        .frame(maxWidth: dynamicTypeSize >= .accessibility1 ? .infinity : 180)
                        .accessibilityLabel("Opening kind")
                        .accessibilityHint("Doors and windows are routed differently by the engine.")
                        .accessibilityIdentifier("house.inspector.openingKind")
                        Text(opening.isExit ? "Exterior" : "Interior")
                            .font(.caption)
                            .foregroundStyle(Theme.supporting)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(opening.isExit
                                ? "This opening leads outside — the engine can use it as an exit."
                                : "Interior opening.")
                        Spacer()
                        Button(role: .destructive) {
                            dispatch(.deleteOpening(openingId: openingId))
                        } label: {
                            Label("Delete Opening", systemImage: "trash").labelStyle(.iconOnly)
                        }
                        .minimumTapTarget()
                        .accessibilityLabel("Delete this \(opening.kind.rawValue)")
                        .accessibilityHint("Removes it from the wall and re-plans the routes.")
                        .accessibilityIdentifier("house.inspector.deleteOpening")
                    }
                    inspectorBar {
                        Stepper(value: Binding(
                            get: { opening.width_m },
                            set: { dispatch(.setOpeningWidth(openingId: openingId, width_m: $0)) }
                        ), in: 0.1...10, step: 0.1) {
                            Text("Width: \(opening.width_m, specifier: "%.2f")m")
                        }
                        .accessibilityIdentifier("house.inspector.openingWidth")
                    }
                }
            }
        case .stairs(let stairsId):
            inspectorBar {
                Label("Stairs", systemImage: "figure.stairs")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(role: .destructive) {
                    dispatch(.deleteStairs(stairsId: stairsId))
                } label: {
                    Label("Delete Stairs", systemImage: "trash").labelStyle(.iconOnly)
                }
                .minimumTapTarget()
                .accessibilityLabel("Delete these stairs")
                .accessibilityHint("Removes the link between the two floors and re-plans "
                                   + "the routes.")
                .accessibilityIdentifier("house.inspector.deleteStairs")
            }
        case .object(let objectId):
            if let object = store.model.floors.flatMap(\.objects).first(where: { $0.id == objectId }) {
                VStack(spacing: 0) {
                    inspectorBar {
                        Picker("Type", selection: Binding(
                            get: { object.category },
                            set: { dispatch(.setObjectCategory(objectId: objectId, category: $0)) }
                        )) {
                            ForEach(ObjectCategory.allCases, id: \.self) { category in
                                Text(category.displayName).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("Object type")
                        .accessibilityValue(object.category.displayName)
                        .accessibilityIdentifier("house.inspector.objectType")
                        Button {
                            dispatch(.rotateObject(objectId: objectId,
                                                   rotation_deg: (object.rotation_deg + 45)
                                                       .truncatingRemainder(dividingBy: 360)))
                        } label: {
                            Label("Rotate 45°", systemImage: "rotate.right")
                                .labelStyle(.iconOnly)
                        }
                        .minimumTapTarget()
                        .accessibilityLabel("Rotate 45 degrees")
                        .accessibilityValue("\(Int(object.rotation_deg)) degrees")
                        .accessibilityIdentifier("house.inspector.rotateObject")
                        Spacer()
                        Button(role: .destructive) {
                            dispatch(.deleteObject(objectId: objectId))
                        } label: {
                            Label("Delete Object", systemImage: "trash").labelStyle(.iconOnly)
                        }
                        .minimumTapTarget()
                        .accessibilityLabel("Delete this \(object.category.rawValue)")
                        .accessibilityIdentifier("house.inspector.deleteObject")
                    }
                    inspectorBar {
                        Toggle("Strapped to the wall?", isOn: Binding(
                            get: { object.secured },
                            set: { dispatch(.setObjectSecured(objectId: objectId, secured: $0)) }
                        ))
                        .accessibilityIdentifier("house.inspector.secured")
                    }
                    inspectorBar {
                        Stepper(value: Binding(
                            get: { object.size_m[0] },
                            set: { dispatch(.resizeObject(objectId: objectId, size_m: [$0, object.size_m[1]], height_m: object.height_m)) }
                        ), in: 0.1...10, step: 0.1) {
                            Text("W: \(object.size_m[0], specifier: "%.2f")m")
                        }
                        .accessibilityIdentifier("house.inspector.width")
                        
                        Stepper(value: Binding(
                            get: { object.size_m[1] },
                            set: { dispatch(.resizeObject(objectId: objectId, size_m: [object.size_m[0], $0], height_m: object.height_m)) }
                        ), in: 0.1...10, step: 0.1) {
                            Text("D: \(object.size_m[1], specifier: "%.2f")m")
                        }
                        .accessibilityIdentifier("house.inspector.depth")
                    }
                    inspectorBar {
                        Stepper(value: Binding(
                            get: { object.height_m },
                            set: { dispatch(.resizeObject(objectId: objectId, size_m: object.size_m, height_m: $0)) }
                        ), in: 0.1...10, step: 0.1) {
                            Text("H: \(object.height_m, specifier: "%.2f")m")
                        }
                        .accessibilityIdentifier("house.inspector.height")
                        
                        if [.tv, .storage, .bookcase, .appliance, .heat_source, .other].contains(object.category) {
                            Toggle("Mounted", isOn: Binding(
                                get: { object.mounted },
                                set: { dispatch(.setObjectMounted(objectId: objectId, mounted: $0)) }
                            ))
                            .accessibilityIdentifier("house.inspector.mounted")
                        }
                    }
                    if object.mounted {
                        inspectorBar {
                            Stepper(value: Binding(
                                get: { object.elevation_m },
                                set: { dispatch(.setObjectElevation(objectId: objectId, elevation_m: $0)) }
                            ), in: 0.0...10, step: 0.1) {
                                Text("Elevation: \(object.elevation_m, specifier: "%.2f")m")
                            }
                            .accessibilityIdentifier("house.inspector.elevation")
                        }
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
            .accessibilityLabel("Undo")
            .accessibilityHint("Reverses the last edit to the home and re-plans the routes.")
            .accessibilityIdentifier("house.undo")
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!(session?.undoStack.canRedo ?? false))
            .accessibilityLabel("Redo")
            .accessibilityHint("Re-applies the edit you just undid.")
            .accessibilityIdentifier("house.redo")
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
            .accessibilityLabel("Add to the home")
            .accessibilityHint("Rooms, doors, windows, objects, stairs and floors.")
            .accessibilityIdentifier("house.addMenu")
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
            .accessibilityLabel("More actions")
            .accessibilityHint("Rename the home or the floor, or delete this floor.")
            .accessibilityIdentifier("house.moreMenu")
        }
    }

    // MARK: - Loading & saving

    private func loadIfNeeded() {
        guard session == nil, loadError == nil, !homeWasDeleted else { return }
        do {
            var controller: HouseEditorSessionController?
            var loaded: HomeModel?
            if let homeID, let documentStore {
                let existing = HouseEditorSessionController(homeID: homeID, disk: documentStore)
                loaded = try existing.open()
                if loaded != nil { controller = existing }
            }
            let model = loaded ?? Self.blankHome()
            if controller == nil, let documentStore {
                // A brand-new home: no file yet, so its first save creates it.
                controller = HouseEditorSessionController(homeID: model.home_id, disk: documentStore)
            }
            let newStore = try HomeModelStore(model: model)
            let newSession = EditorSession(store: newStore)
            // The controller is captured, not read back from @State: this closure outlives the
            // copy of the view it was created in.
            newStore.onCommit = { [controller] _commit in
                newSession.undoStack.recordCommit(_commit)
                autosave(newSession, controller: controller)
                invalidateRoutes()
            }
            session = newSession
            sessionController = controller
            // Arms `library.editor` and sync's `openHomeID` before the first autosave: a pull
            // that landed between here and the next frame would otherwise write the server's
            // copy over the file this editor is about to save into.
            controller?.registration = HouseEditorAppRegistration(
                session: newSession, library: library, syncRepository: syncRepository)
            if let controller { handle(controller.appear(), in: newSession, controller: controller) }
            // A brand-new home is NOT written here. Its first committed edit creates the file
            // (`onCommit` → `autosave`), so opening Build Manually and backing out leaves nothing
            // behind (S11.21, AUD-021). Writing on open is how blank "New Home"s piled up, and
            // each one uploaded to the account on the next sync.
            fetchRoutes()
            applyCachedHazardEmphasis(for: newSession, focusing: initialFocusItemID)
        } catch HomeModelStore.StoreError.invalidInitialModel(let issues) {
            // A home over a size bound (S11.25) is refused by the store. Say why in its own
            // words rather than dumping the error.
            if let bound = issues.first(where: { $0.kind == .sizeBounds }) {
                loadError = "This home is too large to edit: \(Self.sentence(bound.message))"
            } else {
                loadError = "This home has a problem the editor can't open: \(Self.sentence(issues.first?.message ?? "unknown"))"
            }
        } catch {
            loadError = "\(error)"
        }
    }

    /// Advisory emphasis and finding→object focus both key off the cached score: the engine
    /// decided what is hazardous, this screen only draws what it was told.
    ///
    /// Skipped for an unreviewed AI draft: drafts are never scored (S11.17), so any cache entry
    /// for one is left over from before that fix and describes a home nobody confirmed.
    private func applyCachedHazardEmphasis(for session: EditorSession, focusing itemID: String?) {
        let model = session.store.model
        guard !model.hasAIDraftContent, let cache = try? ScoreCache(),
              let score = cache.load(homeID: model.home_id) else {
            hazardObjectIDs = []
            controller?.setHazardObjects(hazardObjectIDs)
            return
        }
        hazardObjectIDs = Set(score.checklist
            .filter { $0.id.hasPrefix("hazard.") }
            .flatMap { $0.objectIDs(in: model) })
        controller?.setHazardObjects(hazardObjectIDs)

        if let itemID,
           let target = score.checklist.first(where: { $0.id == itemID })?.objectIDs(in: model).first {
            initialSelection = .object(objectId: target)
            session.store.select(.object(objectId: target))
        }
    }

    /// Back from another tab with a live session: re-arm the guard, then pick up any change
    /// another writer made while House was away (onboarding, re-scan, sync, Profiles).
    private func resumeSession() {
        guard let session, let sessionController else { return }
        handle(sessionController.appear(), in: session, controller: sessionController)
    }

    private func handle(_ state: HouseEditorSessionController.DiskState, in session: EditorSession,
                        controller: HouseEditorSessionController) {
        switch state {
        case .current:
            break
        case .changed(let newer):
            adoptExternalChange(newer, in: session, controller: controller,
                                notice: Self.reloadedNotice)
            onModelChanged?()
        case .deleted:
            closeForDeletedHome(session, controller: controller)
        case .unreadable:
            saveError = Self.unreadableNotice
        }
    }

    // User-facing copy: "home", never "plan" (in this app a plan is the escape plan).
    private static let reloadedNotice =
        "This home was changed on another screen or device, so the newer version is shown. Undo history was cleared."
    private static let editDroppedNotice =
        "This home was changed on another screen or device, so your last change was not saved and the newer version is shown. Undo history was cleared."
    private static let unreadableNotice =
        "This home's file can't be read, so changes aren't being saved."

    /// A validation message as a sentence: some already end in a full stop, some don't.
    private static func sentence(_ message: String) -> String {
        message.hasSuffix(".") ? message : message + "."
    }

    /// Replaces the session's model with the newer file. The undo history goes: its snapshots
    /// describe a document that no longer exists, and undoing into one would write it back.
    private func adoptExternalChange(_ newer: HomeModel, in session: EditorSession,
                                     controller: HouseEditorSessionController, notice: String) {
        session.undoStack.reset()
        guard session.store.replaceModel(newer).didApply else {
            // The newer file does not validate (over a bound, say). Never edit it from here:
            // close the controller too, so a commit still in flight on the old store (a drag
            // frame) can never write the old model over the newer file.
            controller.close()
            self.session = nil
            loadError = "This home was changed on another screen or device and can't be opened here."
            return
        }
        externalChangeNotice = notice
        invalidateRoutes()
        applyCachedHazardEmphasis(for: session, focusing: nil)
    }

    /// The home's file is gone. Drop the session and close the controller for good.
    private func closeForDeletedHome(_ session: EditorSession, controller: HouseEditorSessionController?) {
        session.undoStack.reset()
        controller?.close()
        self.session = nil
        homeWasDeleted = true
        invalidateRoutes()
    }

    private func autosave(_ session: EditorSession, controller: HouseEditorSessionController?) {
        // No controller means no library, which is the preview alone: nothing is saved.
        guard let controller else { return }
        switch controller.save(session.store.model) {
        case .saved:
            saveError = nil
            externalChangeNotice = nil
        case .reloaded(let newer):
            adoptExternalChange(newer, in: session, controller: controller, notice: Self.editDroppedNotice)
        case .deleted:
            closeForDeletedHome(session, controller: controller)
        case .failed(let reason):
            saveError = reason
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
        autosave(session, controller: sessionController)
        invalidateRoutes()
    }

    private func redo() {
        guard let session, session.undoStack.redo(on: session.store) else { return }
        autosave(session, controller: sessionController)
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

// MARK: - The 3D scene, in words

/// What VoiceOver reads instead of the dollhouse, and what the "Route steps" sheet lists.
///
/// **The acceptance criterion this exists for:** a VoiceOver user must be able to hear their
/// route as an ordered list of steps. A SceneKit surface is an opaque rectangle to a screen
/// reader — there is nothing to swipe to and nothing to read — so the scene becomes ONE
/// labelled element with a summary, and the steps live in a real, focusable control that never
/// requires touching the 3D at all.
///
/// Pure and view-free on purpose, so `A11yHouseSceneTests` can assert the exact strings without
/// a running scene, a simulator window, or a timeline. Nothing here invents safety content:
///
///   * the ordered steps come from `RouteNarration` (one narrator, shared with the printable
///     PDF — never a second, drifting copy), and
///   * the NUMBERS come from `RouteGeometry.numberedStops`, the same pure function that
///     produces `RouteOverlay.drawnSteps` and therefore the numbered chips drawn on the model.
///     So "step 3" spoken is the circled 3 a sighted user is looking at.
///
/// The one thing that is NOT unified: `RouteNarration` and `RouteGeometry` number different
/// things. The drawing numbers every meaningful waypoint including "you start here"; the
/// narration numbers instructions, and standing still is not an instruction, so it skips the
/// start and folds an exterior waypoint into the doorway step that reaches it. Rather than
/// keep two numberings, the drawn numbering wins (it is the one on screen) and each narration
/// sentence is attached to the stop it happens at, matched on the waypoint the engine emitted.
/// Collapsing the two numbering schemes at the source would mean editing
/// `RouteGeometry.numberedStops`, which is outside this lane's fence.
enum HouseSceneAccessibility {

    /// Everything the scene summary says about a running simulation.
    ///
    /// The wording of the hazard lines deliberately matches the finding cards
    /// (`RouteFindingStyle.overtakenByHazard` — "Hazard reaches them first"). A screen reader
    /// gets the same honest sentence a sighted user gets; it is never softened for being
    /// spoken, and it is never withheld until the animation finishes.
    struct SimulationState: Equatable {
        var originRoomName: String
        var isPlaying: Bool
        var elapsedSpoken: String
        var durationSpoken: String
        /// Rooms the ENGINE models as untenable at the current playhead, resolved to names.
        var untenableRoomNames: [String] = []
        /// People the ENGINE flagged `overtaken_by_hazard`.
        var overtakenPeopleNames: [String] = []
    }

    /// One row of the ordered route-steps list.
    struct StepLine: Equatable, Identifiable {
        /// Matches the numbered chip drawn on the model.
        var number: Int
        /// The chip's own caption text ("Through the doorway").
        var title: String
        /// The narrated instruction for that moment, when there is one. The start of a route
        /// has no instruction, by design.
        var detail: String?

        var id: Int { number }

        /// "2. Through the doorway. Leave the Bedroom through the door into the Hall."
        var spoken: String {
            guard let detail, !detail.isEmpty else { return "\(number). \(title)" }
            return "\(number). \(title). \(detail)"
        }
    }

    // MARK: - Scene summary

    /// The summary label for the SceneKit surface.
    ///
    /// Order is deliberate: what the object is, where you are in it, what is drawn, and only
    /// then the simulation — because the simulation lines are the longest and a screen reader
    /// user must not have to sit through them to learn which floor they are on.
    static func sceneLabel(homeName: String,
                           floorName: String,
                           floorNumber: Int,
                           floorCount: Int,
                           roomCount: Int,
                           personName: String?,
                           roomName: String?,
                           hasRoutes: Bool,
                           simulation: SimulationState?) -> String {
        var parts: [String] = ["3D model of \(homeName)."]

        let floorLabel = floorName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "this floor" : floorName
        let rooms = "\(roomCount) \(roomCount == 1 ? "room" : "rooms")"
        parts.append(floorCount > 1
            ? "Showing \(floorLabel), floor \(floorNumber) of \(floorCount), \(rooms)."
            : "\(floorLabel), \(rooms).")

        parts.append(routeSentence(personName: personName,
                                   roomName: roomName,
                                   hasRoutes: hasRoutes))

        if let simulation {
            parts.append(contentsOf: simulationSentences(simulation))
        }
        return parts.joined(separator: " ")
    }

    private static func routeSentence(personName: String?,
                                      roomName: String?,
                                      hasRoutes: Bool) -> String {
        guard hasRoutes else {
            return "No escape routes are drawn yet."
        }
        switch (personName, roomName) {
        case let (person?, room?):
            return "Showing the escape route for \(person), starting in the \(room)."
        case let (person?, nil):
            return "Showing the escape route for \(person)."
        case let (nil, room?):
            return "Showing the escape route from the \(room)."
        case (nil, nil):
            return "Showing the primary escape route for everyone."
        }
    }

    private static func simulationSentences(_ state: SimulationState) -> [String] {
        var parts = ["Fire simulation loaded. The fire starts in the \(state.originRoomName).",
                     "\(state.elapsedSpoken) of \(state.durationSpoken), "
                     + "\(state.isPlaying ? "playing" : "paused")."]

        if state.untenableRoomNames.isEmpty {
            parts.append("No rooms are untenable yet at this point in the simulation.")
        } else {
            let count = state.untenableRoomNames.count
            parts.append("The engine models \(count) \(count == 1 ? "room" : "rooms") as "
                         + "untenable at this point: \(list(state.untenableRoomNames)).")
        }

        if !state.overtakenPeopleNames.isEmpty {
            let names = list(state.overtakenPeopleNames)
            parts.append(state.overtakenPeopleNames.count == 1
                ? "Hazard reaches them first: in this simulation the modeled fire reaches a "
                  + "room on \(names)'s way out before they clear it."
                : "Hazard reaches them first: in this simulation the modeled fire reaches a "
                  + "room on the way out of \(names) before they clear it.")
        }
        return parts
    }

    /// "Kitchen, Hall and Landing" — Oxford-free, because VoiceOver reads the comma anyway.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    // MARK: - Ordered steps

    /// The ordered steps for one room's primary route.
    ///
    /// `drawn` is `RouteOverlay.drawnSteps[room_id]` — the chips literally on screen. When the
    /// overlay has not drawn that room (nothing selected yet, or a rebuild in flight) the same
    /// pure function the overlay uses is called directly, so the numbering is identical either
    /// way rather than merely similar.
    static func steps(for room: RoomRoutePlan,
                      in home: HomeModel,
                      drawn: [RouteGeometry.Stop]?,
                      meetingPoint: String? = nil) -> [StepLine] {
        guard let primary = room.primary else { return [] }
        let stops = drawn ?? RouteGeometry.numberedStops(for: primary)
        let anchors = RouteNarration.stepAnchors(for: primary, startingIn: room.room_id)
        let sentences = RouteNarration.sentences(for: primary, from: room.room_id,
                                                 in: home, meetingPoint: meetingPoint)

        var used = Set<Int>()
        var lines: [StepLine] = stops.map { stop in
            let match = anchors.first { anchor in
                !used.contains(anchor.number) && anchor.waypoint == stop.waypoint
            }
            var detail: String?
            if let match, sentences.indices.contains(match.number - 1) {
                used.insert(match.number)
                detail = sentences[match.number - 1]
            }
            return StepLine(number: stop.number, title: stop.kind.title, detail: detail)
        }

        // Anything the narration says that has no chip on the model — most importantly the
        // meeting-point step, which is outside the building and deliberately undrawn. It is
        // appended rather than dropped: "and then go to the oak across the street" is the last
        // thing a household needs to hear, not the first thing to lose to a layout rule.
        var next = (lines.last?.number ?? 0) + 1
        for (index, sentence) in sentences.enumerated() where !used.contains(index + 1) {
            lines.append(StepLine(number: next, title: sentence, detail: nil))
            next += 1
        }
        return lines
    }

    /// The whole route spoken as one string — used for the scene element's custom action
    /// announcement and by anything that wants the narration in a single utterance.
    static func spokenSteps(for room: RoomRoutePlan,
                            in home: HomeModel,
                            drawn: [RouteGeometry.Stop]?,
                            meetingPoint: String? = nil) -> String {
        let lines = steps(for: room, in: home, drawn: drawn, meetingPoint: meetingPoint)
        guard !lines.isEmpty else {
            return "The routing engine returned no route for the \(room.room_name)."
        }
        return (["Route from the \(room.room_name), \(lines.count) steps."]
                + lines.map(\.spoken)).joined(separator: " ")
    }
}

#Preview {
    HouseScreen(homeID: nil)
        .environment(APIClient())
}

/// Reports the dock's scroll offset (0 at rest, growing as content scrolls up). iOS 18+ reads
/// it straight from the scroll geometry; iOS 17 falls back to the two global-space top edges
/// (content, viewport) — the classic preference pattern, which the newer ScrollView no longer
/// re-emits on scroll, hence the split.
private struct DockScrollOffsetReader: ViewModifier {
    let onChange: (CGFloat) -> Void
    @State private var contentTop: CGFloat = 0
    @State private var viewportTop: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                onChange(offset)
            }
        } else {
            content
                .background(GeometryReader { viewport in
                    Color.clear.preference(key: DockViewportTopKey.self,
                                           value: viewport.frame(in: .global).minY)
                })
                .onPreferenceChange(DockContentTopKey.self) { top in
                    contentTop = top
                    onChange(viewportTop - contentTop)
                }
                .onPreferenceChange(DockViewportTopKey.self) { top in
                    viewportTop = top
                    onChange(viewportTop - contentTop)
                }
        }
    }
}

/// Global-space top edges of the dock's content and of the dock itself (iOS 17 fallback).
private struct DockContentTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct DockViewportTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
