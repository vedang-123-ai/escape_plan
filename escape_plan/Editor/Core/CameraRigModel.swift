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

    var pitchRange: ClosedRange<Double> = (5 * .pi / 180)...(85 * .pi / 180)
    var distanceRange: ClosedRange<Double> = 0.5...200

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
    mutating func truck(rightMeters: Double, upMeters: Double) {
        pivot = pivot + right * rightMeters + up * upMeters
    }

    /// Zoom by `scale` (>1 zooms in) keeping `anchor` fixed on screen: the distance shrinks by
    /// the scale and the pivot slides toward the anchor by the same proportion, so the point
    /// under the user's fingers stays under their fingers.
    mutating func zoom(scale: Double, towardAnchor anchor: Vec3) {
        guard scale > 1e-9 else { return }
        let target = distance / scale
        let clamped = min(max(target, distanceRange.lowerBound), distanceRange.upperBound)
        // If the distance clamp bites, shrink the pivot slide to match — otherwise the pivot
        // keeps drifting into the anchor while the view no longer zooms.
        let effectiveScale = distance / clamped
        distance = clamped
        pivot = anchor + (pivot - anchor) * (1 / effectiveScale)
    }

    /// Zoom about the pivot itself (no anchor — e.g. keyboard/slider zoom).
    mutating func zoom(scale: Double) {
        zoom(scale: scale, towardAnchor: pivot)
    }

    /// Meters spanned by one screen point at the pivot's depth, for converting pan gestures.
    /// `fovDegrees` is the camera's vertical field of view, `viewHeightPoints` the view height.
    func metersPerPoint(fovDegrees: Double, viewHeightPoints: Double) -> Double {
        guard viewHeightPoints > 0 else { return 0.01 }
        let worldHeight = 2 * distance * tan(fovDegrees * .pi / 180 / 2)
        return worldHeight / viewHeightPoints
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
            pitch: 35 * .pi / 180,
            distance: safeExtent * 1.9
        )
        rig.distanceRange = 0.5...(safeExtent * 20)
        return rig
    }
}
