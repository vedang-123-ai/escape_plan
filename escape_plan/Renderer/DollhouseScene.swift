import SceneKit
import UIKit

/// A built dollhouse: the SceneKit scene plus the handles the UI needs to drive it (per-floor
/// visibility, exploded view). Building is a pure function of the HomeModel — same model in, same
/// scene out — so the editor can rebuild on every mutation without hidden state drifting.
final class DollhouseScene {

    /// One floor of the home, and the node holding everything on it.
    struct FloorHandle {
        let id: String
        let level: Int
        let name: String
        let node: SCNNode
        /// Resting y of the node before any exploded-view offset.
        let baseY: Double
        /// Position in bottom-to-top order; drives how far the floor lifts when exploded.
        let stackIndex: Int
    }

    let scene: SCNScene
    let cameraNode: SCNNode
    private(set) var floors: [FloorHandle]

    /// Vertical gap added per floor at full explode. Roughly a floor height, so at 1.0 the
    /// stack reads as clearly separated slices rather than a taller building.
    private let explodeGapM = 2.8

    fileprivate init(scene: SCNScene, cameraNode: SCNNode, floors: [FloorHandle]) {
        self.scene = scene
        self.cameraNode = cameraNode
        self.floors = floors
    }

    /// `amount` in 0...1. 0 = floors stacked as built; 1 = fully separated.
    func setExplode(_ amount: Double) {
        let t = min(max(amount, 0), 1)
        for floor in floors {
            let lift = t * explodeGapM * Double(floor.stackIndex)
            floor.node.position.y = Float(floor.baseY + lift)
        }
    }

    func setFloor(_ id: String, visible: Bool) {
        floors.first(where: { $0.id == id })?.node.isHidden = !visible
    }

    /// Fade a floor without hiding it (floor-spotlight in the unified view). Uses node
    /// opacity — it multiplies down the subtree and never touches the hand-tuned materials
    /// the translucency effect depends on.
    func setFloorFade(_ id: String, opacity: Double) {
        floors.first(where: { $0.id == id })?.node.opacity = CGFloat(min(max(opacity, 0), 1))
    }

    func isFloorVisible(_ id: String) -> Bool {
        guard let node = floors.first(where: { $0.id == id })?.node else { return false }
        return !node.isHidden
    }
}

// MARK: - Builder

enum DollhouseSceneBuilder {

    private static let slabThicknessM = 0.06
    private static let wallThicknessM = 0.10
    /// Opening markers are slightly thicker than the wall so they read as inset panels punched
    /// through it rather than as decals that z-fight with the wall surface.
    private static let openingInsetM = 0.04

    /// Anything the model asked for but the geometry couldn't honor — a dangling `wall_segment`
    /// reference, a degenerate polygon. Surfaced rather than swallowed: bad data should be visible
    /// to whoever is looking at the render, not quietly dropped.
    struct BuildIssue {
        let entityID: String
        let message: String
    }

    struct Result {
        let dollhouse: DollhouseScene
        let issues: [BuildIssue]
    }

    static func build(_ home: HomeModel) -> Result {
        var issues: [BuildIssue] = []
        let scene = SCNScene()
        scene.background.contents = DollhousePalette.background

        let baseHeights = DollhouseGeometry.floorBaseHeights(of: home)
        let orderedFloors = home.floorsByLevel
        var handles: [DollhouseScene.FloorHandle] = []

        for (index, floor) in orderedFloors.enumerated() {
            let baseY = baseHeights[floor.id] ?? 0
            let floorNode = SCNNode()
            floorNode.name = "floor:\(floor.id)"
            // Children are built in floor-local space (y measured from the floor's own base), so
            // the exploded view only has to move this one node.
            floorNode.position = SCNVector3(0, Float(baseY), 0)

            for room in floor.rooms {
                if let slab = makeSlab(room) {
                    floorNode.addChildNode(slab)
                } else {
                    issues.append(BuildIssue(entityID: room.id,
                                             message: "room polygon has fewer than 3 vertices — no slab rendered"))
                }
                floorNode.addChildNode(makeLabel(room, floorHeight: floor.height_m))
            }

            for wall in DollhouseGeometry.walls(for: floor) {
                floorNode.addChildNode(makeWall(wall, height: floor.height_m))
            }

            for object in floor.objects {
                if let node = makeObject(object) {
                    floorNode.addChildNode(node)
                } else {
                    issues.append(BuildIssue(entityID: object.id,
                                             message: "object size_m is malformed — no prism rendered"))
                }
            }

            for opening in floor.openings {
                guard let placement = DollhouseGeometry.placement(for: opening, on: floor) else {
                    issues.append(BuildIssue(
                        entityID: opening.id,
                        message: "wall_segment references room '\(opening.wall_segment.room_id)' edge \(opening.wall_segment.edge_index), which does not resolve on floor '\(floor.id)'"
                    ))
                    continue
                }
                floorNode.addChildNode(makeOpening(opening, placement: placement, floorHeight: floor.height_m))
            }

            for stair in home.stairs where stair.from.floor_id == floor.id {
                let rise = (baseHeights[stair.to.floor_id] ?? 0) - baseY
                if let node = makeStairs(stair, rise: rise) {
                    floorNode.addChildNode(node)
                } else {
                    issues.append(BuildIssue(entityID: stair.id,
                                             message: "stair footprint is degenerate — no proxy rendered"))
                }
            }

            scene.rootNode.addChildNode(floorNode)
            handles.append(DollhouseScene.FloorHandle(
                id: floor.id, level: floor.level, name: floor.name,
                node: floorNode, baseY: baseY, stackIndex: index
            ))
        }

        addLighting(to: scene)
        let cameraNode = makeCamera(for: home, baseHeights: baseHeights)
        scene.rootNode.addChildNode(cameraNode)

        return Result(
            dollhouse: DollhouseScene(scene: scene, cameraNode: cameraNode, floors: handles),
            issues: issues
        )
    }

    // MARK: - Rooms

    private static func makeSlab(_ room: Room) -> SCNNode? {
        guard let path = DollhouseGeometry.path(for: room.polygon) else { return nil }
        let shape = SCNShape(path: UIBezierPath(cgPath: path), extrusionDepth: CGFloat(slabThicknessM))
        shape.firstMaterial = material(
            DollhousePalette.accent(for: room.type)
                .blended(with: DollhousePalette.slab, amount: 1 - DollhousePalette.roomAccentStrength)
        )

        let node = SCNNode(geometry: shape)
        node.name = "room:\(room.id)"
        // SCNShape lays its path out in local XY and extrudes along local z, centered on 0.
        // Rotating −90° about x maps plan (x, y) → scene (x, −z) and the extrusion axis to +y,
        // so the slab ends up flat with its top face at the floor's base height.
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, Float(-slabThicknessM / 2), 0)
        return node
    }

    private static func makeLabel(_ room: Room, floorHeight: Double) -> SCNNode {
        let text = SCNText(string: room.name, extrusionDepth: 0)
        text.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        text.flatness = 0.1
        let labelMaterial = material(DollhousePalette.label, lighting: .constant)
        // Labels are UI, not geometry — they stay legible through a wall.
        labelMaterial.writesToDepthBuffer = false
        labelMaterial.readsFromDepthBuffer = false
        text.firstMaterial = labelMaterial

        let textNode = SCNNode(geometry: text)
        // renderingOrder is per-node and does not inherit, so it belongs on the node that
        // actually carries the geometry, not on the billboarded holder.
        textNode.renderingOrder = RenderOrder.labels
        // SCNText is laid out in points; scale it into meters and re-center on its own bounds so
        // the label sits over the room's centroid rather than starting there.
        let scale: Float = 0.018
        textNode.scale = SCNVector3(scale, scale, scale)
        let (minB, maxB) = text.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)

        let holder = SCNNode()
        holder.name = "label:\(room.id)"
        holder.addChildNode(textNode)
        let c = DollhouseGeometry.centroid(room.polygon)
        holder.position = DollhouseGeometry.scenePoint(c, y: floorHeight * 0.55)
        holder.constraints = [SCNBillboardConstraint()]
        return holder
    }

    // MARK: - Walls

    private static func makeWall(_ spec: DollhouseGeometry.WallSpec, height: Double) -> SCNNode {
        let box = SCNBox(width: CGFloat(spec.length), height: CGFloat(height),
                         length: CGFloat(wallThicknessM), chamferRadius: 0)
        // Exterior shell keeps more body than interior partitions so the house reads as an
        // object while the floor plan inside stays legible.
        let mat = material(spec.isExterior ? DollhousePalette.exteriorWall : DollhousePalette.wall)
        mat.transparency = spec.isExterior
            ? DollhousePalette.exteriorWallOpacity : DollhousePalette.wallOpacity
        mat.isDoubleSided = true
        // Transparent surfaces that write depth hide whatever is drawn behind them afterwards —
        // which for a see-through dollhouse is exactly the content you want to see.
        mat.writesToDepthBuffer = false
        box.firstMaterial = mat

        let node = SCNNode(geometry: box)
        node.position = DollhouseGeometry.scenePoint(spec.midpoint, y: height / 2)
        node.eulerAngles.y = Float(spec.yaw)
        // Drawn after the opaque interior so alpha blends over it in the right order.
        node.renderingOrder = RenderOrder.walls
        // Translucent walls throwing hard shadows would read as solid slabs on the floor.
        node.castsShadow = false
        return node
    }

    // MARK: - Openings

    private static func makeOpening(_ opening: Opening,
                                    placement: DollhouseGeometry.OpeningPlacement,
                                    floorHeight: Double) -> SCNNode {
        // A door taller than its floor is bad data, not a reason to punch through the ceiling.
        let height = min(placement.height, max(floorHeight - placement.sill, 0.05))
        let box = SCNBox(width: CGFloat(placement.width), height: CGFloat(height),
                         length: CGFloat(wallThicknessM + openingInsetM), chamferRadius: 0.01)
        box.firstMaterial = material(DollhousePalette.opening(kind: opening.kind, isExit: opening.isExit))

        let node = SCNNode(geometry: box)
        node.name = "opening:\(opening.id)"
        node.position = DollhouseGeometry.scenePoint(placement.center, y: placement.sill + height / 2)
        node.eulerAngles.y = Float(placement.yaw)
        return node
    }

    // MARK: - Objects (v1.1)

    /// A furniture prism: opaque rotated box sitting on the floor slab. Deliberately the
    /// simplest possible geometry — the schema stores box primitives and nothing more.
    private static func makeObject(_ object: FloorObject) -> SCNNode? {
        guard object.size_m.count == 2, object.size_m[0] > 0, object.size_m[1] > 0,
              object.height_m > 0 else { return nil }
        let box = SCNBox(width: CGFloat(object.size_m[0]), height: CGFloat(object.height_m),
                         length: CGFloat(object.size_m[1]), chamferRadius: 0.02)
        box.firstMaterial = material(DollhousePalette.object(category: object.category))

        let node = SCNNode(geometry: box)
        node.name = "object:\(object.id)"
        node.position = DollhouseGeometry.scenePoint(object.center, y: object.height_m / 2)
        // Plan CCW rotation about +y: plan +y maps to scene −z, so a CCW plan rotation is a
        // positive rotation about the scene's +y axis.
        node.eulerAngles.y = Float(object.rotation_deg * .pi / 180)
        node.renderingOrder = RenderOrder.objects
        return node
    }

    // MARK: - Stairs

    /// A proxy, not a real staircase: the schema stores a footprint and a `kind` for exactly this
    /// purpose. L and U runs render as a straight flight across the footprint's long axis — enough
    /// to read "stairs here, going up" without pretending to geometry the model doesn't carry.
    private static func makeStairs(_ stair: Stairs, rise: Double) -> SCNNode? {
        var bounds = DollhouseGeometry.PlanBounds()
        for p in stair.footprint { bounds.extend(p) }
        guard !bounds.isEmpty, bounds.width > 1e-3, bounds.depth > 1e-3, rise > 1e-3 else { return nil }

        let alongX = bounds.width >= bounds.depth
        let runLength = alongX ? bounds.width : bounds.depth
        let treadWidth = alongX ? bounds.depth : bounds.width

        let stepCount = 12
        let treadDepth = runLength / Double(stepCount)
        let stepRise = rise / Double(stepCount)

        let container = SCNNode()
        container.name = "stairs:\(stair.id)"
        let mat = material(DollhousePalette.stairs)

        for i in 0..<stepCount {
            // Each tread is a slab whose top face is at the height you'd be standing on.
            let box = SCNBox(width: CGFloat(alongX ? treadDepth : treadWidth),
                             height: CGFloat(stepRise),
                             length: CGFloat(alongX ? treadWidth : treadDepth),
                             chamferRadius: 0)
            box.firstMaterial = mat
            let node = SCNNode(geometry: box)

            let alongCenter = (Double(i) + 0.5) * treadDepth
            let plan = alongX
                ? Point(x: bounds.minX + alongCenter, y: bounds.center.y)
                : Point(x: bounds.center.x, y: bounds.minY + alongCenter)
            node.position = DollhouseGeometry.scenePoint(plan, y: Double(i) * stepRise + stepRise / 2)
            container.addChildNode(node)
        }
        return container
    }

    // MARK: - Camera & lighting

    private static func makeCamera(for home: HomeModel, baseHeights: [String: Double]) -> SCNNode {
        let bounds = DollhouseGeometry.bounds(of: home)
        let totalHeight = home.floorsByLevel.reduce(0.0) { $0 + $1.height_m }
        let extent = max(max(bounds.width, bounds.depth), 1.0)

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = Double(extent) * 20
        camera.fieldOfView = 50
        camera.wantsHDR = false

        let node = SCNNode()
        node.camera = camera
        node.name = "camera"

        // Three-quarter view from above — the angle that reads as a dollhouse rather than a
        // floor plan. The user can orbit away from it; this is only the opening shot.
        let center = bounds.isEmpty ? Point(x: 0, y: 0) : bounds.center
        let dist = Double(extent) * 1.15
        node.position = SCNVector3(
            Float(center.x + dist * 0.75),
            Float(totalHeight + Double(extent) * 0.85),
            Float(-center.y + dist * 1.0)
        )
        node.look(at: DollhouseGeometry.scenePoint(center, y: totalHeight * 0.35))
        return node
    }

    private static func addLighting(to scene: SCNScene) {
        // Warm key + cool fill + warm ambient: afternoon-light diorama, not a CAD viewport.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 420
        ambient.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1.0)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.light?.color = UIColor(red: 1.0, green: 0.956, blue: 0.878, alpha: 1.0)
        // Soft contact shadows ground the model. Deferred mode keeps them off the translucent
        // walls (which don't cast — see makeWall) and cheap enough for 60fps on device.
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.light?.shadowRadius = 8
        key.light?.shadowColor = UIColor(white: 0, alpha: 0.28)
        key.light?.automaticallyAdjustsShadowProjection = true
        key.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 260
        fill.light?.color = UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1.0)
        fill.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi * 0.7, 0)
        scene.rootNode.addChildNode(fill)
    }

    // MARK: -

    private static func material(_ color: UIColor,
                                 lighting: SCNMaterial.LightingModel = .physicallyBased) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = lighting
        if lighting == .physicallyBased {
            m.roughness.contents = 0.85
            m.metalness.contents = 0.0
        }
        return m
    }
}

private extension UIColor {
    /// Mix toward `other` by `amount` (0 = self, 1 = other).
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}
