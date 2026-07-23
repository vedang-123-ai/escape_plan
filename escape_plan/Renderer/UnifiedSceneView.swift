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
    var explode: Double
    var hiddenFloorIDs: Set<String>
    /// Floors faded (not hidden) to spotlight another floor. id → opacity.
    var floorFades: [String: Double] = [:]
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
        context.coordinator.install(on: view, rig: rig)

        apply(to: view)
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
            if isTouring {
                // Attach set pointOfView to the rig; the tour node owns it until it finishes.
            }
            if let onViewReady {
                DispatchQueue.main.async { onViewReady(view, rig) }
            }
        }
        view.rendersContinuously = wantsContinuousRendering
        context.coordinator.gesturesEnabled = !isTouring
        apply(to: view)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(homeID: home.home_id)
    }

    private func apply(to view: SCNView) {
        dollhouse.setExplode(explode)
        for floor in dollhouse.floors {
            dollhouse.setFloor(floor.id, visible: !hiddenFloorIDs.contains(floor.id))
            dollhouse.setFloorFade(floor.id, opacity: floorFades[floor.id] ?? 1.0)
        }
        view.setNeedsDisplay()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var rig: OrbitCameraRig?
        var homeID: String
        var gesturesEnabled = true
        private weak var view: SCNView?

        init(homeID: String) {
            self.homeID = homeID
        }

        func install(on view: SCNView, rig: OrbitCameraRig) {
            self.view = view
            self.rig = rig

            let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
            orbit.minimumNumberOfTouches = 1
            orbit.maximumNumberOfTouches = 1
            view.addGestureRecognizer(orbit)

            let truck = UIPanGestureRecognizer(target: self, action: #selector(handleTruck(_:)))
            truck.minimumNumberOfTouches = 2
            truck.maximumNumberOfTouches = 2
            view.addGestureRecognizer(truck)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            // Pinch and two-finger pan run together: a real pinch usually drifts, and a real
            // two-finger pan usually scales a little — requiring exclusivity makes both feel
            // broken. Zoom-toward-point plus simultaneous truck is the expected combined feel.
            truck.delegate = self
        }

        @objc private func handleOrbit(_ g: UIPanGestureRecognizer) {
            guard gesturesEnabled, let view, let rig else { return }
            let delta = g.translation(in: view)
            g.setTranslation(.zero, in: view)
            rig.orbit(byScreenDelta: delta, in: view)
            view.setNeedsDisplay()
        }

        @objc private func handleTruck(_ g: UIPanGestureRecognizer) {
            guard gesturesEnabled, let view, let rig else { return }
            let delta = g.translation(in: view)
            g.setTranslation(.zero, in: view)
            rig.truck(byScreenDelta: delta, in: view)
            view.setNeedsDisplay()
        }

        @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard gesturesEnabled, let view, let rig else { return }
            rig.pinch(scale: g.scale, centroid: g.location(in: view), in: view)
            g.scale = 1
            view.setNeedsDisplay()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Only pinch + two-finger truck combine; orbit stays exclusive.
            let pair = [gestureRecognizer, other]
            let hasPinch = pair.contains { $0 is UIPinchGestureRecognizer }
            let hasTruck = pair.contains { ($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2 }
            return hasPinch && hasTruck
        }
    }
}
