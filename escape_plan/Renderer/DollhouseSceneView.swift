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
        view.rendersContinuously = false
        apply(to: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== dollhouse.scene {
            view.scene = dollhouse.scene
            view.pointOfView = dollhouse.cameraNode
        }
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
