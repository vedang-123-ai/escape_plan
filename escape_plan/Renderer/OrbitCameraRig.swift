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
    private var lastOrbitRate: (yaw: Double, pitch: Double) = (0, 0)
    /// Accumulated travel of the current gesture, used to pick the orbit axis once.
    private var gestureTravel: CGPoint = .zero
    /// nil = undecided, true = turntable (yaw only), false = free orbit.
    private var axisLock: Bool?

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
        apply()
    }

    deinit { displayLink?.invalidate() }

    /// Re-parents the rig's camera into a (re)built scene and makes it the point of view.
    /// Safe to call repeatedly; the model — and therefore the view the user sees — is untouched.
    func attach(to scene: SCNScene, view: SCNView) {
        node.removeFromParentNode()
        scene.rootNode.addChildNode(node)
        view.pointOfView = node
        attachedView = view
        apply()
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
        apply()
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
        apply()
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
        let fov = CameraTuning.fieldOfViewDegrees
        let mpp = model.metersPerPoint(fovDegrees: fov,
                                       viewHeightPoints: Double(view.bounds.height))
        model.truck(rightMeters: -Double(delta.x) * mpp, upMeters: Double(delta.y) * mpp,
                    soft: soft)
        apply()
    }

    /// `scale` is the incremental pinch scale since the last call (caller resets the
    /// recognizer's scale to 1 each time). The world point under the pinch stays put.
    func pinch(scale: CGFloat, centroid: CGPoint, in view: SCNView, soft: Bool = true) {
        model.zoom(scale: Double(scale), towardAnchor: anchor(at: centroid, in: view), soft: soft)
        apply()
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

    // MARK: - Inertia & animation

    private func startInertia(yawRate: Double, pitchRate: Double) {
        inertiaYaw = yawRate
        inertiaPitch = pitchRate
        lastTick = CACurrentMediaTime()
        let link = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.tickInertia() },
                                 selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        continuousRenderingSink?(true)
    }

    private func tickInertia() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 1.0 / 20)
        lastTick = now
        // Exponential decay with a ~0.25 s half-life.
        let decay = pow(0.5, dt / 0.25)
        inertiaYaw *= decay
        inertiaPitch *= decay
        model.orbit(deltaYaw: inertiaYaw * dt, deltaPitch: inertiaPitch * dt)
        apply()
        onChange?()
        if abs(inertiaYaw) + abs(inertiaPitch) < 0.02 {
            stopInertia()
            settle()
        }
    }

    private func stopInertia() {
        displayLink?.invalidate()
        displayLink = nil
        inertiaYaw = 0
        inertiaPitch = 0
        // Continuous rendering is a battery cost; it stays on only while something is moving.
        continuousRenderingSink?(false)
    }

    private func animate(to target: CameraRigModel, duration: TimeInterval) {
        stopInertia()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        model = target
        apply()
        SCNTransaction.commit()
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

    /// Write the model through to the node.
    private func apply() {
        let p = model.position
        node.position = SCNVector3(Float(p.x), Float(p.y), Float(p.z))
        node.look(at: SCNVector3(Float(model.pivot.x), Float(model.pivot.y), Float(model.pivot.z)))
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
