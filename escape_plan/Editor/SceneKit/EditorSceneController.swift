//  EditorSceneController.swift
//
//  Wires the S1.3 renderer (`DollhouseScene`) to the S2.1 editor core as the
//  `EditorSceneAdapter` that `SceneKitEditorBridge` was built against (see the
//  TODO(integration) block at the top of SceneKitEditorBridge.swift — this file
//  is that wiring).
//
//  The editor uses a fixed top-down ORTHOGRAPHIC camera over the active floor rather
//  than SceneKit's free-orbit `allowsCameraControl` (that's what the read-only Plan/
//  demo views use). An orthographic top-down camera makes screen<->floor-plane math
//  exact instead of approximate, and it matches how the editor is actually used: you
//  are drawing a 2D floor plan, not sightseeing a 3D dollhouse.

import Foundation

#if canImport(SceneKit) && canImport(UIKit)
import SceneKit
import UIKit

@MainActor
final class EditorSceneController: NSObject, EditorSceneAdapter {

    let scnView: SCNView
    private(set) var dollhouse: DollhouseScene
    /// World-space Y of the active floor's own ground plane (its slab top), i.e. the plane
    /// taps are unprojected onto. Horizontal (x, z) placement is floor-independent (every
    /// floor node sits at x=0, z=0 — only its Y differs), so this is the only per-floor state
    /// the controller needs to track.
    private var floorPlaneY: Double = 0

    private let cameraNode = SCNNode()
    private let highlightNode = SCNNode()

    /// Padding (meters) added around a floor's footprint so walls near the edge aren't
    /// clipped by the ortho frustum.
    private let framingPaddingM: Double = 1.5

    init(scnView: SCNView) {
        self.scnView = scnView
        self.dollhouse = DollhouseScene.empty()
        super.init()

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 0.01
        camera.zFar = 200
        cameraNode.camera = camera
        // Looking straight down -Y.
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)

        highlightNode.isHidden = true

        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = true
        scnView.rendersContinuously = false
    }

    /// Rebuilds the scene from the current model and frames the camera on `floorId`.
    /// Called on every commit (model may have changed shape) and every floor switch.
    func rebuild(home: HomeModel, activeFloorId: String) {
        let result = DollhouseSceneBuilder.build(home)
        dollhouse = result.dollhouse
        dollhouse.scene.rootNode.addChildNode(cameraNode)
        dollhouse.scene.rootNode.addChildNode(highlightNode)
        // The editor always shows the active floor only — stacked floors would occlude
        // the thing being edited and defeat the top-down view.
        for floor in dollhouse.floors {
            dollhouse.setFloor(floor.id, visible: floor.id == activeFloorId)
        }
        scnView.scene = dollhouse.scene
        scnView.pointOfView = cameraNode
        frame(on: activeFloorId, home: home)
        scnView.setNeedsDisplay()
    }

    private func frame(on floorId: String, home: HomeModel) {
        guard let floor = home.floor(floorId) else { return }
        floorPlaneY = dollhouse.floors.first(where: { $0.id == floorId })?.baseY ?? 0

        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for room in floor.rooms {
            for p in room.polygon {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        if minX > maxX {
            // Floor has no rooms yet (shouldn't happen — every floor needs ≥1 room — but
            // don't crash the camera framing if it briefly does mid-edit).
            minX = -3; maxX = 3; minY = -3; maxY = 3
        }

        let width = (maxX - minX) + framingPaddingM * 2
        let depth = (maxY - minY) + framingPaddingM * 2
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        // scenePoint maps schema (x, y) -> SceneKit (x, -y); see DollhouseGeometry.scenePoint.
        cameraNode.position = SCNVector3(Float(centerX), Float(floorPlaneY + 20), Float(-centerY))
        cameraNode.camera?.orthographicScale = max(width, depth) / 2
    }

    // MARK: - EditorSceneAdapter

    func worldPoint(from screenPoint: CGPoint) -> Point? {
        // unprojectPoint takes a point in the view's own coordinate space with z in
        // [0, 1] as normalized window depth; two z's on the same (x, y) give a ray.
        let near = scnView.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 0))
        let far = scnView.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 1))
        let dy = Double(far.y - near.y)
        guard abs(dy) > 1e-9 else { return nil }
        let t = (floorPlaneY - Double(near.y)) / dy
        let worldX = Double(near.x) + t * Double(far.x - near.x)
        let worldZ = Double(near.z) + t * Double(far.z - near.z)
        // Inverse of DollhouseGeometry.scenePoint: SceneKit (x, z) -> schema (x, y = -z).
        return Point(x: worldX, y: -worldZ)
    }

    func metersPerPoint() -> Double {
        guard let scale = cameraNode.camera?.orthographicScale, scnView.bounds.height > 0 else {
            return 0.01
        }
        // orthographicScale is half the world-space height of the frustum.
        return (scale * 2) / Double(scnView.bounds.height)
    }

    func highlight(_ selection: Selection) {
        highlightNode.childNodes.forEach { $0.removeFromParentNode() }

        guard let home = currentHome, let center = highlightCenter(selection, in: home) else {
            highlightNode.isHidden = true
            return
        }

        let marker = SCNNode(geometry: SCNSphere(radius: 0.12))
        marker.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
        marker.geometry?.firstMaterial?.lightingModel = .constant
        // highlightNode is a direct child of scene.rootNode (not the floor node), so its
        // children need the floor's absolute world Y explicitly — floor-local y=0 sits at
        // `floorPlaneY`, not world y=0.
        marker.position = DollhouseGeometry.scenePoint(center, y: floorPlaneY + 0.05)
        highlightNode.addChildNode(marker)
        highlightNode.isHidden = false
    }

    /// Set by the screen after every commit — the controller needs the model to resolve a
    /// `Selection` into a world point (room centroid, wall midpoint, vertex).
    var currentHome: HomeModel?

    private func highlightCenter(_ selection: Selection, in home: HomeModel) -> Point? {
        switch selection {
        case .none, .opening, .stairs:
            // Opening/stairs selection highlighting is deferred (S2.2 decisions.md) — no
            // device to verify a marker placement against.
            return nil
        case .room(let roomId):
            guard let (_, room) = home.locateRoom(roomId) else { return nil }
            return centroid(room.polygon)
        case .vertex(let roomId, let index):
            guard let (_, room) = home.locateRoom(roomId), room.polygon.indices.contains(index) else { return nil }
            return room.polygon[index]
        case .wall(let roomId, let edgeIndex):
            guard let (_, room) = home.locateRoom(roomId), !room.polygon.isEmpty else { return nil }
            let a = room.polygon[edgeIndex % room.polygon.count]
            let b = room.polygon[(edgeIndex + 1) % room.polygon.count]
            return Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
    }

    private func centroid(_ polygon: Polygon) -> Point? {
        guard !polygon.isEmpty else { return nil }
        let sum = polygon.reduce(Point(x: 0, y: 0)) { Point(x: $0.x + $1.x, y: $0.y + $1.y) }
        return Point(x: sum.x / Double(polygon.count), y: sum.y / Double(polygon.count))
    }
}

private extension DollhouseScene {
    /// An empty placeholder scene before the first `rebuild(home:activeFloorId:)` call.
    static func empty() -> DollhouseScene {
        DollhouseSceneBuilder.build(.editorPlaceholder).dollhouse
    }
}

private extension HomeModel {
    /// Trivial single-room, single-floor home used only to satisfy `DollhouseScene.empty()`
    /// before a real model is loaded — never shown, immediately replaced by `rebuild`.
    static let editorPlaceholder = HomeModel(
        schema_version: HomeModel.currentSchemaVersion,
        home_id: "placeholder",
        name: "",
        floors: [
            Floor(id: "f0", level: 0, name: "", height_m: 2.7,
                  rooms: [Room(id: "r0", name: "", type: .other,
                               polygon: [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)],
                               source: .manual, confidence: nil)],
                  openings: [])
        ],
        stairs: [],
        meta: Meta(created: .distantPast, modified: .distantPast)
    )
}

#endif
