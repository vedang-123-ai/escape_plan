//  EditorSceneView.swift
//
//  SwiftUI host for the on-device editor: a top-down SCNView driven by
//  `EditorSceneController` (the `EditorSceneAdapter`) and `SceneKitEditorBridge` (gesture ->
//  `EditAction` translation).
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
        let controller = EditorSceneController(scnView: view)
        context.coordinator.controller = controller
        context.coordinator.bridge = SceneKitEditorBridge(store: store, scene: controller, undoStack: undoStack)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)

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
        // a pure function of the model) — the alternative is threading a fine-grained "what
        // changed" signal through every EditAction, which the editor core deliberately doesn't
        // expose (rules/languages/swift.md: the store is the only source of truth).
        controller.rebuild(home: store.model, activeFloorId: store.activeFloorId)
        controller.highlight(store.selection)
    }

    @MainActor
    final class Coordinator: NSObject {
        let store: HomeModelStore
        var controller: EditorSceneController?
        var bridge: SceneKitEditorBridge?
        var tool: EditorTool = .select
        var onOpeningPlaced: (() -> Void)?

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
            guard let view = recognizer.view else { return }
            bridge?.handleDrag(recognizer.state, at: recognizer.location(in: view))
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
