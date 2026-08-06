//  UnifiedSceneView.swift
//
//  The one 3D surface for the unified viewer+editor: whole translucent house, free orbit
//  camera. Replaces DollhouseSceneView's `allowsCameraControl` with the hand-rolled
//  `OrbitCameraRig` — required so (A2) editing drags and camera drags can share the same
//  gestures, and so pinch can zoom toward the pinch point instead of the scene center.
//
//  Gesture map (A1 — camera only; A2 adds selection/editing on top):
//    one-finger drag  → orbit
//    two-finger drag  → truck (pan)
//    pinch            → zoom toward the pinch point

import SceneKit
import SwiftUI

struct UnifiedSceneView: UIViewRepresentable {
    let dollhouse: DollhouseScene
    let home: HomeModel
    var hiddenFloorIDs: Set<String>
    /// The floor in focus: it renders solid, every other floor ghosts to a translucent shell.
    /// Replaces the old explode slider and per-floor fade map — see `DollhouseScene`.
    var activeFloorID: String?
    /// The route overlay's pulse shader animates on `u_time`, which only advances while the
    /// view redraws — flip this on while routes are shown, off for the static scene.
    var wantsContinuousRendering: Bool = false
    /// While the camera tour owns `pointOfView`, SwiftUI updates must not reset it.
    var isTouring: Bool = false
    /// Hands the backing SCNView and rig to the owner (tour needs both). Called async so
    /// setting @State from it doesn't mutate state mid-view-update.
    var onViewReady: ((SCNView, OrbitCameraRig) -> Void)? = nil

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = dollhouse.scene
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = DollhousePalette.background
        // The scene is static between edits; only redraw when something actually changes.
        view.rendersContinuously = wantsContinuousRendering

        let rig = OrbitCameraRig(home: home)
        rig.attach(to: dollhouse.scene, view: view)
        context.coordinator.install(on: view, rig: rig, home: home)
        context.coordinator.wantsContinuousRendering = wantsContinuousRendering

        apply(to: view, context: context)
        if let onViewReady {
            DispatchQueue.main.async { onViewReady(view, rig) }
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let rig = context.coordinator.rig else { return }
        if view.scene !== dollhouse.scene {
            // A rebuilt scene (new home or, later, an edit): keep the camera exactly where
            // the user left it by re-attaching the persistent rig node.
            let isNewHome = context.coordinator.homeID != home.home_id
            view.scene = dollhouse.scene
            if isNewHome {
                rig.reframe(for: home)
                context.coordinator.homeID = home.home_id
            }
            rig.attach(to: dollhouse.scene, view: view)
            if let onViewReady {
                DispatchQueue.main.async { onViewReady(view, rig) }
            }
        }
        context.coordinator.wantsContinuousRendering = wantsContinuousRendering
        context.coordinator.gesturesEnabled = !isTouring
        apply(to: view, context: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(homeID: home.home_id)
    }

    /// Push the floor-visibility state into the scene — but only when it has actually changed.
    ///
    /// SwiftUI calls `updateUIView` for reasons that have nothing to do with this view (any
    /// `@State` on the host, a playback clock tick, a re-layout). This used to sweep every
    /// floor and call `setNeedsDisplay` on each one of those, so unrelated state churn landed
    /// directly on a drag's frames. The inputs are cached and compared; unchanged is free.
    private func apply(to view: SCNView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.appliedHiddenFloorIDs != hiddenFloorIDs
                || coordinator.appliedActiveFloorID != activeFloorID
                || coordinator.appliedSceneID != ObjectIdentifier(dollhouse.scene) else { return }
        // Deferred rather than dropped: the same state is re-applied the moment the finger
        // lifts, so a floor toggled mid-drag still lands, just not on the drag's frames.
        guard !coordinator.isCameraGestureInFlight else {
            coordinator.deferredSceneWork = { [dollhouse, hiddenFloorIDs, activeFloorID] in
                Self.applyNow(hidden: hiddenFloorIDs, active: activeFloorID,
                              dollhouse: dollhouse, to: view, coordinator: coordinator)
            }
            return
        }
        Self.applyNow(hidden: hiddenFloorIDs, active: activeFloorID,
                      dollhouse: dollhouse, to: view, coordinator: coordinator)
    }

    private static func applyNow(hidden: Set<String>, active: String?, dollhouse: DollhouseScene,
                                 to view: SCNView, coordinator: Coordinator) {
        for floor in dollhouse.floors {
            dollhouse.setFloor(floor.id, visible: !hidden.contains(floor.id))
        }
        // Only re-focus when the selection actually changed: setActiveFloor animates, and
        // SwiftUI calls updateUIView far more often than the floor changes.
        if let active, active != dollhouse.activeFloorID {
            dollhouse.setActiveFloor(active)
        }
        coordinator.appliedHiddenFloorIDs = hidden
        coordinator.appliedActiveFloorID = active
        coordinator.appliedSceneID = ObjectIdentifier(dollhouse.scene)
        view.setNeedsDisplay()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var rig: OrbitCameraRig?
        var homeID: String
        var gesturesEnabled = true
        private weak var view: SCNView?
        private var cameraGestures: CameraGestureDriver?
        /// The home the double-tap recenter needs; set by `install`.
        private var home: HomeModel?

        /// Last floor state actually pushed into the scene — the memo behind `apply`'s
        /// early-exit. `appliedSceneID` catches a rebuilt scene, whose floors need the state
        /// re-applied even though the inputs did not change.
        var appliedHiddenFloorIDs: Set<String>?
        var appliedActiveFloorID: String?
        var appliedSceneID: ObjectIdentifier?

        private(set) var isCameraGestureInFlight = false
        var deferredSceneWork: (() -> Void)?

        /// The scene's own reason to keep drawing (route pulse, playback). OR'd with the
        /// camera's — see `syncContinuousRendering`.
        var wantsContinuousRendering = false {
            didSet {
                guard wantsContinuousRendering != oldValue else { return }
                syncContinuousRendering()
                view?.setNeedsDisplay()
            }
        }
        private var cameraWantsContinuousRendering = false

        init(homeID: String) {
            self.homeID = homeID
        }

        func install(on view: SCNView, rig: OrbitCameraRig, home: HomeModel) {
            self.view = view
            self.rig = rig
            self.home = home

            // This surface used to wire none of the rig's feedback: no redraw hook and no
            // continuous-rendering sink, so any frame the rig drove itself (inertia, the
            // spring-back) was computed and never drawn.
            rig.onChange = { [weak view] in view?.setNeedsDisplay() }
            rig.continuousRenderingSink = { [weak self] cameraIsMoving in
                self?.cameraWantsContinuousRendering = cameraIsMoving
                self?.syncContinuousRendering()
            }

            let driver = CameraGestureDriver(rig: rig)
            driver.onPhaseChange = { [weak self] inFlight in
                self?.setCameraGestureInFlight(inFlight)
            }
            cameraGestures = driver

            // ONE pan for both touch counts; `CameraGestureDriver` decides orbit vs truck from
            // live touch count, so this surface and the editor's cannot diverge again.
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            view.addGestureRecognizer(pan)

            // Pinch and pan run together: a real pinch usually drifts, and a real two-finger
            // pan usually scales a little — requiring exclusivity makes both feel broken.
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            // Double-tap to zoom in / recenter, same as the editor surface.
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)
        }

        private func syncContinuousRendering() {
            view?.rendersContinuously = wantsContinuousRendering || cameraWantsContinuousRendering
        }

        private func setCameraGestureInFlight(_ inFlight: Bool) {
            let wasInFlight = isCameraGestureInFlight
            isCameraGestureInFlight = inFlight
            guard wasInFlight, !inFlight, let work = deferredSceneWork else { return }
            deferredSceneWork = nil
            work()
        }

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            guard gesturesEnabled, let view, let cameraGestures else { return }
            cameraGestures.handlePan(g, in: view)
        }

        @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard gesturesEnabled, let view, let cameraGestures else { return }
            cameraGestures.handlePinch(g, in: view)
        }

        @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard gesturesEnabled, let view, let cameraGestures, let home else { return }
            cameraGestures.handleDoubleTap(at: g.location(in: view), in: view, home: home)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Pinch + pan combine (two-finger zoom-and-truck); everything else is exclusive.
            let pair = [gestureRecognizer, other]
            let hasPinch = pair.contains { $0 is UIPinchGestureRecognizer }
            let hasPan = pair.contains { $0 is UIPanGestureRecognizer }
            return hasPinch && hasPan
        }
    }
}
