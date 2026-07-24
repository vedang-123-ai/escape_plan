//  OrbitCameraRig.swift
//
//  Binds the pure `CameraRigModel` (Editor/Core) to a persistent SCNNode. The node is owned
//  here — by the view layer, not by any built scene — and re-attached after every
//  `DollhouseSceneBuilder.build`, which is what keeps the camera exactly where the user left
//  it across the editor's rebuild-on-every-edit strategy.

import SceneKit
import UIKit

@MainActor
final class OrbitCameraRig {

    let node: SCNNode
    private(set) var model: CameraRigModel

    /// Full drag across the view height orbits by ~π — brisk but controllable.
    private let orbitRadiansPerViewHeight = Double.pi

    init(home: HomeModel) {
        let bounds = DollhouseGeometry.bounds(of: home)
        let totalHeight = home.floorsByLevel.reduce(0.0) { $0 + $1.height_m }
        let extent = max(max(bounds.width, bounds.depth), 1.0)
        let center = bounds.isEmpty ? Point(x: 0, y: 0) : bounds.center

        // Plan (x, y) → scene (x, −z), same mapping as DollhouseGeometry.scenePoint.
        model = CameraRigModel.framing(
            center: CameraRigModel.Vec3(x: center.x, y: 0, z: -center.y),
            extent: extent,
            totalHeight: totalHeight
        )

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = extent * 40
        camera.fieldOfView = 50
        camera.wantsHDR = false
        node = SCNNode()
        node.camera = camera
        node.name = "orbitRigCamera"
        apply()
    }

    /// Re-parents the rig's camera into a (re)built scene and makes it the point of view.
    /// Safe to call repeatedly; the model — and therefore the view the user sees — is untouched.
    func attach(to scene: SCNScene, view: SCNView) {
        node.removeFromParentNode()
        scene.rootNode.addChildNode(node)
        view.pointOfView = node
    }

    /// Reset to the opening three-quarter framing for a (possibly different) home.
    func reframe(for home: HomeModel) {
        let bounds = DollhouseGeometry.bounds(of: home)
        let totalHeight = home.floorsByLevel.reduce(0.0) { $0 + $1.height_m }
        let extent = max(max(bounds.width, bounds.depth), 1.0)
        let center = bounds.isEmpty ? Point(x: 0, y: 0) : bounds.center
        model = CameraRigModel.framing(
            center: CameraRigModel.Vec3(x: center.x, y: 0, z: -center.y),
            extent: extent,
            totalHeight: totalHeight
        )
        node.camera?.zFar = extent * 40
        apply()
    }

    // MARK: - Gestures → model

    func orbit(byScreenDelta delta: CGPoint, in view: SCNView) {
        guard view.bounds.height > 0 else { return }
        let s = orbitRadiansPerViewHeight / Double(view.bounds.height)
        // Content follows the finger: drag right swings the camera the other way; drag up
        // tilts the camera higher over the house.
        model.orbit(deltaYaw: -Double(delta.x) * s, deltaPitch: -Double(delta.y) * s)
        apply()
    }

    func truck(byScreenDelta delta: CGPoint, in view: SCNView) {
        let mpp = model.metersPerPoint(fovDegrees: Double(node.camera?.fieldOfView ?? 50),
                                       viewHeightPoints: Double(view.bounds.height))
        model.truck(rightMeters: -Double(delta.x) * mpp, upMeters: Double(delta.y) * mpp)
        apply()
    }

    /// `scale` is the incremental pinch scale since the last call (caller resets the
    /// recognizer's scale to 1 each time). The world point under the pinch stays put.
    func pinch(scale: CGFloat, centroid: CGPoint, in view: SCNView) {
        model.zoom(scale: Double(scale), towardAnchor: anchor(at: centroid, in: view))
        apply()
    }

    // MARK: -

    /// World point the zoom should hold fixed: whatever geometry is under the touch, else the
    /// touch ray dropped onto the horizontal plane through the current pivot — so zooming over
    /// empty space still feels anchored at house height rather than snapping to the origin.
    private func anchor(at point: CGPoint, in view: SCNView) -> CameraRigModel.Vec3 {
        if let hit = view.hitTest(point, options: [.ignoreHiddenNodes: true]).first {
            let w = hit.worldCoordinates
            return CameraRigModel.Vec3(x: Double(w.x), y: Double(w.y), z: Double(w.z))
        }
        // Same near/far unproject-to-plane pattern as the editor's worldPoint(from:) — it is
        // projection-agnostic, only the target plane differs.
        let near = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
        let dy = Double(far.y - near.y)
        guard abs(dy) > 1e-9 else { return model.pivot }
        let t = (model.pivot.y - Double(near.y)) / dy
        guard t > 0 else { return model.pivot }
        return CameraRigModel.Vec3(x: Double(near.x) + t * Double(far.x - near.x),
                                   y: model.pivot.y,
                                   z: Double(near.z) + t * Double(far.z - near.z))
    }

    /// Write the model through to the node.
    private func apply() {
        let p = model.position
        node.position = SCNVector3(Float(p.x), Float(p.y), Float(p.z))
        node.look(at: SCNVector3(Float(model.pivot.x), Float(model.pivot.y), Float(model.pivot.z)))
    }
}
