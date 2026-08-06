//  EvacuationTrackLayer.swift
//  Renderer/Evacuation
//
//  Static, cool-coloured paths for an EvacuationTimeline. The moving figures are never the
//  only way to read the engine's answer: pausing, scrubbing, or enabling Reduce Motion leaves
//  every supplied track visible. This layer does not solve, extend, or simplify a route. It
//  joins consecutive TimedSteps exactly as received and owns every node it adds.

import SceneKit

final class EvacuationTrackLayer {

    private static let routeLift = RouteGeometry.routeLiftM + 0.045
    private static let tubeRadius: Float = 0.032
    private static let radialSegments = 6

    /// Route geometry never mutates its material, so every run can share one immutable instance
    /// instead of allocating and uploading an identical material for each floor and crossing.
    private static let material: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = EvacuationPalette.routePrimary
        material.emission.contents = EvacuationPalette.routePrimary
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        material.transparency = 0.88
        material.blendMode = .alpha
        return material
    }()

    /// RouteGeometry performs length/cross-product math in Float. Merely checking a Double for
    /// finiteness is insufficient: a huge finite Double can become infinity when converted to
    /// SCNVector3, and even a representable Float can overflow when its distance is squared.
    /// Keeping each component below sqrt(Float.max)/4 leaves room for a three-axis difference.
    private static let maximumSafeSceneMagnitude =
        Double(Float.greatestFiniteMagnitude.squareRoot()) / 4

    private weak var dollhouse: DollhouseScene?
    private var addedNodes: [SCNNode] = []

    init(dollhouse: DollhouseScene) {
        self.dollhouse = dollhouse
    }

    /// Draws the timeline's paths and returns references that could not be honored by the
    /// built scene. A timeline for another home is rejected rather than drawn approximately.
    @discardableResult
    func show(timeline: EvacuationTimeline, home: HomeModel) -> [String] {
        clear()
        guard let dollhouse else { return [] }
        guard timeline.home_id == home.home_id else {
            return ["evacuation timeline belongs to home '\(timeline.home_id)', not '\(home.home_id)'"]
        }

        var handles: [String: DollhouseScene.FloorHandle] = [:]
        for handle in dollhouse.floors where handles[handle.id] == nil {
            handles[handle.id] = handle
        }
        var issues: [String] = []

        for track in timeline.tracks {
            let nodeCountBeforeTrack = addedNodes.count
            var runFloorID: String?
            var runPoints: [SCNVector3] = []
            runPoints.reserveCapacity(track.steps.count)
            var previousValidStep: TimedStep?
            var reportedUnknownFloors = Set<String>()

            func finishRun() {
                guard let floorID = runFloorID else { return }
                defer { runPoints.removeAll(keepingCapacity: true) }
                guard let handle = handles[floorID] else {
                    issues.append("track for '\(track.profile_name)' references unknown floor '\(floorID)'")
                    return
                }
                guard let geometry = RouteGeometry.tubeGeometry(
                    points: runPoints,
                    radius: Self.tubeRadius,
                    radialSegments: Self.radialSegments
                ) else { return }

                let node = SCNNode(geometry: geometry)
                node.name = "evacuationTrack:\(track.profile_id):\(floorID)"
                node.geometry?.firstMaterial = Self.material
                node.renderingOrder = RenderOrder.routes + 3
                node.castsShadow = false
                handle.node.addChildNode(node)
                addedNodes.append(node)
            }

            /// An unusable step is a break in the supplied polyline. Finishing and resetting
            /// here is essential: continuing with the next valid step would draw a shortcut
            /// across data the renderer could not honor, inventing a route segment.
            func breakRun() {
                finishRun()
                runFloorID = nil
                previousValidStep = nil
            }

            for (index, step) in track.steps.enumerated() {
                guard step.x.isFinite, step.y.isFinite else {
                    issues.append("track for '\(track.profile_name)' has a non-finite point at step \(index)")
                    breakRun()
                    continue
                }
                guard Self.isSafeSceneCoordinate(step.x),
                      Self.isSafeSceneCoordinate(step.y) else {
                    issues.append("track for '\(track.profile_name)' has a point outside "
                                  + "SceneKit's safe numeric range at step \(index)")
                    breakRun()
                    continue
                }
                guard let floorHandle = handles[step.floor_id] else {
                    if reportedUnknownFloors.insert(step.floor_id).inserted {
                        issues.append("track for '\(track.profile_name)' references unknown "
                                      + "floor '\(step.floor_id)'")
                    }
                    breakRun()
                    continue
                }
                guard Self.isSafeSceneCoordinate(floorHandle.baseY) else {
                    if reportedUnknownFloors.insert(step.floor_id).inserted {
                        issues.append("track for '\(track.profile_name)' references floor "
                                      + "'\(step.floor_id)' with an unsafe scene height")
                    }
                    breakRun()
                    continue
                }
                let point = DollhouseGeometry.scenePoint(
                    Point(x: step.x, y: step.y),
                    y: Self.routeLift
                )

                if runFloorID == nil {
                    runFloorID = step.floor_id
                    runPoints.append(point)
                } else if runFloorID == step.floor_id {
                    runPoints.append(point)
                } else {
                    finishRun()
                    if let previousValidStep {
                        addFloorConnector(from: previousValidStep, to: step,
                                          trackID: track.profile_id,
                                          handles: handles,
                                          issues: &issues)
                    }
                    runFloorID = step.floor_id
                    runPoints.append(point)
                }
                previousValidStep = step
            }
            finishRun()
            if addedNodes.count == nodeCountBeforeTrack {
                issues.append("track for '\(track.profile_name)' has no drawable consecutive segment")
            }
        }

        return issues
    }

    func clear() {
        for node in addedNodes { node.removeFromParentNode() }
        addedNodes.removeAll(keepingCapacity: true)
    }

    /// A floor crossing is the one segment that cannot live below either floor container.
    /// Its endpoints are lifted from the two real floor bases; no rise or intermediate path is
    /// guessed. Usually x/y are identical, so this is the supplied vertical stair connector.
    private func addFloorConnector(
        from: TimedStep,
        to: TimedStep,
        trackID: String,
        handles: [String: DollhouseScene.FloorHandle],
        issues: inout [String]
    ) {
        guard let fromFloor = handles[from.floor_id], let toFloor = handles[to.floor_id] else {
            let missing = handles[from.floor_id] == nil ? from.floor_id : to.floor_id
            issues.append("track '\(trackID)' crosses unknown floor '\(missing)'")
            return
        }

        guard Self.isSafeSceneCoordinate(from.x), Self.isSafeSceneCoordinate(from.y),
              Self.isSafeSceneCoordinate(to.x), Self.isSafeSceneCoordinate(to.y),
              Self.isSafeSceneCoordinate(fromFloor.baseY + Self.routeLift),
              Self.isSafeSceneCoordinate(toFloor.baseY + Self.routeLift) else {
            issues.append("track '\(trackID)' has an unsafe floor-crossing coordinate")
            return
        }

        let a = DollhouseGeometry.scenePoint(
            Point(x: from.x, y: from.y), y: fromFloor.baseY + Self.routeLift)
        let b = DollhouseGeometry.scenePoint(
            Point(x: to.x, y: to.y), y: toFloor.baseY + Self.routeLift)
        guard let geometry = RouteGeometry.tubeGeometry(
            points: [a, b], radius: Self.tubeRadius,
            radialSegments: Self.radialSegments
        ) else { return }

        let node = SCNNode(geometry: geometry)
        node.name = "evacuationTrack:\(trackID):floorCrossing"
        node.geometry?.firstMaterial = Self.material
        node.renderingOrder = RenderOrder.routes + 3
        node.castsShadow = false
        dollhouse?.scene.rootNode.addChildNode(node)
        addedNodes.append(node)
    }

    private static func isSafeSceneCoordinate(_ value: Double) -> Bool {
        value.isFinite && abs(value) <= maximumSafeSceneMagnitude
    }
}
