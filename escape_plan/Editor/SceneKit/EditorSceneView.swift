//  EditorSceneView.swift
//
//  SwiftUI host for the unified editor: the free-orbit perspective dollhouse
//  (`UnifiedSceneController` + `OrbitCameraRig`) with editing driven through
//  `SceneKitEditorBridge`. There is no edit mode: `GestureArbiter` decides at .began whether
//  a one-finger pan edits (it landed on the current selection) or orbits, and the answer is
//  latched for the whole gesture. Two-finger pan trucks, pinch zooms toward the pinch point.
//
//  `model`/`activeFloorId`/`selection` are passed BY VALUE alongside the store: the store is
//  @Observable, so the parent body re-evaluates on every change, and the changed values here
//  are what make SwiftUI call `updateUIView` (a reference-typed store alone would never look
//  different to the representable's diff).

import SwiftUI

#if canImport(SceneKit) && canImport(UIKit)
import SceneKit
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A pan that remembers where the touch actually went down. By the time a pan RECOGNIZES,
/// the finger has moved ~10 pt, and `translation` does not fully cover that slop — so
/// `location − translation` is NOT the press point. Arbitration and edit-drag anchoring need
/// the true one: at typical zooms 10 pt is enough to cross to a neighboring room's vertex.
final class InitialPointPanGestureRecognizer: UIPanGestureRecognizer {
    private(set) var initialTouchPoint: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if initialTouchPoint == nil, let touch = touches.first, let view {
            initialTouchPoint = touch.location(in: view)
        }
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        initialTouchPoint = nil
        super.reset()
    }
}

struct EditorSceneView: UIViewRepresentable {
    let store: HomeModelStore
    let model: HomeModel
    let activeFloorId: String
    let selection: Selection
    var tool: EditorTool = .select
    /// False while the camera tour owns `pointOfView` — gestures and edits pause.
    var interactionEnabled: Bool = true
    let undoStack: UndoStack
    /// Called after a `.placeOpening` tap successfully adds its opening, so the screen can
    /// disarm the tool (placement is one-shot).
    var onOpeningPlaced: (() -> Void)?
    /// Hands the live controller to the owner (async, once) — HouseScreen hangs the route
    /// overlay and camera tour off it.
    var onControllerReady: ((UnifiedSceneController) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        // Lets UI automation (the manual-build recording driver) find the scene surface and
        // convert floor-plan meters into tap coordinates.
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "editor.scene"
        let controller = UnifiedSceneController(scnView: view, home: store.model)
        context.coordinator.controller = controller
        context.coordinator.bridge = SceneKitEditorBridge(store: store, scene: controller, undoStack: undoStack)
        context.coordinator.installCameraGestures(on: controller)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        // A single tap must not wait on the double-tap unless a second tap is actually coming.
        tap.require(toFail: doubleTap)

        // ONE pan for both fingers-counts, branched at .began — a `maximumNumberOfTouches`
        // split into two recognizers silently swallowed XCUITest's synthesized press-drags
        // (the pan never left .possible), and a single unconstrained pan is also what the old
        // editor shipped with.
        let pan = InitialPointPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        controller.currentHome = store.model
        controller.rebuild(home: store.model, activeFloorId: store.activeFloorId)
        if let onControllerReady {
            DispatchQueue.main.async { onControllerReady(controller) }
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let controller = context.coordinator.controller else { return }
        context.coordinator.tool = tool
        context.coordinator.interactionEnabled = interactionEnabled
        context.coordinator.onOpeningPlaced = onOpeningPlaced
        controller.currentHome = store.model
        // Rebuild only when the geometry inputs actually changed. `DollhouseSceneBuilder.build`
        // is a pure function of the model, so an unchanged model rebuilds to an identical scene
        // — pure cost. That was harmless while updates only followed an edit commit, but
        // HouseScreen's body reads the evacuation playback clock, so this path now runs on every
        // frame of a simulation; rebuilding there would restart the animation 60×/sec.
        // The camera survives either way: the rig node is re-attached, not rebuilt.
        controller.rebuildIfNeeded(home: store.model, activeFloorId: store.activeFloorId)
        controller.highlight(store.selection)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let store: HomeModelStore
        var controller: UnifiedSceneController?
        var bridge: SceneKitEditorBridge?
        var tool: EditorTool = .select
        var interactionEnabled = true
        var onOpeningPlaced: (() -> Void)?
        /// Rolling gesture-event log surfaced via accessibilityValue for UI-automation
        /// debugging (see decisions.md 2026-07-23: log streams can't reach the cloned test
        /// simulator, but the test process can read this back). Only active under the
        /// automation camera flag — VoiceOver must never announce it.
        private let debugLogEnabled = UserDefaults.standard.bool(forKey: "editor.topDownCamera")
        private var debugEvents: [String] = []
        private func logDebug(_ event: String, on view: UIView) {
            guard debugLogEnabled else { return }
            debugEvents.append(event)
            view.accessibilityValue = debugEvents.suffix(5).joined(separator: " ;; ")
        }

        /// Edit-or-camera, decided at `.began` and held until the gesture ends. Orbit-vs-truck
        /// is NOT decided here any more — `CameraGestureDriver`'s arbiter owns that, from live
        /// touch count, so the two surfaces cannot drift apart again.
        private enum PanMode { case edit, camera }
        private var panMode: PanMode = .camera

        /// The shared camera-gesture implementation. Created once the controller exists.
        private(set) var cameraGestures: CameraGestureDriver?

        init(store: HomeModelStore) {
            self.store = store
        }

        func installCameraGestures(on controller: UnifiedSceneController) {
            let driver = CameraGestureDriver(rig: controller.rig)
            driver.onPhaseChange = { [weak controller] inFlight in
                controller?.isCameraGestureInFlight = inFlight
            }
            cameraGestures = driver
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard interactionEnabled, let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            logDebug("tap@\(Int(location.x)),\(Int(location.y)) \(bridge?.debugProbe(at: location) ?? "")", on: view)
            if case .placeOpening(let kind) = tool {
                if bridge?.handlePlacementTap(at: location, kind: kind) == true {
                    onOpeningPlaced?()
                }
            } else {
                bridge?.handleTap(at: location)
                // A tap that landed on a floor other than the active one focuses that floor —
                // the direct-manipulation twin of the floor chips. The bridge's own selection
                // handling already ran, so this only ever ADDS focus, never steals a selection.
                if let controller,
                   let hit = controller.floorID(atScreenPoint: location),
                   hit != controller.activeFloorId {
                    controller.onFloorTapped?(hit)
                }
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard interactionEnabled, let view = recognizer.view as? SCNView, let controller else { return }
            let location = recognizer.location(in: view)

            if recognizer.state == .began {
                // The pan only recognizes after ~10 pt of travel, so `location` has already
                // drifted off whatever the finger went down on — enough, at typical zooms, to
                // cross to a neighboring vertex and misroute the whole gesture. Arbitrate and
                // begin the edit at the TRUE touch-down point.
                let start = (recognizer as? InitialPointPanGestureRecognizer)?.initialTouchPoint
                    ?? location
                if case .placeOpening = tool {
                    // A pan while a placement tool is armed never edits — placement is tap-only.
                    panMode = .camera
                } else if recognizer.numberOfTouches >= 2 {
                    // Two fingers is unambiguously a camera manipulation; never an edit drag.
                    panMode = .camera
                } else {
                    panMode = bridge?.dragIntent(at: start) == .edit ? .edit : .camera
                }
                logDebug("pan=\(panMode)@\(Int(start.x)),\(Int(start.y)) \(bridge?.debugProbe(at: start) ?? "")", on: view)
                if panMode == .edit {
                    // An edit-drag must never run against a still-moving camera. `beginOrbit`
                    // kills leftover inertia without claiming the gesture.
                    controller.rig.beginOrbit()
                    bridge?.handleDrag(.began, at: start)
                    // Feed the recognition drift as the first movement so the geometry
                    // catches up to where the finger actually is.
                    bridge?.handleDrag(.changed, at: location)
                    return
                }
            }

            switch panMode {
            case .edit:
                bridge?.handleDrag(recognizer.state, at: location)
                if recognizer.state == .ended {
                    logDebug("end " + (bridge?.debugPolygons() ?? ""), on: view)
                }
            case .camera:
                cameraGestures?.handlePan(recognizer, in: view)
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard interactionEnabled, let view = recognizer.view as? SCNView else { return }
            cameraGestures?.handlePinch(recognizer, in: view)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard interactionEnabled, let view = recognizer.view as? SCNView, let controller,
                  let home = controller.currentHome else { return }
            cameraGestures?.handleDoubleTap(at: recognizer.location(in: view), in: view, home: home)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Pinch + pan run together so two-finger zoom and truck combine naturally (a real
            // pinch drifts, a real two-finger pan scales a little). Editing is unaffected:
            // edit-drags are single-finger, and the mode latch never reassigns mid-gesture.
            let pair = [gestureRecognizer, other]
            let hasPinch = pair.contains { $0 is UIPinchGestureRecognizer }
            let hasPan = pair.contains { $0 is UIPanGestureRecognizer }
            return hasPinch && hasPan
        }
    }
}

#else

/// Non-UIKit fallback (e.g. a future macOS/previews-only target) so the file still compiles;
/// the editor is iOS-only per CLAUDE.md's scope lock.
struct EditorSceneView: View {
    let store: HomeModelStore
    let model: HomeModel
    let activeFloorId: String
    let selection: Selection
    var tool: EditorTool = .select
    let undoStack: UndoStack
    var onOpeningPlaced: (() -> Void)?
    var body: some View {
        Text("3D editor requires iOS/SceneKit.")
    }
}

#endif
