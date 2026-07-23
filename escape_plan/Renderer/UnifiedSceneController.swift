//  UnifiedSceneController.swift
//
//  The unified-view successor to `EditorSceneController`: conforms the free-orbit perspective
//  scene to `EditorSceneAdapter`, so `SceneKitEditorBridge` drives editing in the same scene
//  the user orbits. Differences from the ortho controller it replaces:
//
//  - The whole house stays visible (no per-floor isolation) — this IS the unified view.
//  - The camera is the persistent `OrbitCameraRig`, re-attached across rebuilds, never reset.
//  - Screen→plan unprojection targets the active floor's *presentation* Y (base + explode
//    lift), so editing keeps working mid-explode.
//  - `metersPerPoint` is measured at the drag plane — in perspective it varies with zoom and
//    tilt, and touch tolerances must track what the user actually sees.

import Foundation

#if canImport(SceneKit) && canImport(UIKit)
import SceneKit
import UIKit

@MainActor
final class UnifiedSceneController: NSObject, EditorSceneAdapter {

    let scnView: SCNView
    let rig: OrbitCameraRig
    private(set) var dollhouse: DollhouseScene?
    private var activeFloorId: String = ""
    private let highlightNode = SCNNode()

    /// Set by the screen after every commit — needed to resolve a `Selection` into a world
    /// point for the highlight marker.
    var currentHome: HomeModel?

    /// UI-automation escape hatch (`-editor.topDownCamera YES`): the manual-build recording
    /// driver converts floor-plan meters to tap points by inverting a deterministic camera, so
    /// it gets the old fixed top-down orthographic frame instead of the free rig. Never set in
    /// normal use.
    private let topDownForAutomation = UserDefaults.standard.bool(forKey: "editor.topDownCamera")
    private let topDownNode: SCNNode = {
        let node = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 0.01
        camera.zFar = 200
        node.camera = camera
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        return node
    }()

    init(scnView: SCNView, home: HomeModel) {
        self.scnView = scnView
        self.rig = OrbitCameraRig(home: home)
        super.init()
        highlightNode.isHidden = true
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = DollhousePalette.background
        scnView.rendersContinuously = false
    }

    /// Rebuilds the scene from the current model. Called on every commit and floor switch.
    /// The rig node survives the rebuild — the camera stays exactly where the user left it.
    func rebuild(home: HomeModel, activeFloorId: String) {
        let result = DollhouseSceneBuilder.build(home)
        dollhouse = result.dollhouse
        self.activeFloorId = activeFloorId
        result.dollhouse.scene.rootNode.addChildNode(highlightNode)
        scnView.scene = result.dollhouse.scene
        rig.attach(to: result.dollhouse.scene, view: scnView)
        if topDownForAutomation {
            applyTopDownFrame(home: home, floorId: activeFloorId)
        }
        scnView.setNeedsDisplay()
    }

    /// The old `EditorSceneController.frame(on:home:)` math, verbatim — the recording driver
    /// inverts exactly this (bbox + 1.5 m padding, orthographicScale = max(width, depth) / 2).
    private func applyTopDownFrame(home: HomeModel, floorId: String) {
        guard let floor = home.floor(floorId) else { return }
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for room in floor.rooms {
            for p in room.polygon {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        if minX > maxX { minX = -3; maxX = 3; minY = -3; maxY = 3 }
        let padding = 1.5
        let width = (maxX - minX) + padding * 2
        let depth = (maxY - minY) + padding * 2
        // Only the active floor stays visible top-down — stacked floors would cover it.
        for handle in dollhouse?.floors ?? [] {
            dollhouse?.setFloor(handle.id, visible: handle.id == floorId)
        }
        topDownNode.position = SCNVector3(Float((minX + maxX) / 2),
                                          Float(floorPlaneY + 20),
                                          Float(-(minY + maxY) / 2))
        topDownNode.camera?.orthographicScale = max(width, depth) / 2
        topDownNode.removeFromParentNode()
        scnView.scene?.rootNode.addChildNode(topDownNode)
        scnView.pointOfView = topDownNode
    }

    /// World-space Y of the active floor's ground plane as currently *presented* (base height
    /// plus any explode lift) — the plane taps and drags are unprojected onto.
    private var floorPlaneY: Double {
        guard let handle = dollhouse?.floors.first(where: { $0.id == activeFloorId }) else { return 0 }
        return Double(handle.node.position.y)
    }

    // MARK: - EditorSceneAdapter

    func worldPoint(from screenPoint: CGPoint) -> Point? {
        // Same near/far unproject-to-plane as the ortho controller — the math never assumed a
        // projection, only the tolerance sizing did (handled by metersPerPoint below).
        let near = scnView.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 0))
        let far = scnView.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 1))
        let dy = Double(far.y - near.y)
        guard abs(dy) > 1e-9 else { return nil }
        let planeY = floorPlaneY
        let t = (planeY - Double(near.y)) / dy
        // In perspective the plane can be behind the camera (t < 0) — that's a miss, not a hit
        // at a mirrored point.
        guard t > 0 else { return nil }
        let worldX = Double(near.x) + t * Double(far.x - near.x)
        let worldZ = Double(near.z) + t * Double(far.z - near.z)
        return Point(x: worldX, y: -worldZ)
    }

    func metersPerPoint() -> Double {
        // Probe: two screen points 10 pt apart, both dropped onto the drag plane. Perspective
        // makes the scale depend on zoom AND tilt; measuring on the actual plane captures both.
        let c = CGPoint(x: scnView.bounds.midX, y: scnView.bounds.midY)
        guard let a = worldPoint(from: c),
              let b = worldPoint(from: CGPoint(x: c.x, y: c.y + 10)) else { return 0.01 }
        let d = Geometry.distance(a, b) / 10
        return d > 1e-6 ? d : 0.01
    }

    func highlight(_ selection: Selection) {
        highlightNode.childNodes.forEach { $0.removeFromParentNode() }

        guard let home = currentHome, let center = highlightCenter(selection, in: home) else {
            highlightNode.isHidden = true
            scnView.setNeedsDisplay()
            return
        }

        let marker = SCNNode(geometry: SCNSphere(radius: 0.12))
        marker.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
        marker.geometry?.firstMaterial?.lightingModel = .constant
        marker.geometry?.firstMaterial?.writesToDepthBuffer = false
        marker.renderingOrder = RenderOrder.glow
        marker.position = DollhouseGeometry.scenePoint(center, y: floorPlaneY + 0.05)
        highlightNode.addChildNode(marker)
        highlightNode.isHidden = false
        scnView.setNeedsDisplay()
    }

    private func highlightCenter(_ selection: Selection, in home: HomeModel) -> Point? {
        switch selection {
        case .none, .opening, .stairs:
            // Opening/stairs markers still deferred (S2.2 decisions.md).
            return nil
        case .room(let roomId):
            guard let (_, room) = home.locateRoom(roomId) else { return nil }
            return Geometry.centroid(room.polygon)
        case .vertex(let roomId, let index):
            guard let (_, room) = home.locateRoom(roomId), room.polygon.indices.contains(index) else { return nil }
            return room.polygon[index]
        case .wall(let roomId, let edgeIndex):
            guard let (_, room) = home.locateRoom(roomId),
                  let edge = Geometry.edge(room.polygon, edgeIndex) else { return nil }
            return Point(x: (edge.a.x + edge.b.x) / 2, y: (edge.a.y + edge.b.y) / 2)
        }
    }
}

#endif
