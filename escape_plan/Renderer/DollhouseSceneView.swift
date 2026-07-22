import SceneKit
import SwiftUI

/// SwiftUI wrapper around the SCNView that draws a built `DollhouseScene`.
///
/// `allowsCameraControl` is what provides orbit / pan / zoom: one finger orbits, two fingers pan,
/// pinch zooms. It is deliberately not reimplemented by hand — SceneKit's default camera
/// controller is the interaction P2 would otherwise be rebuilding.
struct DollhouseSceneView: UIViewRepresentable {
    let dollhouse: DollhouseScene
    var explode: Double
    var hiddenFloorIDs: Set<String>
    /// The route overlay's pulse shader animates on `u_time`, which only advances while the
    /// view redraws — flip this on while routes are shown (S2.3), off for the static scene.
    var wantsContinuousRendering: Bool = false
    /// While the S2.3 camera tour owns `pointOfView`, SwiftUI updates must not reset it.
    var isTouring: Bool = false
    /// Hands the backing SCNView to the owner (PlanScreen needs it for tour mode). Called
    /// async so setting @State from it doesn't mutate state mid-view-update.
    var onViewReady: ((SCNView) -> Void)? = nil

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = dollhouse.scene
        view.pointOfView = dollhouse.cameraNode
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = DollhousePalette.background
        // The scene is static between edits; only redraw when something actually changes.
        view.rendersContinuously = wantsContinuousRendering
        apply(to: view)
        if let onViewReady {
            DispatchQueue.main.async { onViewReady(view) }
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== dollhouse.scene {
            view.scene = dollhouse.scene
            if !isTouring {
                view.pointOfView = dollhouse.cameraNode
            }
            if let onViewReady {
                DispatchQueue.main.async { onViewReady(view) }
            }
        }
        view.rendersContinuously = wantsContinuousRendering
        apply(to: view)
    }

    private func apply(to view: SCNView) {
        dollhouse.setExplode(explode)
        for floor in dollhouse.floors {
            dollhouse.setFloor(floor.id, visible: !hiddenFloorIDs.contains(floor.id))
        }
        view.setNeedsDisplay()
    }
}
