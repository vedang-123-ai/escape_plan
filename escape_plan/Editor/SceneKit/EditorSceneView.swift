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

struct EditorSceneView: UIViewRepresentable {
    let store: HomeModelStore
    let model: HomeModel
    let activeFloorId: String
    let selection: Selection
    var tool: EditorTool = .select
    let undoStack: UndoStack
    /// Called after a `.placeOpening` tap successfully adds its opening, so the screen can
    /// disarm the tool (placement is one-shot).
    var onOpeningPlaced: (() -> Void)?

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

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        // ONE pan for both fingers-counts, branched at .began — a `maximumNumberOfTouches`
        // split into two recognizers silently swallowed XCUITest's synthesized press-drags
        // (the pan never left .possible), and a single unconstrained pan is also what the old
        // editor shipped with.
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        controller.currentHome = store.model
        controller.rebuild(home: store.model, activeFloorId: store.activeFloorId)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let controller = context.coordinator.controller else { return }
        context.coordinator.tool = tool
        context.coordinator.onOpeningPlaced = onOpeningPlaced
        controller.currentHome = store.model
        // Cheap to rebuild unconditionally (see `DollhouseSceneBuilder.build` doc comment: it's
        // a pure function of the model). The camera survives: the rig node is re-attached, not
        // rebuilt.
        controller.rebuild(home: store.model, activeFloorId: store.activeFloorId)
        controller.highlight(store.selection)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let store: HomeModelStore
        var controller: UnifiedSceneController?
        var bridge: SceneKitEditorBridge?
        var tool: EditorTool = .select
        var onOpeningPlaced: (() -> Void)?

        /// What the in-flight pan is doing, decided at .began and held until it ends — no
        /// mid-gesture reassignment even if a second finger lands.
        private enum PanMode { case edit, orbit, truck }
        private var panMode: PanMode = .orbit

        init(store: HomeModelStore) {
            self.store = store
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            if case .placeOpening(let kind) = tool {
                if bridge?.handlePlacementTap(at: location, kind: kind) == true {
                    onOpeningPlaced?()
                }
            } else {
                bridge?.handleTap(at: location)
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view as? SCNView, let controller else { return }
            let location = recognizer.location(in: view)

            if recognizer.state == .began {
                if recognizer.numberOfTouches >= 2 {
                    panMode = .truck
                } else if case .placeOpening = tool {
                    // A pan while a placement tool is armed never edits — placement is tap-only.
                    panMode = .orbit
                } else {
                    panMode = bridge?.dragIntent(at: location) == .edit ? .edit : .orbit
                }
            }

            switch panMode {
            case .edit:
                bridge?.handleDrag(recognizer.state, at: location)
            case .orbit:
                let delta = recognizer.translation(in: view)
                recognizer.setTranslation(.zero, in: view)
                controller.rig.orbit(byScreenDelta: delta, in: view)
                view.setNeedsDisplay()
            case .truck:
                let delta = recognizer.translation(in: view)
                recognizer.setTranslation(.zero, in: view)
                controller.rig.truck(byScreenDelta: delta, in: view)
                view.setNeedsDisplay()
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view = recognizer.view as? SCNView, let controller else { return }
            controller.rig.pinch(scale: recognizer.scale, centroid: recognizer.location(in: view), in: view)
            recognizer.scale = 1
            view.setNeedsDisplay()
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
