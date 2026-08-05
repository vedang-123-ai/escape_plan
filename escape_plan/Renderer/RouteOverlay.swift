import SceneKit
import UIKit

/// S2.3 route overlay: draws a fetched `RoutePlan` onto an existing `DollhouseScene` and runs
/// the camera tour. This is a controller over the built scene, not part of the builder —
/// `DollhouseSceneBuilder.build` stays a pure function of the HomeModel, and everything this
/// class adds is tracked so `clear()` restores the scene exactly.
///
/// Route data is server truth: tubes follow the engine's waypoints, badges render the engine's
/// findings verbatim. Nothing here computes, extends, or invents a route.
///
/// ## Encoding without color
///
/// The route is no longer allowed to mean anything by hue alone. A hazard system in the same
/// scene owns the warm end of the wheel (see `DollhousePalette`), so this overlay carries three
/// redundant, color-free channels on top of its cool blues:
///
/// 1. **Solid versus dashed.** The primary is one continuous tube; the secondary is real dashed
///    geometry (`RouteGeometry.dashes`). Desaturate the frame to gray and the backup route is
///    still obviously the backup.
/// 2. **Numbered stops.** Meaningful waypoints — room, doorway, stairs, exit — carry sequential
///    numbered chips. They give the route an explicit direction that does not depend on the
///    travelling pulse (which Reduce Motion removes), and their captions are the same ordered
///    list a VoiceOver user should hear.
/// 3. **A luminance step.** Primary, secondary and the reserved hazard color are separated in
///    relative luminance, so they stay three distinguishable grays on a black-and-white print.
///    `RouteEncodingTests` asserts the actual numbers.
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
        /// The non-color half of "this is the backup route".
        var isDashed: Bool { self == .secondary }
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

    private weak var dollhouse: DollhouseScene?
    /// Everything show() added, so clear() can remove exactly that and nothing else.
    private var addedNodes: [SCNNode] = []
    private var floorContainers: [String: SCNNode] = [:]

    /// Motion is decoration here, never information: the travelling pulse and the throbbing
    /// start dot only restate a direction the numbered stops already state statically. So under
    /// Reduce Motion they are dropped and the route itself is untouched — same tubes, same
    /// dashes, same numbers, nothing moving.
    let reduceMotion: Bool

    /// The numbered stops currently drawn, keyed by room id, in walking order. Read this to
    /// speak the route: `overlay.drawnSteps["bed_1"]?.map(\.caption)` is exactly the sequence
    /// of chips on screen, so the spoken list and the visible list cannot drift.
    private(set) var drawnSteps: [String: [RouteGeometry.Stop]] = [:]

    private var tourNode: SCNNode?
    private weak var tourView: SCNView?
    private weak var tourRestoreNode: SCNNode?
    private var tourCompletion: (() -> Void)?
    /// Room-name labels hidden while the tour owns the camera — at eye level a billboarded
    /// label fills the whole frame.
    private var tourHiddenLabels: [SCNNode] = []

    init(dollhouse: DollhouseScene,
         reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) {
        self.dollhouse = dollhouse
        self.reduceMotion = reduceMotion
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
                // The ordered-steps encoding is always computed — a caller can speak it even in
                // the whole-house view — but the chips are only DRAWN for a single selected
                // route. Numbering every room's route at once would bury the model in digits,
                // the same reason the start dot is single-room only.
                let stops = RouteGeometry.numberedStops(for: primary)
                drawnSteps[room.room_id] = stops
                // "You start here": only when a single room is shown — one dot per house
                // would be noise, one dot per selected route is orientation.
                if rooms.count == 1 {
                    addStartMarker(for: primary, knownFloorIDs: knownFloorIDs)
                    addStopMarkers(stops, label: room.room_id, knownFloorIDs: knownFloorIDs)
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
        drawnSteps = [:]
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
            if style.isDashed {
                // One tube per mark, each carrying its share of the run's `u` span so the
                // parameterization stays continuous across the gaps.
                for (i, dash) in RouteGeometry.dashes(smoothed).enumerated() {
                    guard let geometry = RouteGeometry.tubeGeometry(
                        points: dash.points, radius: style.radius,
                        uRange: dash.uStart...max(dash.uEnd, dash.uStart + 1e-5)) else { continue }
                    addTube(geometry, style: style,
                            name: "route:\(label):\(run.floorID):dash\(i)", into: container)
                }
            } else if let geometry = RouteGeometry.tubeGeometry(points: smoothed,
                                                                radius: style.radius) {
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
        // is a flat blue ribbon.
        //
        // The dash is NOT here any more. It used to be an alpha stipple in this shader; it is
        // now real segmented geometry (see `draw`), which is testable, has a fixed physical
        // period regardless of route length, and is reusable by the printed plan.
        var modifier = Self.roundShader
        if !occludedPass, style == .primary, !reduceMotion { modifier += Self.pulseShader }
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
        if reduceMotion {
            // Settle at the midpoint of the throb rather than at its floor, so the static dot
            // is the same visual weight the animated one averages to.
            node.scale = SCNVector3(1.25, 1.25, 1.25)
        } else {
            node.runAction(.repeatForever(.sequence([
                .scale(to: 1.5, duration: 0.6),
                .scale(to: 1.0, duration: 0.6),
            ])))
        }
        container.addChildNode(node)
    }

    // MARK: - Numbered stops

    /// Chip size in meters. Big enough to read a two-digit number from the default overview
    /// camera, small enough that consecutive stops in a hallway don't overlap.
    private static let stopChipSizeM: CGFloat = 0.30
    /// Chips float above the tube (and above the room-name chips) so a stop on a corridor
    /// doesn't sit inside the line it labels.
    private static let stopChipLiftM = RouteGeometry.routeLiftM + 0.45

    /// Sequential numbered chips at the route's meaningful waypoints. This is the encoding that
    /// survives everything: it works in grayscale, it works with Reduce Motion on, and its
    /// captions are the ordered list a screen reader reads out.
    private func addStopMarkers(_ stops: [RouteGeometry.Stop], label: String,
                                knownFloorIDs: Set<String>) {
        for stop in stops {
            guard knownFloorIDs.contains(stop.waypoint.floor_id),
                  let container = container(forFloor: stop.waypoint.floor_id) else { continue }

            let image = Self.stopChipImage(number: stop.number)
            let plane = SCNPlane(width: Self.stopChipSizeM, height: Self.stopChipSizeM)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            // Like the warning badges: a stop you can't see through a wall is a stop you can't
            // count, and counting them is the whole point of numbering them.
            material.readsFromDepthBuffer = false
            plane.firstMaterial = material

            let planeNode = SCNNode(geometry: plane)
            // Above room labels, below warning badges — a badge outranks a step number.
            planeNode.renderingOrder = RenderOrder.badges - 1
            planeNode.castsShadow = false

            let holder = SCNNode()
            holder.name = "routeStop:\(label):\(stop.number)"
            holder.accessibilityLabel = stop.caption
            holder.addChildNode(planeNode)
            holder.position = DollhouseGeometry.scenePoint(
                Point(x: stop.waypoint.x, y: stop.waypoint.y), y: Self.stopChipLiftM)
            holder.constraints = [SCNBillboardConstraint()]
            container.addChildNode(holder)
        }
    }

    /// The chip: a white ring (so it separates from the white model by its edge, not by its
    /// fill), a primary-route core, and the number knocked out in white — 8.9:1 against the
    /// core, so the digit stays legible when the chip is small on screen. Stops belong to the
    /// primary route only, so the core is always `routePrimary`.
    private static func stopChipImage(number: Int) -> UIImage {
        let side: CGFloat = 44
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { _ in
                let full = CGRect(x: 0, y: 0, width: side, height: side)
                UIColor.white.withAlphaComponent(0.92).setFill()
                UIBezierPath(ovalIn: full).fill()

                DollhousePalette.routePrimary.setFill()
                UIBezierPath(ovalIn: full.insetBy(dx: 3.5, dy: 3.5)).fill()

                let font = UIFont.systemFont(ofSize: 22, weight: .bold)
                let rounded = font.fontDescriptor.withDesign(.rounded)
                    .map { UIFont(descriptor: $0, size: 22) } ?? font
                let text = "\(number)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: rounded,
                    .foregroundColor: UIColor.white,
                ]
                let size = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2),
                          withAttributes: attributes)
            }
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
