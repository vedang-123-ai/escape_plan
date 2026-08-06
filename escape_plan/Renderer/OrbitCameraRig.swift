//  OrbitCameraRig.swift
//
//  Binds the pure `CameraRigModel` (Editor/Core) to a persistent SCNNode. The node is owned
//  here — by the view layer, not by any built scene — and re-attached after every
//  `DollhouseSceneBuilder.build`, which is what keeps the camera exactly where the user left
//  it across the editor's rebuild-on-every-edit strategy.

import SceneKit
import UIKit

@MainActor
final class OrbitCameraRig {

    let node: SCNNode
    private(set) var model: CameraRigModel

    /// Full drag across the view height orbits by ~π — brisk but controllable.
    private let orbitRadiansPerViewHeight = Double.pi

    /// Called whenever the rig moves itself (inertia, springs), so the host can redraw.
    var onChange: (() -> Void)?
    /// Set by the host to flip `SCNView.rendersContinuously` only while the camera is animating.
    var continuousRenderingSink: ((Bool) -> Void)?

    private weak var attachedView: SCNView?
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var inertiaYaw: Double = 0
    private var inertiaPitch: Double = 0
    /// Pan momentum, in meters/second along the camera's own right/up axes.
    private var inertiaRight: Double = 0
    private var inertiaUp: Double = 0
    /// Camera gestures in flight. Counted because pan and pinch recognize simultaneously.
    private var gestureDepth = 0
    /// When the current explicit spring/tour animation finishes; until then the view must keep
    /// redrawing or the animation is invisible on a static scene.
    private var animationDeadline: CFTimeInterval = 0
    private var lastOrbitRate: (yaw: Double, pitch: Double) = (0, 0)
    /// Accumulated travel of the current gesture, used to pick the orbit axis once.
    private var gestureTravel: CGPoint = .zero
    /// nil = undecided, true = turntable (yaw only), false = free orbit.
    private var axisLock: Bool?
    /// The world point the in-flight pinch holds fixed, resolved once at `.began` (see #2).
    private var pinchAnchor: CameraRigModel.Vec3?

    init(home: HomeModel) {
        let bounds = DollhouseGeometry.bounds(of: home)
        let totalHeight = home.floorsByLevel.reduce(0.0) { $0 + $1.height_m }
        let extent = max(max(bounds.width, bounds.depth), 1.0)
        let center = bounds.isEmpty ? Point(x: 0, y: 0) : bounds.center

        // Plan (x, y) → scene (x, −z), same mapping as DollhouseGeometry.scenePoint.
        model = CameraRigModel.framing(
            center: CameraRigModel.Vec3(x: center.x, y: 0, z: -center.y),
            extent: extent,
            totalHeight: totalHeight
        )

        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = extent * 40
        // Projection direction stays `.automatic`. Pinning it horizontally sounds right (the
        // house's width always fits) but on a full-screen 1:2.2 viewport it implies a ~90°
        // vertical FOV — the model shrinks and the wide-angle distortion skews it badly.
        //
        // Projection, FOV and ambient occlusion come from CameraTuning so this camera and the
        // builder's static one agree; a mismatch shows up as a jump when the tour hands the
        // point of view back.
        CameraTuning.configure(camera)
        node = SCNNode()
        node.camera = camera
        node.name = "orbitRigCamera"
        applyNow()
    }

    deinit { displayLink?.invalidate() }

    /// Re-parents the rig's camera into a (re)built scene and makes it the point of view.
    /// Safe to call repeatedly; the model — and therefore the view the user sees — is untouched.
    func attach(to scene: SCNScene, view: SCNView) {
        node.removeFromParentNode()
        scene.rootNode.addChildNode(node)
        view.pointOfView = node
        attachedView = view
        applyNow()
    }

    /// Reset to the opening three-quarter framing for a (possibly different) home.
    func reframe(for home: HomeModel) {
        let bounds = DollhouseGeometry.bounds(of: home)
        let totalHeight = home.floorsByLevel.reduce(0.0) { $0 + $1.height_m }
        let extent = max(max(bounds.width, bounds.depth), 1.0)
        let center = bounds.isEmpty ? Point(x: 0, y: 0) : bounds.center
        model = CameraRigModel.framing(
            center: CameraRigModel.Vec3(x: center.x, y: 0, z: -center.y),
            extent: extent,
            totalHeight: totalHeight
        )
        node.camera?.zFar = extent * 40
        applyNow()
    }

    // MARK: - Gestures → model

    /// Call at the start of every orbit gesture: resets the axis-lock sampler and kills any
    /// inertia still running, so a new touch takes control immediately.
    func beginOrbit() {
        stopInertia()
        gestureTravel = .zero
        axisLock = nil
    }

    func orbit(byScreenDelta delta: CGPoint, in view: SCNView) {
        guard view.bounds.height > 0 else { return }
        let s = orbitRadiansPerViewHeight / Double(view.bounds.height)

        // Decide once per gesture whether this is a turntable spin or a free orbit, from the
        // first ~12 pt of travel.
        gestureTravel.x += delta.x
        gestureTravel.y += delta.y
        if axisLock == nil {
            let lock = CameraRigModel.shouldLockToYaw(dx: Double(gestureTravel.x),
                                                      dy: Double(gestureTravel.y))
            if abs(gestureTravel.x) + abs(gestureTravel.y) >= 12 { axisLock = lock }
        }

        let dYaw = -Double(delta.x) * s
        let dPitch = (axisLock == true) ? 0 : -Double(delta.y) * s
        model.orbit(deltaYaw: dYaw, deltaPitch: dPitch)
        lastOrbitRate = (yaw: dYaw, pitch: dPitch)
        applyNow()
    }

    /// Hand the recognizer's exit velocity to the rig so the turntable keeps spinning and eases
    /// out, instead of stopping dead the frame the finger lifts — which is most of why orbiting
    /// used to feel abrupt.
    func endOrbit(velocity: CGPoint, in view: SCNView) {
        guard view.bounds.height > 0 else { return }
        let s = orbitRadiansPerViewHeight / Double(view.bounds.height)
        // Velocity is points/second; convert to radians/second, then decay.
        let yawRate = -Double(velocity.x) * s
        let pitchRate = (axisLock == true) ? 0 : -Double(velocity.y) * s
        axisLock = nil
        guard abs(yawRate) + abs(pitchRate) > 0.05 else {
            settle()
            return
        }
        startInertia(yawRate: yawRate, pitchRate: pitchRate)
    }

    func truck(byScreenDelta delta: CGPoint, in view: SCNView, soft: Bool = true) {
        let mpp = model.metersPerPoint(projection: projection(in: view),
                                       viewHeightPoints: Double(view.bounds.height))
        model.truck(rightMeters: -Double(delta.x) * mpp, upMeters: Double(delta.y) * mpp,
                    soft: soft)
        applyNow()
    }

    /// Hand a pan's exit velocity to the rig so the house coasts and eases out, exactly as an
    /// orbit flick does. Without this, pan stopped dead on lift while orbit glided — two
    /// different feels for the same house, from the same finger.
    func endTruck(velocity: CGPoint, in view: SCNView) {
        guard view.bounds.height > 0 else { settle(); return }
        let mpp = model.metersPerPoint(projection: projection(in: view),
                                       viewHeightPoints: Double(view.bounds.height))
        // Same sign convention as `truck`: dragging right moves the pivot left.
        let rightRate = -Double(velocity.x) * mpp
        let upRate = Double(velocity.y) * mpp
        guard abs(rightRate) + abs(upRate) >= Self.panInertiaFloor else {
            settle()
            return
        }
        startInertia(rightRate: rightRate, upRate: upRate)
    }

    /// The projection the attached camera is ACTUALLY using, read from the camera rather than
    /// assumed from `CameraTuning`.
    ///
    /// `truck` used to convert screen points to meters with perspective math unconditionally,
    /// while the default projection is orthographic — so under the shipping camera the house
    /// tracked the finger at a constant wrong ratio. Reading `orthographicScale` back off the
    /// camera (not recomputing it) also picks up the portrait aspect widening `apply()` does,
    /// which any independent recomputation would have to duplicate and could drift from.
    private func projection(in view: SCNView) -> CameraRigModel.Projection {
        guard let camera = node.camera, camera.usesOrthographicProjection else {
            return .perspective(fovDegrees: CameraTuning.fieldOfViewDegrees)
        }
        return .orthographic(halfHeight: camera.orthographicScale)
    }

    /// Resolve and cache the world point the pinch holds fixed. Call once at `.began`.
    ///
    /// The hit test behind this walks the whole dollhouse — walls, doors, windows, furniture,
    /// route tubes, figures. Doing it per recognizer update meant 60–120 full-scene hit tests a
    /// second, and it was wrong as well as slow: zoom-toward-anchor is defined against a FIXED
    /// point, so re-resolving mid-pinch let the anchor crawl under the fingers.
    func beginPinch(at centroid: CGPoint, in view: SCNView) {
        stopInertia()
        pinchAnchor = anchor(at: centroid, in: view)
    }

    /// `scale` is the incremental pinch scale since the last call (caller resets the
    /// recognizer's scale to 1 each time). The world point captured at `.began` stays put.
    ///
    /// `centroid` is only a fallback for callers that never called `beginPinch` (and for a
    /// recognizer whose `.began` was missed); the cached anchor wins whenever it exists.
    func pinch(scale: CGFloat, centroid: CGPoint, in view: SCNView, soft: Bool = true) {
        let target = pinchAnchor ?? anchor(at: centroid, in: view)
        pinchAnchor = target
        model.zoom(scale: Double(scale), towardAnchor: target, soft: soft)
        applyNow()
    }

    /// Release the cached anchor so the next pinch resolves a fresh one.
    func endPinch() {
        pinchAnchor = nil
    }

    /// Spring back inside the limits after a rubber-banded pan or pinch.
    func settle() {
        let target = model.settled()
        guard target != model else { return }
        animate(to: target, duration: 0.3)
    }

    /// Double-tap: zoom in toward the tapped point, or — if already at the closest allowed
    /// distance — treat the tap as "put the house back", which is the thing a user who has
    /// zoomed into a corner actually wants.
    func doubleTap(at point: CGPoint, in view: SCNView, home: HomeModel) {
        if model.distance <= model.distanceRange.lowerBound * 1.02 {
            recenter(on: home)
            return
        }
        var target = model
        target.zoom(scale: 1.6, towardAnchor: anchor(at: point, in: view))
        animate(to: target, duration: 0.28)
    }

    /// Spring the camera back onto the home. `focusY`, when given, is the mid-height of the
    /// floor in focus, so orbiting a basement doesn't swing around the roofline.
    func recenter(on home: HomeModel, focusY: Double? = nil) {
        let bounds = DollhouseGeometry.bounds(of: home)
        let totalHeight = home.floorsByLevel.reduce(0.0) { $0 + $1.height_m }
        let extent = max(max(bounds.width, bounds.depth), 1.0)
        let center = bounds.isEmpty ? Point(x: 0, y: 0) : bounds.center
        let target = model.recentered(
            on: CameraRigModel.Vec3(x: center.x, y: focusY ?? totalHeight * 0.35, z: -center.y),
            extent: extent)
        animate(to: target, duration: 0.5)
    }

    /// Slide the orbit centre to a floor's mid-height without otherwise moving the camera.
    /// Without this, selecting the basement leaves the camera orbiting around the roof and the
    /// controls feel like they are pivoting on the wrong axis.
    func focus(onHeight y: Double) {
        var target = model
        target.pivot = CameraRigModel.Vec3(x: model.pivot.x, y: y, z: model.pivot.z)
        target.clampPivot()
        animate(to: target, duration: 0.35)
    }

    /// True once the camera has wandered far enough from a framed view that offering a recenter
    /// affordance is useful — the chip should appear quietly, like Maps' compass, not sit there
    /// permanently.
    func isOffHome(_ home: HomeModel) -> Bool {
        let bounds = DollhouseGeometry.bounds(of: home)
        guard !bounds.isEmpty else { return false }
        let extent = max(max(bounds.width, bounds.depth), 1.0)
        let dx = model.pivot.x - bounds.center.x
        let dz = model.pivot.z + bounds.center.y
        let drift = (dx * dx + dz * dz).squareRoot()
        return drift > extent * 0.15
            || model.distance > extent * 2.4
            || model.distance < extent * 0.7
    }

    // MARK: - Gesture lifecycle

    /// Bracket every camera gesture with these.
    ///
    /// They exist for the redraw model: between them the view renders continuously, so a drag
    /// is drawn on the frame it happens rather than whenever `setNeedsDisplay` next gets
    /// serviced. Per-event `setNeedsDisplay` alone gives a one-frame-behind, unevenly spaced
    /// drag on a static scene, which is a large part of what "laggy" was.
    ///
    /// Counted, not a flag: pan and pinch are recognized simultaneously, so both are live
    /// during a two-finger manipulation and whichever ends first must not drop the other's
    /// continuous rendering.
    func beginCameraGesture() {
        gestureDepth += 1
        syncMotionState()
    }

    func endCameraGesture() {
        gestureDepth = max(0, gestureDepth - 1)
        syncMotionState()
    }

    // MARK: - Inertia & animation

    /// Exit-velocity half-life, shared by orbit and pan so the two read as the same instrument.
    /// Pan used to stop dead the instant the finger lifted while orbit coasted, which is why
    /// they felt like different controls on the same house.
    private static let inertiaHalfLife: TimeInterval = 0.25
    /// Below these the motion is not visible; carrying it further only burns frames.
    private static let orbitInertiaFloor = 0.02   // radians/second
    private static let panInertiaFloor = 0.01     // meters/second

    private func startInertia(yawRate: Double = 0, pitchRate: Double = 0,
                              rightRate: Double = 0, upRate: Double = 0) {
        inertiaYaw = yawRate
        inertiaPitch = pitchRate
        inertiaRight = rightRate
        inertiaUp = upRate
        lastTick = CACurrentMediaTime()
        syncMotionState()
    }

    private func tickMotion() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 1.0 / 20)
        lastTick = now

        if hasInertia {
            let decay = pow(0.5, dt / Self.inertiaHalfLife)
            inertiaYaw *= decay
            inertiaPitch *= decay
            inertiaRight *= decay
            inertiaUp *= decay
            if inertiaYaw != 0 || inertiaPitch != 0 {
                model.orbit(deltaYaw: inertiaYaw * dt, deltaPitch: inertiaPitch * dt)
            }
            if inertiaRight != 0 || inertiaUp != 0 {
                // Soft, like the gesture that launched it: coasting into the bounds should
                // rubber-band and spring back, not stop against a wall.
                model.truck(rightMeters: inertiaRight * dt, upMeters: inertiaUp * dt, soft: true)
            }
            applyNow()
            if !hasInertia {
                // Ran out of momentum: stop, then spring back from any rubber-band overshoot.
                stopInertia()
                onChange?()
                settle()
                return
            }
        }

        onChange?()
        if !isCameraMoving { stopMotionTicker() }
    }

    /// True while any axis still carries enough velocity to be worth drawing.
    private var hasInertia: Bool {
        abs(inertiaYaw) + abs(inertiaPitch) >= Self.orbitInertiaFloor
            || abs(inertiaRight) + abs(inertiaUp) >= Self.panInertiaFloor
    }

    private func stopInertia() {
        inertiaYaw = 0
        inertiaPitch = 0
        inertiaRight = 0
        inertiaUp = 0
        syncMotionState()
    }

    /// Is the camera moving right now, for any reason — a finger, coasting momentum, or an
    /// explicit spring still running? This is the ONLY question continuous rendering answers.
    private var isCameraMoving: Bool {
        gestureDepth > 0 || hasInertia || CACurrentMediaTime() < animationDeadline
    }

    /// Start or stop the ticker and the host's continuous rendering to match `isCameraMoving`.
    private func syncMotionState() {
        let moving = isCameraMoving
        if moving && displayLink == nil {
            lastTick = CACurrentMediaTime()
            let link = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.tickMotion() },
                                     selector: #selector(DisplayLinkProxy.tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !moving {
            stopMotionTicker()
        }
        continuousRenderingSink?(moving)
    }

    private func stopMotionTicker() {
        displayLink?.invalidate()
        displayLink = nil
        continuousRenderingSink?(isCameraMoving)
    }

    private func animate(to target: CameraRigModel, duration: TimeInterval) {
        stopInertia()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        model = target
        apply()
        SCNTransaction.commit()
        // An SCNTransaction animation interpolates the node, but on a static scene nothing
        // asks for the intermediate frames — the spring-back used to SNAP, one redraw at the
        // end. Hold the ticker open for the animation's duration so it is actually seen.
        animationDeadline = max(animationDeadline, CACurrentMediaTime() + duration)
        syncMotionState()
        onChange?()
    }

    // MARK: -

    /// World point the zoom should hold fixed: whatever geometry is under the touch, else the
    /// touch ray dropped onto the horizontal plane through the current pivot — so zooming over
    /// empty space still feels anchored at house height rather than snapping to the origin.
    private func anchor(at point: CGPoint, in view: SCNView) -> CameraRigModel.Vec3 {
        if let hit = view.hitTest(point, options: [.ignoreHiddenNodes: true]).first {
            let w = hit.worldCoordinates
            return CameraRigModel.Vec3(x: Double(w.x), y: Double(w.y), z: Double(w.z))
        }
        // Same near/far unproject-to-plane pattern as the editor's worldPoint(from:) — it is
        // projection-agnostic, only the target plane differs.
        let near = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
        let dy = Double(far.y - near.y)
        guard abs(dy) > 1e-9 else { return model.pivot }
        let t = (model.pivot.y - Double(near.y)) / dy
        guard t > 0 else { return model.pivot }
        return CameraRigModel.Vec3(x: Double(near.x) + t * Double(far.x - near.x),
                                   y: model.pivot.y,
                                   z: Double(near.z) + t * Double(far.z - near.z))
    }

    /// Write the model through to the node with no implicit animation.
    ///
    /// Every gesture-driven write goes through this rather than bare `apply()`. Without an
    /// explicit zero-duration transaction the write inherits whatever ambient `SCNTransaction`
    /// is open — SceneKit's default is a 0.25 s implicit animation — so a finger-tracking drag
    /// lands a frame or more late and the camera eases toward where the finger *was*.
    private func applyNow() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        apply()
        SCNTransaction.commit()
    }

    /// Write the model through to the node.
    private func apply() {
        // One transform write, not `position` + `look(at:)`.
        //
        // `look(at:)` is a second transform solve per frame, and — because it lands as a
        // separate property write — inside an animating transaction the position and the
        // orientation interpolate on their own curves. The camera then swims through an arc
        // between two poses instead of moving along the straight line the model describes.
        // Composing the basis here is both cheaper and exact.
        //
        // The basis is identical to what `look(at:)` produced with the default world up, so the
        // tour handoff in PlaybackCameraController still lines up: camera +Z is `toCamera`
        // (away from the pivot), +X is `model.right`, +Y is `model.up`. CameraRigModelTests
        // already pins that basis as orthonormal, non-rolling and up-positive; the pitch clamp
        // at 80° keeps it out of the gimbal case where world-up and +Z would be parallel.
        let p = model.position
        let back = model.toCamera
        let right = model.right
        let up = model.up
        node.simdTransform = simd_float4x4(
            SIMD4<Float>(Float(right.x), Float(right.y), Float(right.z), 0),
            SIMD4<Float>(Float(up.x), Float(up.y), Float(up.z), 0),
            SIMD4<Float>(Float(back.x), Float(back.y), Float(back.z), 0),
            SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
        )
        // Under an orthographic projection, moving the camera along its own axis changes nothing
        // on screen — `distance` only reads as zoom if it drives orthographicScale. Keeping the
        // rig's distance as the single source of truth is what lets the same pinch/framing math
        // serve both projections.
        if let camera = node.camera, camera.usesOrthographicProjection {
            var scale = CameraTuning.orthographicScale(forDistance: Float(model.distance))
            // orthographicScale is a HALF-HEIGHT. On a portrait viewport that means the visible
            // WIDTH is scale × aspect, which is much smaller — a house framed to fit vertically
            // gets sliced off at both sides. Widen the volume so the same distance frames the
            // same content in either orientation, which is also what keeps the ortho/perspective
            // toggle from jumping.
            if let bounds = attachedView?.bounds, bounds.width > 0, bounds.height > 0 {
                let aspect = Double(bounds.width / bounds.height)
                if aspect < 1 { scale /= aspect }
            }
            camera.orthographicScale = scale
        }
    }
}


/// CADisplayLink retains its target, so the rig can't be the target without leaking. This
/// forwards to a closure that holds the rig weakly.
private final class DisplayLinkProxy: NSObject {
    private let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func tick() { body() }
}
