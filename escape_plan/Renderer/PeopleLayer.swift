//  PeopleLayer.swift
//  Renderer — static household figures and deterministic evacuation playback.
//
//  The backend owns the route and its timing. This layer only lifts those supplied plan-space
//  samples into the already-built dollhouse, applies procedural joint poses, and keeps every
//  node it adds under explicit ownership. There are no SceneKit actions or client-side paths:
//  any modeled instant, including one reached by scrubbing backwards, is rendered directly.

import Foundation
import SceneKit

/// Setup is main-actor work; `update(time:reduceMotion:)` is intentionally nonisolated because
/// SceneKit invokes its renderer delegate on the render thread. The immutable animation storage
/// is swapped under a lock, so a rebuild can never expose a half-configured set of figures.
nonisolated final class PeopleLayer {

    private final class FigureState {
        let rig: PersonFixture.Rig
        let sampler: PathSampler
        let cycle: GaitCycle
        let phaseLock: GaitPhaseLock
        let laneOffsetM: Double
        let baseHeights: [String: Double]
        let reducedMotionTimes: [Double]
        let windowSillM: Double?
        let finalSegmentIndex: Int?
        let reachesLeftRail: Bool

        init(rig: PersonFixture.Rig,
             sampler: PathSampler,
             cycle: GaitCycle,
             phaseLock: GaitPhaseLock,
             laneOffsetM: Double,
             baseHeights: [String: Double],
             reducedMotionTimes: [Double],
             windowSillM: Double?,
             finalSegmentIndex: Int?,
             reachesLeftRail: Bool) {
            self.rig = rig
            self.sampler = sampler
            self.cycle = cycle
            self.phaseLock = phaseLock
            self.laneOffsetM = laneOffsetM
            self.baseHeights = baseHeights
            self.reducedMotionTimes = reducedMotionTimes
            self.windowSillM = windowSillM
            self.finalSegmentIndex = finalSegmentIndex
            self.reachesLeftRail = reachesLeftRail
        }

        /// In Reduce Motion, figures occupy engine-supplied waypoints rather than gliding
        /// between them. The playback model also advances in discrete time jumps; this second
        /// guard means manual scrubbing cannot accidentally reintroduce continuous motion.
        func reducedMotionSampleTime(for requestedTime: Double) -> Double {
            guard let first = reducedMotionTimes.first,
                  let last = reducedMotionTimes.last else { return requestedTime }
            let time: Double
            if requestedTime == .infinity {
                time = last
            } else if requestedTime.isFinite {
                time = requestedTime
            } else {
                time = first
            }
            if time <= first { return first }
            if time >= last { return last }

            // Upper bound: exact duplicate timestamps resolve to the final atomic waypoint.
            var low = 0
            var high = reducedMotionTimes.count
            while low < high {
                let middle = low + (high - low) / 2
                if reducedMotionTimes[middle] <= time {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return reducedMotionTimes[max(0, low - 1)]
        }
    }

    private final class AnimationStorage {
        let figures: [FigureState]

        init(figures: [FigureState]) {
            self.figures = figures
        }
    }

    @MainActor private weak var dollhouse: DollhouseScene?
    @MainActor private var addedNodes: [SCNNode] = []
    @MainActor private(set) var figureNodesByProfileID: [String: SCNNode] = [:]

    private let animationLock = NSLock()
    private var animationStorage: AnimationStorage?

    /// Lets a playback coordinator suppress the standing bedroom figures without destroying
    /// them. Later profile redraws inherit the same state, preventing static/animated doubles.
    @MainActor
    var isVisible: Bool = true {
        didSet {
            // The render callback may be assigning transforms to these same animated nodes.
            // Keep visibility changes in the same short critical section as update/clear so
            // SceneKit never receives simultaneous mutations from two threads.
            animationLock.lock()
            defer { animationLock.unlock() }
            for node in addedNodes { node.isHidden = !isVisible }
        }
    }

    @MainActor
    init(dollhouse: DollhouseScene) {
        self.dollhouse = dollhouse
    }

    /// Places one figure per profile at the centroid of its bedroom.
    @MainActor
    @discardableResult
    func show(profiles: [Profile], home: HomeModel, highlighted: String?) -> [String] {
        clear()
        guard let dollhouse else { return [] }
        var issues: [String] = []
        let baseHeights = DollhouseGeometry.floorBaseHeights(of: home)

        for profile in profiles {
            guard let (floorID, room) = home.locateRoom(profile.bedroom_room_id) else {
                issues.append("\(profile.name)'s bedroom (\(profile.bedroom_room_id)) "
                              + "isn't in this home.")
                continue
            }
            let node = PersonFixture.node(
                id: profile.id,
                name: profile.name,
                highlighted: profile.id == highlighted,
                kind: Self.figureKind(for: profile.tags)
            )
            node.position = DollhouseGeometry.scenePoint(
                Geometry.centroid(room.polygon),
                y: baseHeights[floorID] ?? 0
            )
            node.isHidden = !isVisible
            dollhouse.scene.rootNode.addChildNode(node)
            addedNodes.append(node)
            figureNodesByProfileID[profile.id] = node
        }
        return issues
    }

    /// Builds articulated figures for an engine-produced timeline. Geometry, samplers, phase
    /// locks, floor heights, window metadata and lane offsets are all cached here; the renderer
    /// callback performs no hierarchy searches and allocates no collections.
    @MainActor
    @discardableResult
    func show(timeline: EvacuationTimeline,
              home: HomeModel,
              highlighted: String? = nil) -> [String] {
        clear()
        guard let dollhouse else { return [] }
        guard timeline.home_id == home.home_id else {
            return ["evacuation timeline belongs to home '\(timeline.home_id)', "
                    + "not '\(home.home_id)'"]
        }

        let baseHeights = DollhouseGeometry.floorBaseHeights(of: home)
        var openingsByID: [String: Opening] = [:]
        for floor in home.floors {
            for opening in floor.openings where openingsByID[opening.id] == nil {
                openingsByID[opening.id] = opening
            }
        }

        var figures: [FigureState] = []
        figures.reserveCapacity(timeline.tracks.count)
        var issues: [String] = []
        var seenProfileIDs: Set<String> = []
        let centerIndex = Double(max(timeline.tracks.count - 1, 0)) / 2

        for (index, track) in timeline.tracks.enumerated() {
            guard seenProfileIDs.insert(track.profile_id).inserted else {
                issues.append("timeline repeats profile '\(track.profile_id)'")
                continue
            }
            guard !track.steps.isEmpty else {
                issues.append("track for '\(track.profile_name)' has no timed steps")
                continue
            }

            let unknownFloors = Set(track.steps.map(\.floor_id)).filter {
                baseHeights[$0] == nil
            }.sorted()
            guard unknownFloors.isEmpty else {
                issues.append("track for '\(track.profile_name)' references unknown floor(s): "
                              + unknownFloors.joined(separator: ", "))
                continue
            }

            let windowSill: Double?
            if track.uses_window {
                if let opening = openingsByID[track.exit_id], opening.kind == .window,
                   opening.sill_height_m.isFinite, opening.sill_height_m >= 0 {
                    windowSill = opening.sill_height_m
                } else {
                    windowSill = nil
                    issues.append("window track for '\(track.profile_name)' cannot resolve "
                                  + "window exit '\(track.exit_id)'")
                }
            } else {
                windowSill = nil
            }

            let kind = Self.figureKind(for: track.gait)
            let rig = PersonFixture.makeRig(
                id: track.profile_id,
                name: track.profile_name,
                highlighted: track.profile_id == highlighted,
                kind: kind
            )
            rig.rootNode.isHidden = !isVisible
            dollhouse.scene.rootNode.addChildNode(rig.rootNode)
            addedNodes.append(rig.rootNode)
            figureNodesByProfileID[track.profile_id] = rig.rootNode

            let sampler = PathSampler(steps: track.steps)
            let cycle = GaitCycle(kind: track.gait)
            let laneOffset = (Double(index) - centerIndex) * Self.laneSpacingM
            let state = FigureState(
                rig: rig,
                sampler: sampler,
                cycle: cycle,
                phaseLock: GaitPhaseLock(sampler: sampler, cycle: cycle),
                laneOffsetM: laneOffset,
                baseHeights: baseHeights,
                reducedMotionTimes: Self.sanitizedTimes(from: track.steps),
                windowSillM: windowSill,
                finalSegmentIndex: track.uses_window && track.steps.count >= 2
                    ? track.steps.count - 2 : nil,
                reachesLeftRail: index.isMultiple(of: 2)
            )
            figures.append(state)
        }

        animationLock.lock()
        animationStorage = AnimationStorage(figures: figures)
        animationLock.unlock()
        update(time: 0, reduceMotion: false)
        return issues
    }

    /// Applies an absolute pose for one modeled instant. This is the render-thread hot path:
    /// it creates only value types, does no node-tree search, and never queues SceneKit actions.
    func update(time requestedTime: Double, reduceMotion: Bool) {
        animationLock.lock()
        guard let storage = animationStorage else {
            animationLock.unlock()
            return
        }
        // Retaining storage alone is not enough: clear() could otherwise detach its nodes while
        // this callback was mutating them. Holding the lock for the sub-millisecond transform
        // pass makes storage lifetime and scene-graph ownership one atomic boundary.
        defer { animationLock.unlock() }

        let time: Double
        if requestedTime == .infinity {
            time = .infinity
        } else if requestedTime.isFinite {
            time = max(0, requestedTime)
        } else {
            time = 0
        }
        for figure in storage.figures {
            let sampleTime = reduceMotion
                ? figure.reducedMotionSampleTime(for: time)
                : time
            guard let path = figure.sampler.sample(at: sampleTime) else { continue }

            let heading = path.heading.isFinite ? path.heading : 0
            let perpendicularX = -sin(heading)
            let perpendicularY = cos(heading)
            let planX = path.position.x + perpendicularX * figure.laneOffsetM
            let planY = path.position.y + perpendicularY * figure.laneOffsetM
            let baseY = Self.baseHeight(for: path, in: figure.baseHeights)

            let isWindowSegment = !reduceMotion
                && !path.hasReachedEnd
                && path.segmentIndex == figure.finalSegmentIndex
                && figure.windowSillM != nil
            let windowProgress = isWindowSegment ? path.segmentProgress : 0
            let windowLift = isWindowSegment
                ? Self.windowLift(sillM: figure.windowSillM ?? 0,
                                  progress: windowProgress)
                : 0

            figure.rig.rootNode.position = SCNVector3(
                Float(Self.finiteOrZero(planX)),
                Float(Self.finiteOrZero(baseY + windowLift)),
                Float(Self.finiteOrZero(-planY))
            )
            // Plan θ maps to scene (cos θ, 0, -sin θ); the authored figure faces local +z.
            figure.rig.rootNode.eulerAngles.y = Float(heading + .pi / 2)

            if reduceMotion {
                figure.rig.apply(.neutral)
                continue
            }

            let phase = figure.phaseLock.sample(for: path)
            let gaitPose = figure.cycle.pose(
                at: phase.phase,
                effectiveStrideLength: phase.effectiveStrideLength
            )
            var pose = Self.rigPose(from: gaitPose)
            if path.floorTransition != nil {
                Self.applyStairPose(to: &pose,
                                    phase: phase.phase,
                                    railSideIsLeft: figure.rig.kind == .pet
                                        || figure.rig.kind == .wheelchair
                                        ? nil : figure.reachesLeftRail)
            } else if isWindowSegment {
                Self.applyWindowPose(to: &pose,
                                     progress: windowProgress,
                                     leadingLeft: figure.reachesLeftRail)
            }
            figure.rig.apply(pose)
        }
    }

    @MainActor
    func clear() {
        animationLock.lock()
        defer { animationLock.unlock() }
        animationStorage = nil

        for node in addedNodes { node.removeFromParentNode() }
        addedNodes.removeAll(keepingCapacity: true)
        figureNodesByProfileID.removeAll(keepingCapacity: true)
    }

    /// Walks up from a hit-test result to the `person:<id>` container.
    static func profileID(forHit node: SCNNode) -> String? {
        var current: SCNNode? = node
        while let candidate = current {
            if let name = candidate.name, name.hasPrefix("person:") {
                return String(name.dropFirst("person:".count))
            }
            current = candidate.parent
        }
        return nil
    }

    // MARK: - Setup helpers

    private static let laneSpacingM = 0.06

    private static func figureKind(for gait: GaitKind) -> PersonFixture.FigureKind {
        switch gait {
        case .adult, .unknown: return .adult
        case .child: return .child
        case .elderly: return .elderly
        case .wheelchair: return .wheelchair
        case .pet: return .pet
        }
    }

    /// Matches the backend's tag precedence, but affects only the static silhouette.
    private static func figureKind(for tags: [ProfileTag]) -> PersonFixture.FigureKind {
        if tags.contains(.mobility_limited) { return .wheelchair }
        if tags.contains(.pet) { return .pet }
        if tags.contains(.child) { return .child }
        if tags.contains(.elderly) { return .elderly }
        return .adult
    }

    private static func sanitizedTimes(from steps: [TimedStep]) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(steps.count)
        for step in steps {
            let fallback = result.last ?? 0
            let proposed = step.t_s.isFinite ? step.t_s : fallback
            result.append(max(fallback, proposed))
        }
        return result
    }

    // MARK: - Render helpers

    private static func baseHeight(for sample: PathSample,
                                   in heights: [String: Double]) -> Double {
        if let crossing = sample.floorTransition,
           let from = heights[crossing.fromFloorID],
           let to = heights[crossing.toFloorID] {
            let progress = min(max(crossing.progress, 0), 1)
            return finiteOrZero(from + (to - from) * progress)
        }
        return finiteOrZero(heights[sample.floorID] ?? 0)
    }

    private static func windowLift(sillM: Double, progress: Double) -> Double {
        let p = min(max(finiteOrZero(progress), 0), 1)
        let controlledArc = sin(.pi * p)
        return max(0.18, min(max(sillM, 0), 1.4) * 0.82) * controlledArc
    }

    private static func rigPose(from gait: GaitPose) -> PersonFixture.Pose {
        var pose = PersonFixture.Pose()
        pose.verticalOffset = Float(finiteOrZero(gait.torsoBob))
        pose.pelvis.yaw = Float(finiteOrZero(gait.pelvisCounterRotation))
        pose.spine.pitch = Float(finiteOrZero(gait.spinePitch))
        pose.spine.yaw = Float(finiteOrZero(gait.spineTwist))
        pose.leftShoulder.pitch = Float(finiteOrZero(gait.leftShoulder))
        pose.rightShoulder.pitch = Float(finiteOrZero(gait.rightShoulder))
        pose.leftElbow.pitch = Float(finiteOrZero(gait.leftElbow))
        pose.rightElbow.pitch = Float(finiteOrZero(gait.rightElbow))
        pose.leftHip.pitch = Float(finiteOrZero(gait.leftHip))
        pose.rightHip.pitch = Float(finiteOrZero(gait.rightHip))
        pose.leftKnee.pitch = Float(finiteOrZero(gait.leftKnee))
        pose.rightKnee.pitch = Float(finiteOrZero(gait.rightKnee))
        pose.leftAnkle.pitch = Float(finiteOrZero(gait.leftAnkle))
        pose.rightAnkle.pitch = Float(finiteOrZero(gait.rightAnkle))
        pose.leftWheelRotation = Float(finiteOrZero(gait.wheelRotation))
        pose.rightWheelRotation = Float(finiteOrZero(gait.wheelRotation))
        pose.tail.yaw = Float(finiteOrZero(gait.tailSwing))
        return pose
    }

    private static func applyStairPose(to pose: inout PersonFixture.Pose,
                                       phase: Double,
                                       railSideIsLeft: Bool?) {
        let stepping = Float(0.5 - 0.5 * cos(2 * .pi * finiteOrZero(phase)))
        pose.spine.pitch += 0.15
        pose.leftKnee.pitch += 0.22 + 0.20 * stepping
        pose.rightKnee.pitch += 0.42 - 0.20 * stepping
        if railSideIsLeft == true {
            pose.leftShoulder.roll -= 0.32
            pose.leftElbow.pitch += 0.24
        } else if railSideIsLeft == false {
            pose.rightShoulder.roll += 0.32
            pose.rightElbow.pitch += 0.24
        }
    }

    private static func applyWindowPose(to pose: inout PersonFixture.Pose,
                                        progress: Double,
                                        leadingLeft: Bool) {
        let p = min(max(finiteOrZero(progress), 0), 1)
        let effort = Float(sin(.pi * p))
        pose.spine.pitch += 0.30 * effort
        pose.leftShoulder.pitch -= 0.55 * effort
        pose.rightShoulder.pitch -= 0.55 * effort
        pose.leftElbow.pitch += 0.38 * effort
        pose.rightElbow.pitch += 0.38 * effort
        if leadingLeft {
            pose.leftHip.pitch += 0.58 * effort
            pose.leftKnee.pitch += 0.92 * effort
            pose.rightKnee.pitch += 0.24 * effort
        } else {
            pose.rightHip.pitch += 0.58 * effort
            pose.rightKnee.pitch += 0.92 * effort
            pose.leftKnee.pitch += 0.24 * effort
        }
    }

    private static func finiteOrZero(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }
}
