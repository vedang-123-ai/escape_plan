import SceneKit
import UIKit

/// S2.3 route overlay: draws a fetched `RoutePlan` onto an existing `DollhouseScene` and runs
/// the camera tour. This is a controller over the built scene, not part of the builder —
/// `DollhouseSceneBuilder.build` stays a pure function of the HomeModel, and everything this
/// class adds is tracked so `clear()` restores the scene exactly.
///
/// Route data is server truth: tubes follow the engine's waypoints, badges render the engine's
/// findings verbatim. Nothing here computes, extends, or invents a route.
final class RouteOverlay {

    private enum TubeStyle {
        case primary
        case secondary

        var radius: Float { self == .primary ? 0.06 : 0.045 }
        var color: UIColor { self == .primary ? DollhousePalette.routePrimary : DollhousePalette.routeSecondary }
        /// Secondary rides slightly higher so shared corridor stretches don't z-fight.
        var extraLift: Float { self == .primary ? 0 : 0.06 }
    }

    /// Fragment modifier for the primary tube: a bright band travels start → exit. `u` is
    /// arc-length-normalized, so the band moves at constant speed along the whole path — the
    /// directional cue that makes the route read as "flow this way".
    private static let pulseShader = """
    float band = fract(_surface.diffuseTexcoord.x * 6.0 - u_time * 0.8);
    float pulse = smoothstep(0.42, 0.5, band) * (1.0 - smoothstep(0.5, 0.58, band));
    _output.color.rgb += _surface.emission.rgb * pulse * 1.6;
    """

    /// Fragment modifier for the secondary tube: alpha-dashed instead of discard-based —
    /// SceneKit's GLSL→Metal transpile of `discard` is unreliable across OS versions, and
    /// alpha 0 with depth writes off renders identically.
    private static let dashShader = """
    if (fract(_surface.diffuseTexcoord.x * 24.0) > 0.55) {
        _output.color.a = 0.0;
    }
    """

    private weak var dollhouse: DollhouseScene?
    /// Everything show() added, so clear() can remove exactly that and nothing else.
    private var addedNodes: [SCNNode] = []
    private var floorContainers: [String: SCNNode] = [:]

    private var tourNode: SCNNode?
    private weak var tourView: SCNView?
    private var tourCompletion: (() -> Void)?

    init(dollhouse: DollhouseScene) {
        self.dollhouse = dollhouse
    }

    // MARK: - Drawing

    /// Redraws the overlay for the given rooms' routes. `includeSecondary: false` is the
    /// "everyone" view — primaries plus badges only, so a whole-house overlay stays legible.
    /// Returns human-readable issues for anything the plan referenced that the scene couldn't
    /// honor (unknown floor, unresolvable exit or room id) — surfaced, never swallowed.
    @discardableResult
    func show(rooms: [RoomRoutePlan], home: HomeModel, includeSecondary: Bool = true) -> [String] {
        clear()
        guard let dollhouse else { return [] }
        var issues: [String] = []
        let knownFloorIDs = Set(dollhouse.floors.map(\.id))

        for room in rooms {
            if let primary = room.primary {
                draw(primary, style: .primary, label: room.room_id,
                     knownFloorIDs: knownFloorIDs, issues: &issues)
                addExitGlow(exitID: primary.exit_id, issues: &issues)
            }
            if includeSecondary, let secondary = room.secondary {
                draw(secondary, style: .secondary, label: room.room_id,
                     knownFloorIDs: knownFloorIDs, issues: &issues)
                addExitGlow(exitID: secondary.exit_id, issues: &issues)
            }
            for finding in room.findings {
                addBadge(for: finding, home: home, issues: &issues)
            }
        }
        return issues
    }

    func clear() {
        for node in addedNodes { node.removeFromParentNode() }
        addedNodes = []
        floorContainers = [:]
    }

    private func draw(_ route: Route, style: TubeStyle, label: String,
                      knownFloorIDs: Set<String>, issues: inout [String]) {
        let (runs, dropped) = RouteGeometry.floorRuns(for: route, knownFloorIDs: knownFloorIDs)
        for floorID in dropped {
            issues.append("route for '\(label)' references floor '\(floorID)', which isn't in the model")
        }
        for run in runs {
            guard let container = container(forFloor: run.floorID) else { continue }
            let lifted = run.points.map { SCNVector3($0.x, $0.y + style.extraLift, $0.z) }
            let smoothed = RouteGeometry.catmullRom(lifted)
            if let geometry = RouteGeometry.tubeGeometry(points: smoothed, radius: style.radius) {
                geometry.firstMaterial = tubeMaterial(style)
                let node = SCNNode(geometry: geometry)
                node.name = "route:\(label):\(run.floorID)"
                container.addChildNode(node)
            }
            // Where the route crosses floors, a glowing stub on each side marks "continues via
            // these stairs". Stubs live floor-local, so under explode the pair separates
            // cleanly instead of needing bridge geometry recomputed per frame.
            if run.endsAtStair, let end = run.points.last {
                container.addChildNode(stairStub(at: end, style: style))
            }
            if run.startsAtStair, let start = run.points.first {
                container.addChildNode(stairStub(at: start, style: style))
            }
        }
    }

    /// One "routes:<floorID>" container per floor, parented under the builder's
    /// "floor:<id>" node so explode and floor visibility apply automatically.
    private func container(forFloor floorID: String) -> SCNNode? {
        if let existing = floorContainers[floorID] { return existing }
        guard let handle = dollhouse?.floors.first(where: { $0.id == floorID }) else { return nil }
        let container = SCNNode()
        container.name = "routes:\(floorID)"
        handle.node.addChildNode(container)
        floorContainers[floorID] = container
        addedNodes.append(container)
        return container
    }

    private func tubeMaterial(_ style: TubeStyle) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = style.color
        material.emission.contents = style.color
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        switch style {
        case .primary:
            material.shaderModifiers = [.fragment: Self.pulseShader]
        case .secondary:
            material.shaderModifiers = [.fragment: Self.dashShader]
        }
        return material
    }

    private func stairStub(at point: SCNVector3, style: TubeStyle) -> SCNNode {
        let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(style.radius) * 1.8, height: 0.4)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = style.color
        material.emission.contents = style.color
        cone.firstMaterial = material
        let node = SCNNode(geometry: cone)
        node.position = SCNVector3(point.x, point.y + 0.2, point.z)
        return node
    }

    // MARK: - Exit glow

    /// A pulsing translucent shell around the exit's opening marker. Added as a sibling so the
    /// builder's opening node and material are never touched.
    private func addExitGlow(exitID: String, issues: inout [String]) {
        guard let dollhouse else { return }
        // Same exit may be shared by many routes — one glow is enough.
        let glowName = "exitglow:\(exitID)"
        guard dollhouse.scene.rootNode.childNode(withName: glowName, recursively: true) == nil else { return }
        guard let opening = dollhouse.scene.rootNode.childNode(withName: "opening:\(exitID)",
                                                               recursively: true),
              let parent = opening.parent,
              let box = opening.geometry as? SCNBox else {
            issues.append("exit '\(exitID)' has no opening marker in the scene — glow skipped")
            return
        }

        let shell = SCNBox(width: box.width + 0.16, height: box.height + 0.16,
                           length: box.length + 0.16, chamferRadius: 0.04)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = DollhousePalette.exitGlow
        material.emission.contents = DollhousePalette.exitGlow
        material.transparency = 0.55
        material.writesToDepthBuffer = false
        shell.firstMaterial = material

        let node = SCNNode(geometry: shell)
        node.name = glowName
        node.position = opening.position
        node.eulerAngles = opening.eulerAngles
        node.renderingOrder = 20
        node.runAction(.repeatForever(.sequence([
            .fadeOpacity(to: 0.35, duration: 0.7),
            .fadeOpacity(to: 0.9, duration: 0.7),
        ])))
        parent.addChildNode(node)
        addedNodes.append(node)
    }

    // MARK: - Warning badges

    /// Billboarded warning marker over a flagged room, following the "label:<id>" conventions
    /// (billboard, high renderingOrder, no depth test — visible through walls). Driven purely
    /// by the engine's findings.
    private func addBadge(for finding: RouteFinding, home: HomeModel, issues: inout [String]) {
        guard let floor = home.floors.first(where: { f in f.rooms.contains { $0.id == finding.room_id } }),
              let room = floor.rooms.first(where: { $0.id == finding.room_id }),
              let container = container(forFloor: floor.id) else {
            issues.append("finding for room '\(finding.room_id)' doesn't resolve in the model — badge skipped")
            return
        }

        let severe = finding.kind == .no_viable_route
        let color = severe ? DollhousePalette.warningBadgeSevere : DollhousePalette.warningBadge

        let disc = SCNPlane(width: 0.55, height: 0.55)
        disc.cornerRadius = 0.275
        let discMaterial = SCNMaterial()
        discMaterial.lightingModel = .constant
        discMaterial.diffuse.contents = color
        discMaterial.isDoubleSided = true
        discMaterial.writesToDepthBuffer = false
        discMaterial.readsFromDepthBuffer = false
        disc.firstMaterial = discMaterial
        let discNode = SCNNode(geometry: disc)
        discNode.renderingOrder = 110

        let glyph = SCNText(string: severe ? "✕" : "!", extrusionDepth: 0)
        glyph.font = UIFont.systemFont(ofSize: 12, weight: .heavy)
        glyph.flatness = 0.1
        let glyphMaterial = SCNMaterial()
        glyphMaterial.lightingModel = .constant
        glyphMaterial.diffuse.contents = UIColor.white
        glyphMaterial.writesToDepthBuffer = false
        glyphMaterial.readsFromDepthBuffer = false
        glyph.firstMaterial = glyphMaterial
        let glyphNode = SCNNode(geometry: glyph)
        glyphNode.renderingOrder = 111
        let scale: Float = 0.028
        glyphNode.scale = SCNVector3(scale, scale, scale)
        let (minB, maxB) = glyph.boundingBox
        glyphNode.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
        glyphNode.position = SCNVector3(0, 0, 0.01)

        let holder = SCNNode()
        holder.name = "badge:\(finding.room_id)"
        holder.addChildNode(discNode)
        holder.addChildNode(glyphNode)
        // Above the room's name label (which sits at floorHeight * 0.55).
        let centroid = DollhouseGeometry.centroid(room.polygon)
        holder.position = DollhouseGeometry.scenePoint(centroid, y: floor.height_m * 0.8)
        holder.constraints = [SCNBillboardConstraint()]
        container.addChildNode(holder)
    }

    // MARK: - Tour

    /// Flies the camera along the primary route at eye height — the S2.3 "money shot".
    /// Restores free orbit on the builder's camera when finished or cancelled.
    func startTour(along route: Route, in view: SCNView, completion: @escaping () -> Void) {
        cancelTour()
        guard let dollhouse else {
            completion()
            return
        }

        // World-space path: floor-local run points plus each floor's resting base height.
        // The caller resets explode to 0 before starting, so baseY is the floor's real y.
        let baseY = Dictionary(uniqueKeysWithValues: dollhouse.floors.map { ($0.id, $0.baseY) })
        let (runs, _) = RouteGeometry.floorRuns(for: route, knownFloorIDs: Set(baseY.keys))
        let eyeHeight: Float = 1.2
        var worldPoints: [SCNVector3] = []
        for run in runs {
            let lift = Float(baseY[run.floorID] ?? 0) + eyeHeight
            worldPoints += run.points.map { SCNVector3($0.x, $0.y + lift, $0.z) }
        }
        let path = RouteGeometry.catmullRom(RouteGeometry.dedupe(worldPoints), samplesPerSegment: 12)
        let arcs = RouteGeometry.arcLengths(path)
        guard path.count >= 2, let total = arcs.last, total > 0.1 else {
            completion()
            return
        }

        let camera = (dollhouse.cameraNode.camera?.copy() as? SCNCamera) ?? SCNCamera()
        let node = SCNNode()
        node.name = "tourCamera"
        node.camera = camera
        node.position = path[0]
        dollhouse.scene.rootNode.addChildNode(node)

        tourNode = node
        tourView = view
        tourCompletion = completion
        view.pointOfView = node
        view.allowsCameraControl = false

        let speed: Float = 1.5 // m/s — brisk walk, slow enough to read the house
        let duration = TimeInterval(total / speed)
        let fly = SCNAction.customAction(duration: duration) { node, elapsed in
            let s = Float(elapsed) / Float(duration) * total
            node.position = RouteGeometry.point(at: s, along: path, arcs: arcs)
            let ahead = RouteGeometry.point(at: min(s + 1.0, total), along: path, arcs: arcs)
            if SCNVector3EqualToVector3(node.position, ahead) == false {
                node.look(at: ahead)
            }
        }
        let finish = SCNAction.run { [weak self] _ in
            DispatchQueue.main.async { self?.finishTour() }
        }
        node.runAction(.sequence([fly, finish]), forKey: "tour")
    }

    func cancelTour() {
        guard tourNode != nil else { return }
        tourNode?.removeAction(forKey: "tour")
        finishTour()
    }

    var isTourRunning: Bool { tourNode != nil }

    private func finishTour() {
        guard let node = tourNode else { return }
        node.removeFromParentNode()
        tourNode = nil
        if let view = tourView, let dollhouse {
            view.pointOfView = dollhouse.cameraNode
            view.allowsCameraControl = true
        }
        tourView = nil
        let completion = tourCompletion
        tourCompletion = nil
        completion?()
    }
}
