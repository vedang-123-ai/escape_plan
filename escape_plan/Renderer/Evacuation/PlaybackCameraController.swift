//  PlaybackCameraController.swift
//  Renderer/Evacuation
//
//  Optional automatic framing for an evacuation timeline. It owns one temporary camera node,
//  never mutates OrbitCameraRig's model, and restores the manual point of view as soon as the
//  user begins a gesture. Automatic framing stays suspended until explicitly resumed, so a
//  playback tick can never steal the camera back from the user's hand.
//
//  Figure nodes are resolved once during `configure`; `update` walks weak bindings in place and
//  allocates no positions array per frame. The caller owns the playback clock and renderer
//  delegate. Reduce Motion is passed in from EvacuationPlaybackModel.isSteppedMode.

import SceneKit
import UIKit

nonisolated final class PlaybackCameraController {

    enum FramingMode: Equatable {
        /// Fit everyone who has not reached their engine-supplied egress time. At the final
        /// instant, retain a stable frame containing all settled figures.
        case allActive
        /// Fit every figure, including occupants already settled outside.
        case allOccupants
        /// Follow the active occupant with the latest egress time — the last person out.
        case lastEscaping
    }

    struct Tuning {
        var framingMargin: Double = 1.32
        var minimumSubjectRadius_m: Double = 0.78
        var subjectCenterLift_m: Double = 0.72
        var minimumCameraDistance_m: Double = 2.4
        var smoothingTime_s: Double = 0.24
        /// A modeled-time jump above this is a seek, not ordinary playback; snap so scrubbing
        /// does not leave the camera easing toward a stale instant.
        var seekSnapThreshold_s: Double = 0.45

        static let `default` = Tuning()
    }

    private final class FigureBinding {
        let profileID: String
        let egressTime_s: Double
        weak var node: SCNNode?

        init(profileID: String, egressTime_s: Double, node: SCNNode) {
            self.profileID = profileID
            self.egressTime_s = egressTime_s.isFinite ? max(0, egressTime_s) : 0
            self.node = node
        }
    }

    private struct FrameAccumulator {
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        var count = 0

        mutating func include(_ point: SCNVector3) {
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return }
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
            minZ = min(minZ, point.z); maxZ = max(maxZ, point.z)
            count += 1
        }

        var center: SCNVector3 {
            SCNVector3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
        }

        var radius: Double {
            let dx = Double(maxX - minX)
            let dy = Double(maxY - minY)
            let dz = Double(maxZ - minZ)
            return (dx * dx + dy * dy + dz * dz).squareRoot() / 2
        }
    }

    private struct TargetFrame {
        let center: SCNVector3
        let distance: Double
        let orthographicScale: Double
    }

    private weak var dollhouse: DollhouseScene?
    private weak var view: SCNView?
    private weak var preferredManualCameraNode: SCNNode?
    private weak var restorePointOfView: SCNNode?
    private let cameraNode = SCNNode()
    private let tuning: Tuning

    private var bindings: [FigureBinding] = []
    private var mode: FramingMode
    private(set) var isAutomaticallyFraming = false
    private(set) var isUnderManualOverride = false

    private var viewportAspect: Double
    private var viewDirection = normalized(SCNVector3(1, 0.82, 1))
    private var hasDerivedViewDirection = false
    private var currentCenter: SCNVector3?
    private var currentDistance: Double?
    private var currentOrthographicScale: Double?
    private var lastPlaybackTime_s: Double?
    private var lastReduceMotion: Bool?

    @MainActor
    init(dollhouse: DollhouseScene,
         view: SCNView,
         manualCameraNode: SCNNode? = nil,
         mode: FramingMode = .allActive,
         tuning: Tuning = .default) {
        self.dollhouse = dollhouse
        self.view = view
        self.preferredManualCameraNode = manualCameraNode
        self.mode = mode
        self.tuning = tuning
        let width = max(Double(view.bounds.width), 1)
        let height = max(Double(view.bounds.height), 1)
        self.viewportAspect = width / height
        cameraNode.name = "evacuationPlaybackCamera"
    }

    /// Resolve each timeline track to the animated node owned by PeopleLayer. The provider is
    /// invoked only here, never in the per-frame callback.
    @MainActor
    @discardableResult
    func configure(timeline: EvacuationTimeline,
                   mode newMode: FramingMode? = nil,
                   figureNodeProvider: (String) -> SCNNode?) -> [String] {
        if let newMode { mode = newMode }
        bindings.removeAll(keepingCapacity: true)
        bindings.reserveCapacity(timeline.tracks.count)
        var issues: [String] = []
        for track in timeline.tracks {
            guard let node = figureNodeProvider(track.profile_id) else {
                issues.append("playback camera could not resolve figure '\(track.profile_id)'")
                continue
            }
            bindings.append(FigureBinding(profileID: track.profile_id,
                                          egressTime_s: track.egress_time_s,
                                          node: node))
        }
        resetSmoothing()
        if bindings.isEmpty, isAutomaticallyFraming {
            stopAutomaticFraming(restoringManualCamera: true)
        }
        return issues
    }

    /// Dictionary convenience for coordinators that already keep PeopleLayer's roots by id.
    @MainActor
    @discardableResult
    func configure(timeline: EvacuationTimeline,
                   figureNodes: [String: SCNNode],
                   mode newMode: FramingMode? = nil) -> [String] {
        configure(timeline: timeline, mode: newMode) { figureNodes[$0] }
    }

    /// Configure and take the point of view in one call at playback start.
    @MainActor
    @discardableResult
    func begin(timeline: EvacuationTimeline,
               figureNodes: [String: SCNNode],
               mode newMode: FramingMode? = nil) -> [String] {
        let issues = configure(timeline: timeline, figureNodes: figureNodes, mode: newMode)
        resumeAutomaticFraming()
        return issues
    }

    /// Takes the point of view without advancing anything. Safe to call repeatedly.
    @MainActor
    func resumeAutomaticFraming() {
        guard !bindings.isEmpty, let dollhouse, let view else { return }
        isUnderManualOverride = false
        if isAutomaticallyFraming { return }

        let source = preferredManualCameraNode
            ?? (view.pointOfView === cameraNode ? restorePointOfView : view.pointOfView)
            ?? dollhouse.cameraNode
        restorePointOfView = source
        cameraNode.camera = (source.camera?.copy() as? SCNCamera)
            ?? (dollhouse.cameraNode.camera?.copy() as? SCNCamera)
            ?? SCNCamera()
        cameraNode.camera?.zNear = min(cameraNode.camera?.zNear ?? 0.1, 0.1)
        cameraNode.camera?.zFar = max(cameraNode.camera?.zFar ?? 100, 100)
        // The playback node is parented at the scene root, so the source's world transform is
        // the correct local transform even when the manual camera came from a nested rig.
        cameraNode.transform = source.presentation.worldTransform
        cameraNode.removeFromParentNode()
        dollhouse.scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        isAutomaticallyFraming = true
        resetSmoothing()
    }

    /// Call before OrbitCameraRig.beginOrbit / truck / pinch. The restore happens immediately,
    /// and subsequent playback updates remain no-ops until `resumeAutomaticFraming()`.
    @MainActor
    func userDidBeginManualControl() {
        isUnderManualOverride = true
        stopAutomaticFraming(restoringManualCamera: true)
    }

    @MainActor
    func stopAutomaticFraming(restoringManualCamera: Bool = true) {
        if restoringManualCamera, let view {
            view.pointOfView = preferredManualCameraNode
                ?? restorePointOfView
                ?? dollhouse?.cameraNode
        }
        cameraNode.removeFromParentNode()
        isAutomaticallyFraming = false
        resetSmoothing()
    }

    /// Apply one instant from the shared playback model. This two-argument form is convenient
    /// for render callbacks; use the overload with `isPlaying` when the coordinator has it so a
    /// paused scrub snaps immediately instead of smoothing.
    func update(time: Double, reduceMotion: Bool) {
        update(time: time, isPlaying: true, reduceMotion: reduceMotion)
    }

    func update(time: Double, isPlaying: Bool, reduceMotion: Bool) {
        guard isAutomaticallyFraming, !isUnderManualOverride else { return }
        let now = time.isFinite ? max(0, time) : 0

        // In stepped mode the playback model holds time between jumps. Avoid even rewriting
        // the camera transform while that instant is unchanged; on a jump, snap once.
        if reduceMotion, lastReduceMotion == true, lastPlaybackTime_s == now { return }

        guard let target = targetFrame(at: now) else { return }
        let previousTime = lastPlaybackTime_s
        let enteredReduceMotion = reduceMotion && lastReduceMotion != true
        lastPlaybackTime_s = now
        lastReduceMotion = reduceMotion

        let shouldSnap: Bool
        if currentCenter == nil || currentDistance == nil || currentOrthographicScale == nil
            || reduceMotion || enteredReduceMotion
            || !isPlaying || previousTime == nil {
            shouldSnap = true
        } else {
            let delta = now - (previousTime ?? now)
            shouldSnap = delta < 0 || delta > tuning.seekSnapThreshold_s
        }

        let center: SCNVector3
        let distance: Double
        let orthographicScale: Double
        if shouldSnap {
            center = target.center
            distance = target.distance
            orthographicScale = target.orthographicScale
        } else {
            let delta = max(now - (previousTime ?? now), 1.0 / 120.0)
            let alpha = 1 - exp(-delta / max(tuning.smoothingTime_s, 0.001))
            center = lerp(currentCenter ?? target.center, target.center, amount: alpha)
            distance = (currentDistance ?? target.distance)
                + (target.distance - (currentDistance ?? target.distance)) * alpha
            orthographicScale = (currentOrthographicScale ?? target.orthographicScale)
                + (target.orthographicScale
                   - (currentOrthographicScale ?? target.orthographicScale)) * alpha
        }

        if !hasDerivedViewDirection {
            let source = restorePointOfView ?? preferredManualCameraNode
            if let source {
                let candidate = source.presentation.worldPosition - center
                if length(candidate) > 0.01 { viewDirection = normalized(candidate) }
            }
            hasDerivedViewDirection = true
        }

        currentCenter = center
        currentDistance = distance
        currentOrthographicScale = orthographicScale
        let position = center + viewDirection * Float(distance)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        cameraNode.position = position
        cameraNode.look(at: center)
        if cameraNode.camera?.usesOrthographicProjection == true {
            // Moving an orthographic camera along its view axis does not zoom. Drive the
            // matched CameraTuning half-height explicitly so the fit works in both projections.
            cameraNode.camera?.orthographicScale = orthographicScale
        }
        SCNTransaction.commit()
    }

    /// Call from layout/orientation handling, not the render callback.
    func updateViewportSize(_ size: CGSize) {
        viewportAspect = max(Double(size.width), 1) / max(Double(size.height), 1)
        resetSmoothing()
    }

    /// Removes only the temporary camera, drops weak figure bindings, and returns control.
    func clear() {
        let oldView = view
        let oldPlaybackCamera = cameraNode
        let manualCamera = preferredManualCameraNode ?? restorePointOfView

        // Render-state teardown stays synchronous and nonisolated. UIKit's point-of-view
        // mutation is main-actor work; when clear is requested off-main, defer only that small
        // handoff and guard against clobbering a newer playback camera installed in the interim.
        cameraNode.removeFromParentNode()
        isAutomaticallyFraming = false
        resetSmoothing()
        bindings.removeAll(keepingCapacity: true)
        restorePointOfView = nil
        isUnderManualOverride = false

        let restoreView = { @MainActor [weak oldView, weak oldPlaybackCamera,
                                        weak manualCamera] in
            guard let oldView, let oldPlaybackCamera,
                  oldView.pointOfView === oldPlaybackCamera else { return }
            oldView.pointOfView = manualCamera
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(restoreView)
        } else {
            DispatchQueue.main.async(execute: restoreView)
        }
    }

    // MARK: - Framing

    private func targetFrame(at time: Double) -> TargetFrame? {
        var accumulator = FrameAccumulator()

        switch mode {
        case .allOccupants:
            includeAllFigures(in: &accumulator)

        case .allActive:
            for binding in bindings where time < binding.egressTime_s {
                include(binding, in: &accumulator)
            }
            if accumulator.count == 0 { includeAllFigures(in: &accumulator) }

        case .lastEscaping:
            var chosen: FigureBinding?
            for binding in bindings where binding.node?.parent != nil && time < binding.egressTime_s {
                if chosen == nil || binding.egressTime_s > chosen!.egressTime_s
                    || (binding.egressTime_s == chosen!.egressTime_s
                        && binding.profileID < chosen!.profileID) {
                    chosen = binding
                }
            }
            if chosen == nil {
                for binding in bindings where binding.node?.parent != nil {
                    if chosen == nil || binding.egressTime_s > chosen!.egressTime_s
                        || (binding.egressTime_s == chosen!.egressTime_s
                            && binding.profileID < chosen!.profileID) {
                        chosen = binding
                    }
                }
            }
            if let chosen { include(chosen, in: &accumulator) }
        }

        guard accumulator.count > 0 else { return nil }
        var center = accumulator.center
        center.y += Float(tuning.subjectCenterLift_m)
        let radius = max(accumulator.radius + tuning.subjectCenterLift_m * 0.35,
                         tuning.minimumSubjectRadius_m)
        let verticalFOV = max((cameraNode.camera?.fieldOfView ?? 50) * .pi / 180, 0.1)
        let horizontalFOV = 2 * atan(tan(verticalFOV / 2) * max(viewportAspect, 0.1))
        let limitingFOV = min(verticalFOV, horizontalFOV)
        let fitDistance = radius / max(tan(limitingFOV / 2), 0.05) * tuning.framingMargin
        let distance = max(fitDistance, tuning.minimumCameraDistance_m)
        // `fitDistance` used the limiting (horizontal in portrait) FOV. Convert the fitted
        // distance through this camera's vertical FOV exactly once to obtain its half-height.
        let orthographicScale = max(distance, 0.01) * tan(verticalFOV / 2)
        return TargetFrame(center: center, distance: distance,
                           orthographicScale: orthographicScale)
    }

    private func includeAllFigures(in accumulator: inout FrameAccumulator) {
        for binding in bindings { include(binding, in: &accumulator) }
    }

    private func include(_ binding: FigureBinding, in accumulator: inout FrameAccumulator) {
        guard let node = binding.node, node.parent != nil, !node.isHidden else { return }
        // PeopleLayer writes model transforms earlier in the same renderer callback. Reading
        // `worldPosition` observes that instant immediately; `presentation` may lag one frame.
        accumulator.include(node.worldPosition)
    }

    private func resetSmoothing() {
        currentCenter = nil
        currentDistance = nil
        currentOrthographicScale = nil
        lastPlaybackTime_s = nil
        lastReduceMotion = nil
        hasDerivedViewDirection = false
    }
}

// MARK: - Tiny allocation-free vector helpers

nonisolated private func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
}

nonisolated private func - (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
    SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
}

nonisolated private func * (lhs: SCNVector3, rhs: Float) -> SCNVector3 {
    SCNVector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
}

nonisolated private func length(_ vector: SCNVector3) -> Float {
    (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
}

nonisolated private func normalized(_ vector: SCNVector3) -> SCNVector3 {
    let magnitude = length(vector)
    guard magnitude > 1e-6 else { return SCNVector3(1, 0.82, 1) }
    return vector * (1 / magnitude)
}

nonisolated private func lerp(_ from: SCNVector3, _ to: SCNVector3,
                              amount: Double) -> SCNVector3 {
    let t = Float(min(max(amount, 0), 1))
    return SCNVector3(from.x + (to.x - from.x) * t,
                      from.y + (to.y - from.y) * t,
                      from.z + (to.z - from.z) * t)
}
