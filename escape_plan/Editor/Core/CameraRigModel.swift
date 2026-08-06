//  CameraRigModel.swift — pure orbit-camera state for the unified 3D view.
//
//  No SceneKit, no UIKit: the rig is yaw/pitch/distance around a movable pivot, with pure
//  transitions for orbit, truck (pan), and zoom-toward-a-point. `OrbitCameraRig` (Renderer/)
//  binds this to an SCNNode; keeping the math here means the interaction model is testable
//  in the fast editorcore package without a renderer.
//
//  Frame: scene space, +y up. Yaw is measured in the XZ plane, pitch is elevation above the
//  horizontal. The camera sits at `position` looking at `pivot`.

import Foundation

struct CameraRigModel: Equatable {

    /// Minimal 3D vector so the core stays SceneKit-free.
    struct Vec3: Equatable {
        var x: Double
        var y: Double
        var z: Double

        static let zero = Vec3(x: 0, y: 0, z: 0)

        static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func * (a: Vec3, k: Double) -> Vec3 { Vec3(x: a.x * k, y: a.y * k, z: a.z * k) }

        var length: Double { (x * x + y * y + z * z).squareRoot() }

        func normalized() -> Vec3 {
            let l = length
            guard l > 1e-12 else { return .zero }
            return self * (1 / l)
        }

        static func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
            Vec3(x: a.y * b.z - a.z * b.y,
                 y: a.z * b.x - a.x * b.z,
                 z: a.x * b.y - a.y * b.x)
        }
    }

    /// The point the camera orbits and looks at.
    var pivot: Vec3
    /// Rotation about +y in the XZ plane, radians. 0 looks down −z... any value is valid; it wraps.
    var yaw: Double
    /// Elevation above horizontal, radians. Clamped: near-zero pitch puts the camera inside the
    /// walls it is supposed to look through; near-vertical makes yaw degenerate (gimbal).
    var pitch: Double
    /// Camera-to-pivot distance, meters. Clamped so zooming can neither cross the pivot nor
    /// leave the house a speck.
    var distance: Double

    /// 12° rather than 5°: now that the walls are opaque, a very low camera skims *inside* them
    /// and the view fills with wall interior. 80° rather than 85° keeps yaw from going
    /// degenerate at the top.
    var pitchRange: ClosedRange<Double> = (12 * .pi / 180)...(80 * .pi / 180)
    var distanceRange: ClosedRange<Double> = 0.5...200

    /// Region the pivot is allowed to occupy — the house bounds plus an apron. Without this,
    /// panning is unbounded and the house can be pushed off screen with no way back, which was
    /// the single most-reported "I lost the house" bug. `nil` disables clamping.
    var pivotBounds: Bounds?

    /// An axis-aligned box in world space.
    struct Bounds: Equatable {
        var minX: Double, maxX: Double
        var minY: Double, maxY: Double
        var minZ: Double, maxZ: Double

        init(minX: Double, maxX: Double, minY: Double, maxY: Double, minZ: Double, maxZ: Double) {
            self.minX = min(minX, maxX); self.maxX = max(minX, maxX)
            self.minY = min(minY, maxY); self.maxY = max(minY, maxY)
            self.minZ = min(minZ, maxZ); self.maxZ = max(minZ, maxZ)
        }
    }

    init(pivot: Vec3, yaw: Double, pitch: Double, distance: Double) {
        self.pivot = pivot
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
        clamp()
    }

    // MARK: - Derived frame

    /// Unit vector from pivot toward the camera.
    var toCamera: Vec3 {
        Vec3(x: cos(pitch) * sin(yaw),
             y: sin(pitch),
             z: cos(pitch) * cos(yaw))
    }

    var position: Vec3 { pivot + toCamera * distance }

    /// Camera-right in world space (horizontal — orbit cameras don't roll).
    var right: Vec3 {
        // forward = -toCamera; right = forward × up, with world up (0,1,0).
        Vec3.cross(toCamera * -1, Vec3(x: 0, y: 1, z: 0)).normalized()
    }

    /// Camera-up in world space.
    var up: Vec3 {
        Vec3.cross(right, toCamera * -1).normalized()
    }

    // MARK: - Transitions

    mutating func orbit(deltaYaw: Double, deltaPitch: Double) {
        yaw += deltaYaw
        pitch += deltaPitch
        clamp()
    }

    /// Pan: slide the pivot in the camera's right/up plane. Deltas in meters at pivot depth.
    ///
    /// `soft` is what a gesture in progress passes: motion past the bounds is allowed but
    /// resisted, so the pan feels elastic at the edge instead of hitting a wall. On release the
    /// caller springs to `settled()`.
    mutating func truck(rightMeters: Double, upMeters: Double, soft: Bool = false) {
        pivot = pivot + right * rightMeters + up * upMeters
        clampPivot(soft: soft)
    }

    /// Pull the pivot back inside `pivotBounds`. Beyond the edge, `soft` keeps only a quarter of
    /// the overshoot — the standard rubber-band feel.
    mutating func clampPivot(soft: Bool = false) {
        guard let b = pivotBounds else { return }
        let limit: (Double, Double, Double) -> Double = soft
            ? { v, lo, hi in v < lo ? lo + (v - lo) * 0.25 : (v > hi ? hi + (v - hi) * 0.25 : v) }
            : { v, lo, hi in min(max(v, lo), hi) }
        pivot = Vec3(x: limit(pivot.x, b.minX, b.maxX),
                     y: limit(pivot.y, b.minY, b.maxY),
                     z: limit(pivot.z, b.minZ, b.maxZ))
    }

    /// Where a soft-clamped rig should spring back to when the gesture ends: everything hard
    /// clamped into range.
    func settled() -> CameraRigModel {
        var copy = self
        copy.clampPivot(soft: false)
        copy.distance = min(max(distance, distanceRange.lowerBound), distanceRange.upperBound)
        copy.pitch = min(max(pitch, pitchRange.lowerBound), pitchRange.upperBound)
        return copy
    }

    /// Decide whether a drag should be a pure turntable (yaw only) or free yaw+pitch, from the
    /// first few points of travel.
    ///
    /// A single pan gesture driving both axes means a mostly-horizontal swipe still picks up a
    /// few degrees of pitch wobble, which is what made orbiting feel unsteady. Locking to yaw
    /// once the gesture is clearly horizontal gives a clean turntable and still allows tilting
    /// when the user actually means to.
    static func shouldLockToYaw(dx: Double, dy: Double,
                                sampleThreshold: Double = axisLockSampleThreshold) -> Bool {
        guard abs(dx) + abs(dy) >= sampleThreshold else { return false }
        return abs(dx) > 2 * abs(dy)
    }

    /// What a pan gesture drives.
    enum PanIntent: Equatable { case orbit, truck }

    /// The one rule for orbit-vs-pan arbitration, as a state machine.
    ///
    /// Both gesture hosts latched `numberOfTouches >= 2` at `.began` only, while pinch and pan
    /// were allowed to recognize simultaneously. Start with one finger, add a second, and the
    /// pan kept ORBITING at the two-finger centroid velocity while the pinch drove zoom — the
    /// camera fought itself. The rule is now explicit and lives in exactly one place:
    ///
    /// **Two-finger input is pan and zoom. It never orbits.**
    ///
    /// Suppression latches: once a second finger has touched down, lifting back to one finger
    /// does NOT resume orbiting. Handing the gesture back to a different transition halfway
    /// through is the same self-fighting bug in a slower costume.
    struct PanArbiter: Equatable {
        private(set) var intent: PanIntent = .orbit
        /// True once a second finger has been seen at any point in this gesture.
        private(set) var orbitSuppressed = false

        init(touchCount: Int) {
            update(touchCount: touchCount)
        }

        mutating func update(touchCount: Int) {
            if touchCount >= 2 { orbitSuppressed = true }
            intent = orbitSuppressed ? .truck : .orbit
        }
    }

    /// Zoom by `scale` (>1 zooms in) keeping `anchor` fixed on screen: the distance shrinks by
    /// the scale and the pivot slides toward the anchor by the same proportion, so the point
    /// under the user's fingers stays under their fingers.
    mutating func zoom(scale: Double, towardAnchor anchor: Vec3, soft: Bool = false) {
        guard scale > 1e-9 else { return }
        let target = distance / scale
        let lo = distanceRange.lowerBound, hi = distanceRange.upperBound
        let clamped = soft
            ? (target < lo ? lo + (target - lo) * 0.25
                           : (target > hi ? hi + (target - hi) * 0.25 : target))
            : min(max(target, lo), hi)
        // If the distance clamp bites, shrink the pivot slide to match — otherwise the pivot
        // keeps drifting into the anchor while the view no longer zooms.
        let effectiveScale = distance / clamped
        distance = clamped
        pivot = anchor + (pivot - anchor) * (1 / effectiveScale)
        clampPivot(soft: soft)
    }

    /// Zoom about the pivot itself (no anchor — e.g. keyboard/slider zoom).
    mutating func zoom(scale: Double) {
        zoom(scale: scale, towardAnchor: pivot)
    }

    /// How the camera projects, for screen→world conversion.
    ///
    /// This is an enum rather than two loose parameters because getting it wrong is silent: a
    /// pan converted with perspective math under an orthographic camera still moves the house,
    /// just at a constant wrong ratio, so it reads as "panning feels floaty" rather than as a
    /// bug. Making the call site name its projection means it cannot be defaulted past.
    enum Projection: Equatable {
        /// Vertical field of view, degrees.
        case perspective(fovDegrees: Double)
        /// `SCNCamera.orthographicScale` — a HALF-height in world meters, and already
        /// aspect-corrected by whoever wrote it to the camera.
        case orthographic(halfHeight: Double)
    }

    /// Meters spanned by one screen point at the pivot's depth, for converting pan gestures.
    ///
    /// Under perspective the visible height depends on distance and FOV. Under orthographic it
    /// depends on neither — it is exactly `2 · orthographicScale`, which is why the FOV form
    /// gives an answer that is wrong by a constant factor when applied to an ortho camera.
    func metersPerPoint(projection: Projection, viewHeightPoints: Double) -> Double {
        guard viewHeightPoints > 0 else { return 0.01 }
        switch projection {
        case .perspective(let fovDegrees):
            return 2 * distance * tan(fovDegrees * .pi / 180 / 2) / viewHeightPoints
        case .orthographic(let halfHeight):
            return 2 * max(halfHeight, 1e-6) / viewHeightPoints
        }
    }

    /// Perspective-only convenience, kept because the framing math and its tests speak in FOV.
    func metersPerPoint(fovDegrees: Double, viewHeightPoints: Double) -> Double {
        metersPerPoint(projection: .perspective(fovDegrees: fovDegrees),
                       viewHeightPoints: viewHeightPoints)
    }

    private mutating func clamp() {
        pitch = min(max(pitch, pitchRange.lowerBound), pitchRange.upperBound)
        distance = min(max(distance, distanceRange.lowerBound), distanceRange.upperBound)
    }

    // MARK: - Framing

    /// Opening shot for a home: the same three-quarter dollhouse view the builder's static
    /// camera used — pivot at a third of the house height, backed off by the plan extent.
    static func framing(center: Vec3, extent: Double, totalHeight: Double) -> CameraRigModel {
        let safeExtent = max(extent, 1.0)
        var rig = CameraRigModel(
            pivot: Vec3(x: center.x, y: totalHeight * 0.35, z: center.z),
            yaw: .pi * 0.2,
            pitch: 38 * .pi / 180,
            distance: safeExtent * openingDistanceFactor
        )
        // Tied to the model's own size instead of the old absolute 0.5…extent×20, which let the
        // user zoom until the house was a speck or until the near plane was inside a wall.
        //
        // The floor was 0.8 × extent, which is barely closer than the 2.2 × opening shot and
        // stopped the user well short of inspecting a single room — the limit bit long before
        // it needed to. 0.35 still keeps the near plane clear of a wall on a house-sized model.
        rig.distanceRange = (safeExtent * minimumDistanceFactor)...(safeExtent * 4.0)
        // Pan is bounded to the house plus an apron, vertically to the stack.
        //
        // The apron was a quarter of the extent, so the rubber band engaged almost as soon as
        // the pan started and the whole gesture read as "I can't move the house". The clamp
        // still exists — losing the house entirely with no way back was a real bug — it just
        // gives meaningfully more room before it does.
        let apron = safeExtent * panApronFactor
        rig.pivotBounds = Bounds(minX: center.x - apron, maxX: center.x + apron,
                                 minY: 0, maxY: max(totalHeight, 1.0),
                                 minZ: center.z - apron, maxZ: center.z + apron)
        rig.clampPivot()
        return rig
    }

    /// How far back the opening shot and the recenter chip sit, as a multiple of the plan extent.
    ///
    /// Derived, not guessed: the old framing was 1.9 × extent at a 50° field of view. The White
    /// Model overhaul drops to a 35° long lens to kill wide-angle distortion, which narrows the
    /// visible span by tan(25°)/tan(17.5°) ≈ 1.48× — so the camera has to back off by the same
    /// factor to frame the same house. A further margin covers the diagonal, since at a 45° yaw
    /// the model presents √2 × its extent across the frame.
    static let openingDistanceFactor = 2.2

    /// Closest the camera may get, as a multiple of the plan extent. Sized so a single room
    /// can be inspected; the hard clamp that keeps the near plane out of a wall stays.
    static let minimumDistanceFactor = 0.35

    /// How far past the house the pivot may travel, as a multiple of the plan extent.
    static let panApronFactor = 0.6

    /// Points of travel before the orbit axis lock commits.
    ///
    /// 12 pt was inside the noise of a flick: a short drag committed to an axis from a sample
    /// that had barely started, so small gestures picked up pitch wobble. 20 pt is still well
    /// under a deliberate drag and gives the direction test something to read.
    static let axisLockSampleThreshold: Double = 20

    /// The shot the recenter chip springs to: framed on `center`, backed off by the opening
    /// distance, tilted to 38°, and yawed to the nearest 45° diagonal so the house sits
    /// square-ish in frame.
    func recentered(on center: Vec3, extent: Double) -> CameraRigModel {
        let safeExtent = max(extent, 1.0)
        var copy = self
        copy.pivot = center
        copy.pitch = 38 * .pi / 180
        copy.distance = safeExtent * CameraRigModel.openingDistanceFactor
        let step = Double.pi / 4
        copy.yaw = (yaw / step).rounded() * step
        copy.clampPivot()
        return copy
    }
}
