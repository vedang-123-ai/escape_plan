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

        /// Thinner than the old 0.10/0.055: against an opaque white model the tube no longer has
        /// to shout through stacked translucency to be seen, and a finer line reads as a drawn
        /// path rather than a pipe.
        var radius: Float { self == .primary ? 0.065 : 0.04 }
        var color: UIColor { self == .primary ? DollhousePalette.routePrimary : DollhousePalette.routeSecondary }
        /// Secondary rides slightly higher so shared corridor stretches don't z-fight.
        var extraLift: Float { self == .primary ? 0 : 0.08 }
        /// Primary sits above secondary where they share a corridor.
        var renderingOrder: Int { self == .primary ? RenderOrder.routes + 1 : RenderOrder.routes }
    }

    /// Shades the tube as a cylinder. `_surface.normal` is in view space, so its z component is
    /// how directly a fragment faces the camera: the centerline stays bright and the silhouette
    /// edges fall off, which is what makes a constant-lit tube read as round from any orbit angle.
    private static let roundShader = """
    float facing = clamp(abs(_surface.normal.z), 0.0, 1.0);
    _output.color.rgb *= mix(0.55, 1.35, facing);
    """

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
    private weak var tourRestoreNode: SCNNode?
    private var tourCompletion: (() -> Void)?
    /// Room-name labels hidden while the tour owns the camera — at eye level a billboarded
    /// label fills the whole frame.
    private var tourHiddenLabels: [SCNNode] = []

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
                // "You start here": only when a single room is shown — one dot per house
                // would be noise, one dot per selected route is orientation.
                if rooms.count == 1 {
                    addStartMarker(for: primary, knownFloorIDs: knownFloorIDs)
                }
            }
            if includeSecondary, let secondary = room.secondary {
                draw(secondary, style: .secondary, label: room.room_id,
                     knownFloorIDs: knownFloorIDs, issues: &issues)
            }
            for finding in room.findings {
                addBadge(for: finding, home: home, issues: &issues)
            }
        }
        // Exits are no longer glowing shells wrapped around the door fixture — they are green
        // pads on the ground built by the scene builder (ExitMarkerFixture), so they are present
        // whether or not a route is on screen. Nothing to add here.
        refreshFloorFocus()
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
                addTube(geometry, style: style, name: "route:\(label):\(run.floorID)",
                        into: container)
            }
            // Where the route crosses floors, a stub on each side marks "continues via these
            // stairs". Stubs live floor-local, so floor focus and visibility apply for free.
            if run.endsAtStair, let end = run.points.last {
                container.addChildNode(stairStub(at: end, style: style))
            }
            if run.startsAtStair, let start = run.points.first {
                container.addChildNode(stairStub(at: start, style: style))
            }
        }
    }

    /// Adds a route tube as TWO passes, which is what gives the route depth without making the
    /// whole model look like an x-ray.
    ///
    /// - Pass B draws first and ignores the depth buffer, so it paints the entire path at 55%
    ///   even where walls and floors are in front of it.
    /// - Pass A draws after and DOES depth-test, so it repaints the unoccluded stretches at full
    ///   strength.
    ///
    /// The net read is a hot solid line where the path is in the open and a ghost where it runs
    /// behind something — you can see the whole route at once and still tell what is in front of
    /// what. The previous single depth-off pass made the route float flatly over the house.
    private func addTube(_ geometry: SCNGeometry, style: TubeStyle, name: String,
                         into container: SCNNode) {
        let ghost = SCNNode(geometry: geometry)
        ghost.name = "\(name):occluded"
        ghost.geometry = geometry.copy() as? SCNGeometry
        ghost.geometry?.firstMaterial = tubeMaterial(style, occludedPass: true)
        ghost.renderingOrder = RenderOrder.routes - 1
        ghost.castsShadow = false
        container.addChildNode(ghost)

        let solid = SCNNode(geometry: geometry)
        solid.name = name
        solid.geometry?.firstMaterial = tubeMaterial(style, occludedPass: false)
        solid.renderingOrder = style.renderingOrder
        solid.castsShadow = false
        container.addChildNode(solid)
    }

    /// Dim route segments that aren't on the floor the user is looking at, so the hot wire
    /// visibly dives between layers instead of every floor's routes competing at once.
    func refreshFloorFocus() {
        guard let activeID = dollhouse?.activeFloorID else { return }
        for (floorID, container) in floorContainers {
            container.opacity = floorID == activeID ? 1.0 : 0.45
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

    private func tubeMaterial(_ style: TubeStyle, occludedPass: Bool) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = style.color
        material.emission.contents = style.color
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = !occludedPass
        material.transparency = occludedPass ? 0.55 : 1.0
        material.blendMode = .alpha

        // Constant lighting means the tube gets no shading from the scene's lights (correct — a
        // route must not go dim on the shadowed side of the house), so roundness is shaded into
        // the fragment instead: faces angled away from the viewer darken. Without this the tube
        // is a flat orange ribbon.
        var modifier = Self.roundShader
        if !occludedPass, style == .primary { modifier += Self.pulseShader }
        if style == .secondary { modifier += Self.dashShader }
        material.shaderModifiers = [.fragment: modifier]
        return material
    }

    private func stairStub(at point: SCNVector3, style: TubeStyle) -> SCNNode {
        let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(style.radius) * 1.8, height: 0.4)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = style.color
        material.emission.contents = style.color
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        cone.firstMaterial = material
        let node = SCNNode(geometry: cone)
        node.position = SCNVector3(point.x, point.y + 0.2, point.z)
        node.renderingOrder = style.renderingOrder
        node.castsShadow = false
        return node
    }

    /// Pulsing "you start here" dot at the route's first waypoint, floor-local like the tubes
    /// so explode / floor toggles carry it along.
    private func addStartMarker(for route: Route, knownFloorIDs: Set<String>) {
        guard let first = route.waypoints.first,
              knownFloorIDs.contains(first.floor_id),
              let container = container(forFloor: first.floor_id) else { return }
        let sphere = SCNSphere(radius: 0.16)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = DollhousePalette.routePrimary
        material.emission.contents = DollhousePalette.routePrimary
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        sphere.firstMaterial = material
        let node = SCNNode(geometry: sphere)
        node.name = "routeStart"
        node.position = DollhouseGeometry.scenePoint(Point(x: first.x, y: first.y),
                                                     y: RouteGeometry.routeLiftM)
        node.renderingOrder = 56
        node.castsShadow = false
        node.runAction(.repeatForever(.sequence([
            .scale(to: 1.5, duration: 0.6),
            .scale(to: 1.0, duration: 0.6),
        ])))
        container.addChildNode(node)
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
        discNode.renderingOrder = RenderOrder.badges

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
        glyphNode.renderingOrder = RenderOrder.badgeGlyphs
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
    /// When finished or cancelled, `pointOfView` returns to `restoreTo` (the unified view's
    /// orbit-rig camera; falls back to the builder's static camera when nil).
    func startTour(along route: Route, in view: SCNView,
                   restoreTo restoreNode: SCNNode? = nil,
                   completion: @escaping () -> Void) {
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
        // Wider lens for interiors: at 50° a hallway is all wall; at 65° the room reads.
        camera.fieldOfView = 65
        let node = SCNNode()
        node.name = "tourCamera"
        node.camera = camera
        node.position = path[0]
        dollhouse.scene.rootNode.addChildNode(node)

        tourNode = node
        tourView = view
        tourRestoreNode = restoreNode
        tourCompletion = completion
        view.pointOfView = node

        tourHiddenLabels = []
        dollhouse.scene.rootNode.enumerateChildNodes { child, _ in
            if child.name?.hasPrefix("label:") == true, !child.isHidden {
                child.isHidden = true
                tourHiddenLabels.append(child)
            }
        }

        let speed: Float = 1.5 // m/s — brisk walk, slow enough to read the house
        let duration = TimeInterval(total / speed)
        let fly = SCNAction.customAction(duration: duration) { node, elapsed in
            let s = Float(elapsed) / Float(duration) * total
            node.position = RouteGeometry.point(at: s, along: path, arcs: arcs)
            // Gaze slightly downward at the path ahead so the glowing route (not blank wall)
            // fills the frame.
            var ahead = RouteGeometry.point(at: min(s + 1.2, total), along: path, arcs: arcs)
            ahead.y -= 0.45
            if SCNVector3EqualToVector3(node.position, ahead) == false {
                node.look(at: ahead)
            }
        }
        // Walk, don't teleport: ease into the first step and settle at the exit.
        fly.timingMode = .easeInEaseOut
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
        for label in tourHiddenLabels { label.isHidden = false }
        tourHiddenLabels = []
        // Hand the camera back to whoever owned it — the orbit rig's node, not
        // `allowsCameraControl` (the unified view never enables the built-in controller).
        if let view = tourView {
            view.pointOfView = tourRestoreNode ?? dollhouse?.cameraNode
        }
        tourView = nil
        tourRestoreNode = nil
        let completion = tourCompletion
        tourCompletion = nil
        completion?()
    }
}
