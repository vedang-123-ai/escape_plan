import SceneKit
import UIKit

/// A built dollhouse: the SceneKit scene plus the handles the UI needs to drive it (per-floor
/// visibility, active-floor focus). Building is a pure function of the HomeModel — same model in,
/// same scene out — so the editor can rebuild on every mutation without hidden state drifting.
///
/// White Model overhaul (Aug 2026): the house is ONE stacked object, always. The exploded-view
/// slider is gone. Instead exactly one floor is ACTIVE and fully solid, and every other floor
/// ghosts to a translucent white shell — you look down through the open top and focus slides
/// through the model rather than the model coming apart. See `DOLLHOUSE-REDESIGN-SPEC.md` §4.
final class DollhouseScene {

    /// What a piece of floor geometry is, which decides how it ghosts.
    enum GhostPart {
        /// Floor slabs. Ghost heavier than walls — the slab silhouette is what communicates a
        /// jagged footprint (a small basement under a wide ground floor).
        case slab
        /// Walls, fixtures, furniture — the bulk of the structure.
        case structure
        /// Glass, labels, exit markers: hidden outright while ghosted rather than dimmed, since
        /// at 12% alpha they are illegible noise that only z-fights with the stack.
        case hidden
        /// Slab edge outlines: the inverse — only visible WHILE ghosted.
        case outline
    }

    /// One geometry node on a floor plus the materials it wears when solid, so the ghost swap is
    /// reversible without rebuilding.
    struct GhostEntry {
        let node: SCNNode
        let solidMaterials: [SCNMaterial]
        let part: GhostPart
        /// The node's `renderingOrder` as built (before any ghosting ever happens). `.structure`
        /// covers walls, fixtures AND furniture objects, which sit in different bands
        /// (`RenderOrder.walls`/`.fixtures`/`.objects`) — so un-ghosting must restore each node's
        /// own value, not a single constant.
        let solidRenderingOrder: Int
    }

    /// One floor of the home, and the node holding everything on it.
    struct FloorHandle {
        let id: String
        let level: Int
        let name: String
        let node: SCNNode
        let baseY: Double
        /// Position in bottom-to-top order.
        let stackIndex: Int
        let entries: [GhostEntry]
    }

    let scene: SCNScene
    let cameraNode: SCNNode
    private(set) var floors: [FloorHandle]
    private(set) var activeFloorID: String?

    /// How long focus takes to slide from one floor to another. Fast enough to feel responsive,
    /// slow enough that the house reads as one object being re-focused rather than layers
    /// snapping on and off.
    private let focusDuration: TimeInterval = 0.35

    fileprivate init(scene: SCNScene, cameraNode: SCNNode, floors: [FloorHandle]) {
        self.scene = scene
        self.cameraNode = cameraNode
        self.floors = floors
    }

    /// Focus a floor: it goes fully solid, every other floor ghosts.
    ///
    /// Floors ABOVE the active one thin out more than floors below (0.12 vs 0.18) because you
    /// are looking down through the open top — an upper floor at the same opacity as a lower one
    /// curtains the view of the floor you actually selected.
    func setActiveFloor(_ id: String, animated: Bool = true) {
        guard floors.contains(where: { $0.id == id }) else { return }
        activeFloorID = id
        guard let active = floors.first(where: { $0.id == id }) else { return }

        for floor in floors {
            let isActive = floor.id == id
            let opacity: CGFloat = isActive ? 0
                : (floor.level < active.level
                   ? DollhousePalette.ghostOpacityBelow
                   : DollhousePalette.ghostOpacityAbove)
            apply(floor: floor, ghosted: !isActive, opacity: opacity, animated: animated)
        }
    }

    private func apply(floor: FloorHandle, ghosted: Bool, opacity: CGFloat, animated: Bool) {
        let swap = {
            for entry in floor.entries {
                switch entry.part {
                case .hidden:
                    entry.node.isHidden = ghosted
                case .outline:
                    entry.node.isHidden = !ghosted
                case .slab, .structure:
                    guard let geometry = entry.node.geometry else { continue }
                    if ghosted {
                        let alpha = entry.part == .slab
                            ? min(opacity * DollhousePalette.ghostSlabBoost,
                                  DollhousePalette.ghostSlabOpacityCap)
                            : opacity
                        geometry.materials = [FixtureStyle.ghost(opacity: alpha)]
                        entry.node.renderingOrder = entry.part == .slab
                            ? RenderOrder.ghostSlab : RenderOrder.ghostWall
                        entry.node.castsShadow = false
                    } else {
                        geometry.materials = entry.solidMaterials
                        entry.node.renderingOrder = entry.solidRenderingOrder
                        entry.node.castsShadow = true
                    }
                }
            }
        }

        guard animated else {
            swap()
            return
        }
        // The material swap happens at the midpoint of a cross-fade of the whole floor node, so
        // the change of material family is masked by the dip rather than popping.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = focusDuration / 2
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = { [focusDuration] in
            swap()
            SCNTransaction.begin()
            SCNTransaction.animationDuration = focusDuration / 2
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            floor.node.opacity = 1.0
            SCNTransaction.commit()
        }
        floor.node.opacity = 0.55
        SCNTransaction.commit()
    }

    /// Drop every floor out of its ghost treatment. Used by the camera tour, which flies at eye
    /// level through the whole stack — a translucent floor read from the inside is just fog.
    func setAllFloorsSolid() {
        for floor in floors {
            apply(floor: floor, ghosted: false, opacity: 0, animated: false)
        }
    }

    func setFloor(_ id: String, visible: Bool) {
        floors.first(where: { $0.id == id })?.node.isHidden = !visible
    }

    func isFloorVisible(_ id: String) -> Bool {
        guard let node = floors.first(where: { $0.id == id })?.node else { return false }
        return !node.isHidden
    }

    /// Mid-height of a floor in world space — where the camera should orbit around while that
    /// floor is in focus.
    func focusHeight(of id: String) -> Double? {
        guard let floor = floors.first(where: { $0.id == id }) else { return nil }
        return floor.baseY + 1.35
    }
}

// MARK: - Builder

enum DollhouseSceneBuilder {

    /// Slab heft. The stacked slabs are the "layer cake" lines of the model, and at the old
    /// 0.06 m they read as paper rather than as floors.
    static let slabThicknessM = 0.14
    /// Thickness, not color, is what distinguishes the exterior shell from an interior partition
    /// now that both are the same white.
    static let exteriorWallThicknessM = 0.14
    static let interiorWallThicknessM = 0.10

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
        scene.background.contents = backgroundGradient()

        let baseHeights = DollhouseGeometry.floorBaseHeights(of: home)
        let orderedFloors = home.floorsByLevel
        var handles: [DollhouseScene.FloorHandle] = []

        for (index, floor) in orderedFloors.enumerated() {
            let baseY = baseHeights[floor.id] ?? 0
            let floorNode = SCNNode()
            floorNode.name = "floor:\(floor.id)"
            // Children are built in floor-local space (y measured from the floor's own base).
            floorNode.position = SCNVector3(0, Float(baseY), 0)
            // Per-floor category bit so a tap can be resolved to a floor even through the ghost
            // layers — opacity-based hit tests can't tell a 12%-alpha wall from a solid one.
            let categoryMask = 1 << (min(index, 20) + 4)

            for room in floor.rooms {
                if let slab = makeSlab(room) {
                    floorNode.addChildNode(slab)
                    if let outline = makeSlabOutline(room) { floorNode.addChildNode(outline) }
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
                if opening.isExit,
                   let marker = makeExitMarker(opening, placement: placement, on: floor) {
                    floorNode.addChildNode(marker)
                }
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
            floorNode.enumerateHierarchy { node, _ in node.categoryBitMask |= categoryMask }
            handles.append(DollhouseScene.FloorHandle(
                id: floor.id, level: floor.level, name: floor.name,
                node: floorNode, baseY: baseY, stackIndex: index,
                entries: ghostEntries(in: floorNode)
            ))
        }

        // The plate sizes to the UNION of every floor's footprint and sits at the LOWEST floor's
        // base, so a basement pushes it down and the ground floor visibly overhangs — like a
        // maquette on a plinth showing its foundation pit.
        let lowestBaseY = baseHeights.values.min() ?? 0
        if let plate = BasePlateFixture.node(bounds: DollhouseGeometry.bounds(of: home),
                                             lowestBaseY: lowestBaseY,
                                             slabThickness: slabThicknessM) {
            scene.rootNode.addChildNode(plate)
        }

        addLighting(to: scene)
        let cameraNode = makeCamera(for: home, baseHeights: baseHeights)
        scene.rootNode.addChildNode(cameraNode)

        let dollhouse = DollhouseScene(scene: scene, cameraNode: cameraNode, floors: handles)
        // Open focused on the top floor — the one you see first looking down into the model.
        if let top = handles.last {
            dollhouse.setActiveFloor(top.id, animated: false)
        }
        return Result(dollhouse: dollhouse, issues: issues)
    }

    // MARK: - Ghost bookkeeping

    /// Classify every geometry node on a floor so `setActiveFloor` can swap it without knowing
    /// how it was built. Classification keys off the render band the fixture already assigned,
    /// which keeps custom `FixtureCatalog` builders working for free.
    private static func ghostEntries(in floorNode: SCNNode) -> [DollhouseScene.GhostEntry] {
        var entries: [DollhouseScene.GhostEntry] = []
        floorNode.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            let part: DollhouseScene.GhostPart
            switch node.renderingOrder {
            case RenderOrder.opaque, RenderOrder.opaque + 1:
                part = .slab
            case RenderOrder.glass, RenderOrder.labels, RenderOrder.exitMarkers:
                part = .hidden
            case RenderOrder.ghostSlab + 1:
                part = .outline
            default:
                part = .structure
            }
            entries.append(DollhouseScene.GhostEntry(
                node: node, solidMaterials: geometry.materials, part: part,
                solidRenderingOrder: node.renderingOrder))
        }
        return entries
    }

    // MARK: - Rooms

    private static func makeSlab(_ room: Room) -> SCNNode? {
        let spec = SlabFixtureSpec(polygon: room.polygon, thickness: slabThicknessM,
                                   roomType: room.type)
        guard let node = FixtureCatalog.shared.slab.node(for: spec) else { return nil }
        node.name = "room:\(room.id)"
        return node
    }

    /// A hairline loop around the room's footprint, shown ONLY while the floor is ghosted. At
    /// 12–18% alpha a slab's own silhouette gets soft; the outline is what keeps a jagged stack
    /// legible — you can see the basement's small rectangle sitting inside the ground floor's
    /// large one.
    private static func makeSlabOutline(_ room: Room) -> SCNNode? {
        guard room.polygon.count >= 3 else { return nil }
        let vertices = room.polygon.map { DollhouseGeometry.scenePoint($0, y: 0.004) }
        var indices: [Int32] = []
        for i in 0..<vertices.count {
            indices.append(Int32(i))
            indices.append(Int32((i + 1) % vertices.count))
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = DollhousePalette.ghostEdge
            .withAlphaComponent(DollhousePalette.ghostEdgeAlpha)
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        geometry.firstMaterial = material

        let node = SCNNode(geometry: geometry)
        node.name = "outline:\(room.id)"
        node.renderingOrder = RenderOrder.ghostSlab + 1
        node.castsShadow = false
        node.isHidden = true
        return node
    }

    private static func makeLabel(_ room: Room, floorHeight: Double) -> SCNNode {
        let sprite = RoomLabelSprite.make(name: room.name)
        let chipHeightM: CGFloat = 0.22
        let plane = SCNPlane(width: chipHeightM * sprite.aspect, height: chipHeightM)

        let material = SCNMaterial()
        material.diffuse.contents = sprite.image
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        // Labels now READ depth, so a chip behind a near wall is occluded instead of x-raying
        // through the model. On the mostly-top-down default camera they stay visible anyway
        // because the top of the house is open — and labels only render on the active floor.
        material.readsFromDepthBuffer = true
        plane.firstMaterial = material

        let planeNode = SCNNode(geometry: plane)
        // renderingOrder is per-node and does not inherit, so it belongs on the node that
        // actually carries the geometry, not on the billboarded holder.
        planeNode.renderingOrder = RenderOrder.labels
        planeNode.castsShadow = false

        let holder = SCNNode()
        holder.name = "label:\(room.id)"
        holder.addChildNode(planeNode)
        let c = DollhouseGeometry.centroid(room.polygon)
        holder.position = DollhouseGeometry.scenePoint(c, y: floorHeight * 0.55)
        holder.constraints = [SCNBillboardConstraint()]
        return holder
    }

    // MARK: - Walls

    private static func makeWall(_ spec: DollhouseGeometry.WallSpec, height: Double) -> SCNNode {
        let thickness = spec.isExterior ? exteriorWallThicknessM : interiorWallThicknessM
        let node = FixtureCatalog.shared.wall.node(for: WallFixtureSpec(
            length: spec.length,
            height: height,
            thickness: thickness,
            isExterior: spec.isExterior,
            cutouts: spec.cutouts
        ))
        node.position = DollhouseGeometry.scenePoint(spec.midpoint, y: height / 2)
        node.eulerAngles.y = Float(spec.yaw)
        return node
    }

    // MARK: - Openings

    private static func makeOpening(_ opening: Opening,
                                    placement: DollhouseGeometry.OpeningPlacement,
                                    floorHeight: Double) -> SCNNode {
        // A door taller than its floor is bad data, not a reason to punch through the ceiling.
        // The same clamp feeds the wall's cutout (DollhouseGeometry.walls), so the fixture
        // always exactly fills its hole.
        let height = min(placement.height, max(floorHeight - placement.sill, 0.05))
        let spec = OpeningFixtureSpec(width: placement.width, height: height,
                                      wallThickness: openingWallThickness(for: opening),
                                      kind: opening.kind, isExit: opening.isExit)
        let node = opening.kind == .door
            ? FixtureCatalog.shared.door.node(for: spec)
            : FixtureCatalog.shared.window.node(for: spec)
        node.name = "opening:\(opening.id)"
        node.position = DollhouseGeometry.scenePoint(placement.center, y: placement.sill + height / 2)
        node.eulerAngles.y = Float(placement.yaw)
        return node
    }

    /// An opening onto EXTERIOR sits in an exterior wall, which is the thicker of the two.
    private static func openingWallThickness(for opening: Opening) -> Double {
        opening.room_ids.contains(EXTERIOR_ID) ? exteriorWallThicknessM : interiorWallThicknessM
    }

    /// The green pad + chevrons on the ground outside an exit. `outward` is decided by pointing
    /// away from the host room's centroid — the exterior is whichever side of the wall the room
    /// isn't on.
    private static func makeExitMarker(_ opening: Opening,
                                       placement: DollhouseGeometry.OpeningPlacement,
                                       on floor: Floor) -> SCNNode? {
        guard let room = floor.rooms.first(where: { $0.id == opening.wall_segment.room_id })
        else { return nil }
        let roomCenter = DollhouseGeometry.centroid(room.polygon)

        // Local +z after a yaw rotation about +y maps to world (sin yaw, 0, cos yaw).
        let yaw = placement.yaw
        let outX = sin(yaw), outZ = cos(yaw)
        // Vector from the room's centroid to the opening, in scene coords (plan y → scene −z).
        let awayX = placement.center.x - roomCenter.x
        let awayZ = -(placement.center.y - roomCenter.y)
        let outward: Double = (outX * awayX + outZ * awayZ) >= 0 ? 1 : -1

        let node = ExitMarkerFixture.node(
            wallThickness: openingWallThickness(for: opening),
            sillY: placement.sill + placement.height / 2,
            outwardZ: outward,
            animated: true)
        node.name = "exitmarker:\(opening.id)"
        node.position = DollhouseGeometry.scenePoint(placement.center,
                                                     y: placement.sill + placement.height / 2)
        node.eulerAngles.y = Float(yaw)
        return node
    }

    // MARK: - Objects (v1.1)

    /// A white clay miniature built parametrically from the schema's box footprint + category.
    /// Stays ONE node named `object:<id>` — the editor's selection and drag key off that name.
    private static func makeObject(_ object: FloorObject) -> SCNNode? {
        guard object.size_m.count == 2, object.size_m[0] > 0, object.size_m[1] > 0,
              object.height_m > 0 else { return nil }

        let node = FurnitureFixture.node(category: object.category,
                                         width: object.size_m[0],
                                         depth: object.size_m[1],
                                         height: object.height_m)
        node.name = "object:\(object.id)"
        // FurnitureFixture builds nodes with local origin at the base (y = 0 is the floor
        // of the object). Setting scene y to elevation_m lifts a wall-mounted TV's base to
        // its mount height, while a floor-standing piece (elevation 0) sits correctly at
        // floor level. Early landing from S7.7 scope — see decisions.md 2026-09-09.
        node.position = DollhouseGeometry.scenePoint(object.center, y: object.elevation_m)
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
        let node = FixtureCatalog.shared.stair.node(for: StairFixtureSpec(
            runLength: alongX ? bounds.width : bounds.depth,
            width: alongX ? bounds.depth : bounds.width,
            rise: rise
        ))
        node.name = "stairs:\(stair.id)"
        node.position = DollhouseGeometry.scenePoint(bounds.center, y: 0)
        // The fixture ascends along local +x; plan +y maps to scene −z, so a run along the
        // plan's y axis is a +90° turn about scene +y.
        node.eulerAngles.y = alongX ? 0 : .pi / 2
        return node
    }

    // MARK: - Background

    /// A pale studio cyc: a vertical gradient, slightly darker at the bottom, so the white model
    /// reads bright against it and the frame has a sense of ground.
    private static func backgroundGradient() -> UIImage {
        let size = CGSize(width: 4, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [DollhousePalette.background.cgColor,
                          DollhousePalette.backgroundLower.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    // MARK: - Camera & lighting

    /// The camera the builder ships with. In the app `OrbitCameraRig` owns the live camera and
    /// this one is the fallback / tour restore target, so the two must agree on projection —
    /// see `OrbitCameraRig.configure(camera:)`.
    private static func makeCamera(for home: HomeModel, baseHeights: [String: Double]) -> SCNNode {
        let bounds = DollhouseGeometry.bounds(of: home)
        let totalHeight = home.floorsByLevel.reduce(0.0) { $0 + $1.height_m }
        let extent = max(max(bounds.width, bounds.depth), 1.0)

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = Double(extent) * 20
        CameraTuning.configure(camera)

        let node = SCNNode()
        node.camera = camera
        node.name = "camera"

        let center = bounds.isEmpty ? Point(x: 0, y: 0) : bounds.center
        let dist = Double(extent) * 1.15
        node.position = SCNVector3(
            Float(center.x + dist * 0.75),
            Float(totalHeight + Double(extent) * 0.85),
            Float(-center.y + dist * 1.0)
        )
        node.look(at: DollhouseGeometry.scenePoint(center, y: totalHeight * 0.35))
        camera.orthographicScale = CameraTuning.orthographicScale(
            forDistance: (node.position.simd - DollhouseGeometry.scenePoint(center, y: totalHeight * 0.35).simd).length)
        return node
    }

    /// Studio lighting per spec §3.4. Every bit of depth in a monochrome model comes from here:
    /// one soft warm key from the upper left, a broad cool fill so shadowed faces stay luminous,
    /// and generous ambient so nothing crushes to gray.
    private static func addLighting(to scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        ambient.light?.color = DollhousePalette.ambientTint.blended(with: .white, amount: 0.5)
        scene.rootNode.addChildNode(ambient)

        // Key at azimuth 315° / elevation 50° — upper-left, matching the reference render.
        //
        // SceneKit has no shadow-opacity knob, so the target strength (0.55) is dialled by
        // SPLITTING the key between a shadow-casting light and an identical shadowless twin.
        // Surfaces in shadow still receive the twin's 45%, which is what keeps shadows warm and
        // open instead of punching black holes in a white model.
        let keyTotal: CGFloat = 1000
        let shadowStrength: CGFloat = 0.55
        let keyDirection = direction(azimuthDegrees: 315, elevationDegrees: 50)

        let key = keyLightNode(intensity: keyTotal * shadowStrength, direction: keyDirection)
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.light?.shadowRadius = 14
        key.light?.shadowColor = DollhousePalette.shadowInk.withAlphaComponent(0.42)
        key.light?.shadowSampleCount = 16
        key.light?.automaticallyAdjustsShadowProjection = true
        scene.rootNode.addChildNode(key)

        let keySoft = keyLightNode(intensity: keyTotal * (1 - shadowStrength),
                                   direction: keyDirection)
        keySoft.light?.castsShadow = false
        scene.rootNode.addChildNode(keySoft)

        let fill = keyLightNode(intensity: 260,
                                direction: direction(azimuthDegrees: 120, elevationDegrees: 25))
        fill.light?.color = DollhousePalette.fillLight
        fill.light?.castsShadow = false
        scene.rootNode.addChildNode(fill)
    }

    private static func keyLightNode(intensity: CGFloat, direction: SCNVector3) -> SCNNode {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = .directional
        node.light?.intensity = intensity
        node.light?.color = DollhousePalette.keyLight
        // Directional lights shine down their own −z; place the node along the direction and aim
        // it at the origin so the angle is written once, in degrees, where it can be checked
        // against the spec.
        node.position = SCNVector3(direction.x * 30, direction.y * 30, direction.z * 30)
        node.look(at: SCNVector3Zero)
        return node
    }

    private static func direction(azimuthDegrees: Double, elevationDegrees: Double) -> SCNVector3 {
        let az = azimuthDegrees * .pi / 180
        let el = elevationDegrees * .pi / 180
        return SCNVector3(Float(cos(el) * sin(az)), Float(sin(el)), Float(cos(el) * cos(az)))
    }
}

/// Projection and image-quality settings shared by the builder's camera and the live orbit rig.
/// They must match or toggling between them (tour start/stop, automation) visibly jumps.
enum CameraTuning {
    /// A long-lens look. 35° instead of the old 50° cuts the perspective distortion that made
    /// the house look like a wide-angle CAD screenshot.
    static let fieldOfViewDegrees: Double = 35
    /// Orthographic by default: it IS the reference-image look, and parallel edges make rooms
    /// far easier to compare. Perspective stays available for the editor, where depth cues help
    /// judge a drag.
    static let usesOrthographic = true

    /// Matched so switching projection never jumps the framing: at `distance`, an orthographic
    /// half-height of `distance · tan(fov/2)` frames exactly what the perspective camera saw.
    static func orthographicScale(forDistance distance: Float) -> Double {
        Double(max(distance, 0.01)) * tan(fieldOfViewDegrees * .pi / 180 / 2)
    }

    static func configure(_ camera: SCNCamera) {
        camera.fieldOfView = CGFloat(fieldOfViewDegrees)
        camera.usesOrthographicProjection = usesOrthographic
        camera.wantsHDR = false
        // Ambient occlusion is where a white model gets its form: it darkens inside corners,
        // wall-floor junctions, window reveals and the space under furniture. Spec §3.4 calls it
        // 80% of the realism, and on a scene with exactly one material that is not an
        // exaggeration — without it the house is a flat white silhouette.
        camera.screenSpaceAmbientOcclusionIntensity = 1.1
        camera.screenSpaceAmbientOcclusionRadius = 0.35
        camera.screenSpaceAmbientOcclusionBias = 0.03
    }
}

private extension SCNVector3 {
    var simd: SIMD3<Float> { SIMD3(x, y, z) }
}

private extension SIMD3 where Scalar == Float {
    var length: Float { (x * x + y * y + z * z).squareRoot() }
}
