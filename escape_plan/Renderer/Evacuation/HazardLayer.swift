//  HazardLayer.swift
//  Renderer/Evacuation
//
//  A deliberately diagrammatic rendering of the engine's `HazardEvent`s. This layer never
//  estimates spread, changes an event time, or mutates the dollhouse's materials. It adds a
//  warm translucent room wash, a wall-edge wash, and a small capped particle emitter for each
//  event the engine supplied. `clear()` removes exactly those containers.
//
//  The wash begins shortly before `untenable_at_s` and reaches full strength exactly at that
//  boundary. This makes the ordered front readable without pretending to simulate flame,
//  smoke density, ventilation, or survivability. In stepped/Reduce Motion mode the same room
//  state remains visible, but it changes discretely and particle motion is suppressed.

import SceneKit
import UIKit

nonisolated final class HazardLayer {

    struct Tuning {
        /// Visual lead-in only. It does not change when the engine says a room is untenable.
        var frontRampDuration_s: Double = 3.0
        /// Hard performance ceiling across the entire home, independent of room count.
        var maximumTotalParticleBirthRate: CGFloat = 120
        var maximumPerRoomParticleBirthRate: CGFloat = 20

        static let `default` = Tuning()
    }

    private struct RoomVisual {
        let roomID: String
        let untenableAt_s: Double
        let floorMaterial: SCNMaterial
        let wallMaterial: SCNMaterial
        let edgeMaterial: SCNMaterial
        let smoke: SCNParticleSystem
        let maximumBirthRate: CGFloat
    }

    private weak var dollhouse: DollhouseScene?
    private let tuning: Tuning

    /// One container per rendered room. Containers may live under different floor nodes, so
    /// ownership is tracked explicitly rather than inferred by walking the scene.
    private var addedNodes: [SCNNode] = []
    private var roomVisuals: [RoomVisual] = []
    private var lastReduceMotion: Bool?

    init(dollhouse: DollhouseScene, tuning: Tuning = .default) {
        self.dollhouse = dollhouse
        self.tuning = tuning
    }

    /// Installs the timeline's hazard events into the existing dollhouse. No room absent from
    /// `timeline.hazard` receives a visual: absence means the engine modeled it as clear.
    ///
    /// Returns data-resolution issues in the same spirit as `RouteOverlay.show`; an invalid
    /// room reference is surfaced rather than painted at the origin or silently relocated.
    @MainActor
    @discardableResult
    func show(timeline: EvacuationTimeline, home: HomeModel) -> [String] {
        clear()
        guard let dollhouse else { return [] }
        guard timeline.home_id == home.home_id else {
            return ["hazard timeline belongs to home '\(timeline.home_id)', not '\(home.home_id)'"]
        }

        var issues: [String] = []
        var earliestByRoom: [String: HazardEvent] = [:]
        for event in timeline.hazard {
            guard event.untenable_at_s.isFinite else {
                issues.append("hazard event for room '\(event.room_id)' has a non-finite time")
                continue
            }
            if let existing = earliestByRoom[event.room_id] {
                issues.append("hazard timeline repeats room '\(event.room_id)'; the earliest event is shown")
                if event.untenable_at_s < existing.untenable_at_s {
                    earliestByRoom[event.room_id] = event
                }
            } else {
                earliestByRoom[event.room_id] = event
            }
        }

        let events = earliestByRoom.values.sorted {
            if $0.untenable_at_s != $1.untenable_at_s {
                return $0.untenable_at_s < $1.untenable_at_s
            }
            return $0.room_id < $1.room_id
        }

        struct ResolvedEvent {
            let event: HazardEvent
            let floor: Floor
            let room: Room
            let floorNode: SCNNode
        }
        var resolved: [ResolvedEvent] = []
        for event in events {
            guard let floor = home.floors.first(where: { $0.id == event.floor_id }) else {
                issues.append("hazard event for '\(event.room_id)' references unknown floor '\(event.floor_id)'")
                continue
            }
            guard let room = floor.rooms.first(where: { $0.id == event.room_id }) else {
                issues.append("hazard event room '\(event.room_id)' is not on floor '\(event.floor_id)'")
                continue
            }
            guard room.polygon.count >= 3 else {
                issues.append("hazard room '\(event.room_id)' has no renderable footprint")
                continue
            }
            guard let handle = dollhouse.floors.first(where: { $0.id == floor.id }) else {
                issues.append("hazard floor '\(floor.id)' is not present in the built scene")
                continue
            }
            resolved.append(ResolvedEvent(event: event, floor: floor, room: room,
                                          floorNode: handle.node))
        }

        let roomBirthRate = min(
            max(tuning.maximumPerRoomParticleBirthRate, 0),
            max(tuning.maximumTotalParticleBirthRate, 0) / CGFloat(max(resolved.count, 1))
        )

        for item in resolved {
            guard let visual = makeVisual(event: item.event, room: item.room,
                                          floor: item.floor, maximumBirthRate: roomBirthRate)
            else {
                issues.append("hazard room '\(item.room.id)' could not build its floor wash")
                continue
            }
            item.floorNode.addChildNode(visual.container)
            addedNodes.append(visual.container)
            roomVisuals.append(visual.visual)
        }

        // t=0 is meaningful: the origin room's event is inclusive and must be visible before
        // the first playback tick arrives.
        update(time: 0, reduceMotion: false)
        return issues
    }

    /// Naming alias for coordinators that configure all evacuation layers together.
    @MainActor
    @discardableResult
    func configure(timeline: EvacuationTimeline, home: HomeModel) -> [String] {
        show(timeline: timeline, home: home)
    }

    /// Applies one playback instant. The caller owns the clock and passes its current value;
    /// this layer never starts a timer, installs a renderer delegate, or advances time itself.
    func update(time: Double, reduceMotion: Bool) {
        let now = time.isFinite ? max(0, time) : 0
        let enteredReduceMotion = reduceMotion && lastReduceMotion != true
        lastReduceMotion = reduceMotion
        for visual in roomVisuals {
            let progress = frontProgress(
                at: now,
                untenableAt: visual.untenableAt_s,
                reduceMotion: reduceMotion
            )
            visual.floorMaterial.transparency = progress * EvacuationPalette.maximumFloorWashOpacity
            visual.floorMaterial.emission.intensity = 0.25 + progress * 0.9
            visual.wallMaterial.transparency = progress * EvacuationPalette.maximumWallWashOpacity
            visual.wallMaterial.emission.intensity = 0.15 + progress * 0.65
            visual.edgeMaterial.transparency = progress * EvacuationPalette.maximumEdgeOpacity
            visual.edgeMaterial.emission.intensity = 0.3 + progress * 0.8

            // Particle motion is decoration, not state. Reduce Motion drops it while retaining
            // the complete floor/wall encoding of which rooms are affected.
            visual.smoke.birthRate = reduceMotion
                ? 0
                : visual.maximumBirthRate * progress * progress
            if enteredReduceMotion {
                // `birthRate = 0` only stops new particles. Reset once on the transition so
                // already-born particles do not continue drifting for their remaining lifetime.
                visual.smoke.reset()
            }
        }
    }

    func clear() {
        for node in addedNodes { node.removeFromParentNode() }
        addedNodes.removeAll(keepingCapacity: true)
        roomVisuals.removeAll(keepingCapacity: true)
        lastReduceMotion = nil
    }

    // MARK: - Construction

    @MainActor
    private func makeVisual(event: HazardEvent, room: Room, floor: Floor,
                            maximumBirthRate: CGFloat)
        -> (container: SCNNode, visual: RoomVisual)? {
        guard let cgPath = DollhouseGeometry.path(for: room.polygon) else { return nil }

        let container = SCNNode()
        container.name = "hazard:\(room.id)"

        let floorMaterial = surfaceMaterial(
            diffuse: EvacuationPalette.hazardCore,
            emission: EvacuationPalette.hazardHalo
        )
        let wallMaterial = surfaceMaterial(
            diffuse: EvacuationPalette.hazardHalo,
            emission: EvacuationPalette.hazardCore
        )
        let edgeMaterial = surfaceMaterial(
            diffuse: EvacuationPalette.hazardEdge,
            emission: EvacuationPalette.hazardEdge
        )

        // SCNShape is tessellated by SceneKit, so concave and jagged schema polygons remain
        // honest instead of being replaced by a bounding rectangle. Rotating -90° around x
        // maps shape (x,y) to scene (x,-z), exactly DollhouseGeometry's convention.
        let shape = SCNShape(path: UIBezierPath(cgPath: cgPath), extrusionDepth: 0.006)
        shape.chamferRadius = 0
        shape.materials = [floorMaterial]
        let floorWash = SCNNode(geometry: shape)
        floorWash.name = "hazardFloor:\(room.id)"
        floorWash.eulerAngles.x = -.pi / 2
        floorWash.position.y = 0.012
        floorWash.renderingOrder = RenderOrder.routes - 4
        floorWash.castsShadow = false
        container.addChildNode(floorWash)

        // A thin translucent sheath sits outside the architectural wall. This avoids changing
        // the wall's material (which the dollhouse owns) and avoids coplanar z-fighting.
        for index in room.polygon.indices {
            guard let edge = DollhouseGeometry.edge(room.polygon, index) else { continue }
            let length = DollhouseGeometry.length(from: edge.a, to: edge.b)
            guard length > 1e-6 else { continue }
            let height = max(0.12, floor.height_m * 0.82)
            let sheath = SCNBox(width: CGFloat(length), height: CGFloat(height),
                               length: 0.154, chamferRadius: 0.006)
            sheath.materials = [wallMaterial]
            let wall = SCNNode(geometry: sheath)
            wall.name = "hazardWall:\(room.id):\(index)"
            wall.position = DollhouseGeometry.scenePoint(
                Point(x: (edge.a.x + edge.b.x) / 2, y: (edge.a.y + edge.b.y) / 2),
                y: 0.04 + height / 2
            )
            wall.eulerAngles.y = Float(DollhouseGeometry.sceneYaw(from: edge.a, to: edge.b))
            wall.renderingOrder = RenderOrder.routes - 3
            wall.castsShadow = false
            container.addChildNode(wall)
        }

        if let outline = outlineNode(for: room, material: edgeMaterial) {
            container.addChildNode(outline)
        }

        let smoke = smokeSystem(for: room)
        smoke.birthRate = 0
        let emitter = SCNNode()
        emitter.name = "hazardSmoke:\(room.id)"
        let centroid = DollhouseGeometry.centroid(room.polygon)
        emitter.position = DollhouseGeometry.scenePoint(centroid, y: 0.10)
        emitter.renderingOrder = RenderOrder.routes - 2
        emitter.addParticleSystem(smoke)
        container.addChildNode(emitter)

        return (
            container,
            RoomVisual(roomID: room.id,
                       untenableAt_s: max(0, event.untenable_at_s),
                       floorMaterial: floorMaterial,
                       wallMaterial: wallMaterial,
                       edgeMaterial: edgeMaterial,
                       smoke: smoke,
                       maximumBirthRate: maximumBirthRate)
        )
    }

    @MainActor
    private func outlineNode(for room: Room, material: SCNMaterial) -> SCNNode? {
        guard room.polygon.count >= 3 else { return nil }
        let vertices = room.polygon.map { DollhouseGeometry.scenePoint($0, y: 0.026) }
        var indices: [Int32] = []
        indices.reserveCapacity(vertices.count * 2)
        for index in vertices.indices {
            indices.append(Int32(index))
            indices.append(Int32((index + 1) % vertices.count))
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = "hazardEdge:\(room.id)"
        node.renderingOrder = RenderOrder.routes - 1
        node.castsShadow = false
        return node
    }

    @MainActor
    private func surfaceMaterial(diffuse: UIColor, emission: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = diffuse
        material.emission.contents = emission
        material.isDoubleSided = true
        material.transparency = 0
        material.blendMode = .alpha
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = false
        return material
    }

    @MainActor
    private func smokeSystem(for room: Room) -> SCNParticleSystem {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for point in room.polygon {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        // The emitter is intentionally a compact centroid plume instead of a physical smoke
        // volume. It reads as an animated diagram symbol and keeps particle counts bounded.
        let width = max(0.22, min((maxX - minX) * 0.34, 1.1))
        let depth = max(0.22, min((maxY - minY) * 0.34, 1.1))
        let system = SCNParticleSystem()
        system.emitterShape = SCNBox(width: CGFloat(width), height: 0.015,
                                     length: CGFloat(depth), chamferRadius: 0)
        system.birthLocation = .volume
        system.birthDirection = .constant
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.spreadingAngle = 16
        system.particleLifeSpan = 3.0
        system.particleLifeSpanVariation = 0.45
        system.particleVelocity = 0.16
        system.particleVelocityVariation = 0.055
        system.acceleration = SCNVector3(0, 0.07, 0)
        system.dampingFactor = 0.12
        system.particleSize = 0.095
        system.particleSizeVariation = 0.045
        system.particleColor = EvacuationPalette.hazardHalo.withAlphaComponent(
            EvacuationPalette.maximumSmokeOpacity
        )
        system.particleColorVariation = SCNVector4(0.02, 0.012, 0, 0.08)
        system.particleImage = UIImage(systemName: "circle.fill")
        system.blendMode = .alpha
        system.orientationMode = .billboardScreenAligned
        system.sortingMode = .distance
        system.isLightingEnabled = false
        system.isLocal = true
        return system
    }

    // MARK: - Timeline mapping

    private func frontProgress(at time: Double, untenableAt: Double,
                               reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return time >= untenableAt ? 1 : 0 }
        let duration = max(tuning.frontRampDuration_s, 0.001)
        let start = max(0, untenableAt - duration)
        if untenableAt <= 0 { return 1 }
        guard time > start else { return 0 }
        let denominator = max(untenableAt - start, 0.001)
        let x = min(max((time - start) / denominator, 0), 1)
        // Smoothstep has zero slope at each end, so rooms do not pop on at the lead-in edge.
        return CGFloat(x * x * (3 - 2 * x))
    }
}
