//  EditorSceneView.swift
//
//  SwiftUI host for the on-device editor: a top-down SCNView driven by
//  `EditorSceneController` (the `EditorSceneAdapter`) and `SceneKitEditorBridge` (gesture ->
//  `EditAction` translation). This is the last piece of the S2.1/S1.3 integration seam described
//  in SceneKitEditorBridge.swift's TODO(integration) header.

import SwiftUI

#if canImport(SceneKit) && canImport(UIKit)
import SceneKit
import UIKit

struct EditorSceneView: UIViewRepresentable {
    let store: HomeModelStore
    /// Bumped by the screen after every accepted commit so `updateUIView` knows to rebuild —
    /// `HomeModelStore` isn't `Observable`, so SwiftUI has nothing else to diff against.
    var revision: Int
    let undoStack: UndoStack

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
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

        init(store: HomeModelStore) {
            self.store = store
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            bridge?.handleTap(at: recognizer.location(in: view))
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
    var revision: Int
    let undoStack: UndoStack
    var body: some View {
        Text("3D editor requires iOS/SceneKit.")
    }
}

#endif
