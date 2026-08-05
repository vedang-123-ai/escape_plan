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
    private(set) var activeFloorId: String = ""
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
        // The rig drives itself during inertia and spring-backs; give it a way to redraw and to
        // turn continuous rendering on ONLY while it is actually animating.
        rig.onChange = { [weak self] in self?.scnView.setNeedsDisplay() }
        rig.continuousRenderingSink = { [weak self] animating in
            self?.scnView.rendersContinuously = animating
        }
    }

    /// Called when the user taps a floor in the 3D view (as opposed to a floor chip).
    var onFloorTapped: ((String) -> Void)?

    /// Spring the camera back onto the home — the recenter chip's action.
    func recenterCamera() {
        guard let currentHome else { return }
        rig.recenter(on: currentHome,
                     focusY: dollhouse?.focusHeight(of: activeFloorId))
        scnView.setNeedsDisplay()
    }

    /// Glide the orbit centre to a newly focused floor's mid-height.
    func focusCamera(onFloor id: String) {
        guard let y = dollhouse?.focusHeight(of: id) else { return }
        rig.focus(onHeight: y)
        scnView.setNeedsDisplay()
    }

    var isCameraOffHome: Bool {
        guard let currentHome else { return false }
        return rig.isOffHome(currentHome)
    }

    /// Resolve a tap to the floor it landed on, so tapping a ghosted floor brings it into focus.
    ///
    /// Hit-testing by opacity does not work here: a ghost wall at 12% alpha is still geometry and
    /// SceneKit will happily report it. Instead each floor's subtree carries its own
    /// `categoryBitMask` (set by the scene builder), and the hit is attributed by mask.
    ///
    /// Disambiguation: the ACTIVE floor wins when it is hit at all — you are working on it, and a
    /// stray tap must not yank focus away — unless the ghost hit is more than 1.5 m nearer along
    /// the ray, which means the user genuinely reached past the active floor to the one in front.
    func floorID(atScreenPoint point: CGPoint) -> String? {
        guard let dollhouse else { return nil }
        let hits = scnView.hitTest(point, options: [
            .ignoreHiddenNodes: true,
            .searchMode: SCNHitTestSearchMode.all.rawValue,
        ])
        guard !hits.isEmpty else { return nil }

        var best: (id: String, depth: Float)?
        var activeHit: Float?
        for hit in hits {
            guard let floor = dollhouse.floors.first(where: { handle in
                hit.node.categoryBitMask & handle.node.categoryBitMask != 0
                    && handle.node.categoryBitMask != 0
            }) else { continue }
            let depth = distanceFromCamera(hit.worldCoordinates)
            if floor.id == activeFloorId {
                if activeHit == nil || depth < activeHit! { activeHit = depth }
            } else if best == nil || depth < best!.depth {
                best = (floor.id, depth)
            }
        }

        guard let candidate = best else { return activeHit != nil ? activeFloorId : nil }
        if let active = activeHit, candidate.depth > active - 1.5 { return activeFloorId }
        return candidate.id
    }

    private func distanceFromCamera(_ point: SCNVector3) -> Float {
        let c = rig.node.position
        let dx = point.x - c.x, dy = point.y - c.y, dz = point.z - c.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// Fired at the end of every `rebuild` with the freshly built scene. The route overlay
    /// hangs nodes off a specific `DollhouseScene`, so it must re-attach after each rebuild.
    var onRebuild: ((DollhouseScene) -> Void)?

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
        onRebuild?(result.dollhouse)
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

    /// World-space Y of the active floor's ground plane. With the exploded view gone this is
    /// simply the floor's base height — there is no longer a presentation offset to account for.
    /// (Kept as a computed property reading the node so a future transform still flows through.)
    /// Original note preserved: world-space Y of the active floor's ground plane as presented
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

    /// Where and how a selection's marker sits. Openings live on a wall at a height, not on
    /// the floor, so a single plan-space point can't place all of them.
    private enum HighlightPlacement {
        /// Ring lying flat on the floor, centred on this plan point.
        case floor(Point)
        /// Ring standing upright in the plane of a wall: plan point, height above the floor,
        /// and the wall's heading in plan space (radians).
        case wall(Point, height: Double, heading: Double)
    }

    func highlight(_ selection: Selection) {
        highlightNode.childNodes.forEach { $0.removeFromParentNode() }

        guard let home = currentHome,
              let placement = highlightPlacement(selection, in: home) else {
            highlightNode.isHidden = true
            scnView.setNeedsDisplay()
            return
        }

        // A ring rather than a yellow ball floating over the model: the ball read as a stray
        // object in the scene, and yellow is a third saturated hue in a model that is meant to
        // have exactly two. The accent green stays clear of the route orange.
        let ring = SCNTorus(ringRadius: 0.26, pipeRadius: 0.022)
        ring.firstMaterial?.diffuse.contents = DollhousePalette.selectionTint
        ring.firstMaterial?.emission.contents = DollhousePalette.selectionTint
        ring.firstMaterial?.lightingModel = .constant
        ring.firstMaterial?.writesToDepthBuffer = false
        let marker = SCNNode(geometry: ring)
        marker.renderingOrder = RenderOrder.exitMarkers
        marker.castsShadow = false

        switch placement {
        case .floor(let center):
            marker.position = DollhouseGeometry.scenePoint(center, y: floorPlaneY + 0.02)
            highlightNode.addChildNode(marker)

        case .wall(let center, let height, let heading):
            // Two nested nodes instead of eulerAngles: an SCNTorus lies in its local XZ plane,
            // so it needs a 90° tilt to stand up AND a yaw to face along the wall. Composing
            // those as euler angles depends on SceneKit's rotation order; nesting does not.
            marker.eulerAngles.x = .pi / 2
            let yaw = SCNNode()
            // Plan +y maps to scene −z, so a plan heading θ becomes a scene yaw of θ about +y.
            yaw.eulerAngles.y = Float(heading)
            yaw.position = DollhouseGeometry.scenePoint(center, y: floorPlaneY + height)
            yaw.addChildNode(marker)
            highlightNode.addChildNode(yaw)
        }

        highlightNode.isHidden = false
        scnView.setNeedsDisplay()
    }

    private func highlightPlacement(_ selection: Selection,
                                    in home: HomeModel) -> HighlightPlacement? {
        switch selection {
        case .opening(let openingId):
            // Openings are parametric: the marker is derived from the host wall segment, so it
            // follows the door when the wall is dragged instead of drifting off it.
            for floor in home.floors {
                guard let opening = floor.openings.first(where: { $0.id == openingId }),
                      let (_, room) = home.locateRoom(opening.wall_segment.room_id),
                      let edge = Geometry.edge(room.polygon, opening.wall_segment.edge_index)
                else { continue }
                let t = (opening.wall_segment.t0 + opening.wall_segment.t1) / 2
                let center = Point(x: edge.a.x + (edge.b.x - edge.a.x) * t,
                                   y: edge.a.y + (edge.b.y - edge.a.y) * t)
                return .wall(center,
                             height: opening.sill_height_m + opening.height_m / 2,
                             heading: atan2(edge.b.y - edge.a.y, edge.b.x - edge.a.x))
            }
            return nil
        case .stairs(let stairsId):
            guard let stairs = home.locateStairs(stairsId),
                  !stairs.footprint.isEmpty else { return nil }
            return .floor(Geometry.centroid(stairs.footprint))
        case .none:
            return nil
        default:
            return highlightCenter(selection, in: home).map { .floor($0) }
        }
    }

    private func highlightCenter(_ selection: Selection, in home: HomeModel) -> Point? {
        switch selection {
        case .none, .opening, .stairs:
            // Handled by highlightPlacement above — these are not floor-plane markers.
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
        case .object(let objectId):
            for floor in home.floors {
                if let object = floor.objects.first(where: { $0.id == objectId }) {
                    return object.center
                }
            }
            return nil
        }
    }
}

#endif
