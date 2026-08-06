//  CameraGestureDriver.swift
//
//  ONE camera-gesture implementation, shared by both 3D hosts.
//
//  There were two. `EditorSceneView` (HouseScreen) wired `beginOrbit`/`endOrbit(velocity:)`/
//  `settle()`; `UnifiedSceneView` (DrillScreen) wired none of them and never assigned
//  `rig.onChange` or `rig.continuousRenderingSink` — so on the drill surface there was no
//  inertia, no axis-lock reset, no rubber-band spring-back, and any frame the rig drove itself
//  would not have been drawn. Two divergent gesture models for the same house is a feel bug
//  that regrows every time either file is edited, so the arbitration, the lifecycle and the
//  release behaviour live here and both hosts call in.
//
//  What the hosts still own: WHICH gestures exist, and — for the editor — whether a one-finger
//  pan is an edit drag or a camera drag (`GestureArbiter`, decided at `.began` and latched).
//  Everything after that decision is this file's.

import Foundation

#if canImport(SceneKit) && canImport(UIKit)
import SceneKit
import UIKit

@MainActor
final class CameraGestureDriver {

    private let rig: OrbitCameraRig

    /// Fires with `true` when the first camera gesture begins and `false` when the last one
    /// ends. Hosts use it to hold off scene-affecting work until the finger is up (#5).
    var onPhaseChange: ((Bool) -> Void)?

    /// nil when no camera pan is in flight.
    private var arbiter: CameraRigModel.PanArbiter?
    private var pinchIsActive = false

    /// A finished pan's exit state, held until the LAST camera gesture ends.
    ///
    /// Pinch and pan recognize simultaneously, so a two-finger manipulation has both live at
    /// once. If the one that finishes first launched inertia or sprang back immediately, the
    /// camera would animate out from under the finger still on the glass.
    private struct PendingRelease {
        let intent: CameraRigModel.PanIntent
        let velocity: CGPoint
    }
    private var pendingRelease: PendingRelease?

    init(rig: OrbitCameraRig) {
        self.rig = rig
    }

    var isGestureInFlight: Bool { arbiter != nil || pinchIsActive }

    // MARK: - Pan

    /// Drive the camera from a pan the host has already decided is NOT an edit drag.
    ///
    /// Orbit vs truck is decided here, from live touch count, by `PanArbiter` — not by the
    /// caller and not latched at `.began`.
    func handlePan(_ g: UIPanGestureRecognizer, in view: SCNView) {
        if g.state == .began {
            arbiter = CameraRigModel.PanArbiter(touchCount: g.numberOfTouches)
            rig.beginCameraGesture()
            // Resets the axis-lock sampler and kills leftover inertia, so a new touch takes
            // control on the frame it lands.
            rig.beginOrbit()
            onPhaseChange?(true)
        }
        guard arbiter != nil else { return }
        // Re-read every event: a second finger arriving mid-drag must suppress orbit NOW, not
        // at the start of the next gesture.
        arbiter?.update(touchCount: g.numberOfTouches)
        guard let intent = arbiter?.intent else { return }

        let delta = g.translation(in: view)
        g.setTranslation(.zero, in: view)

        switch g.state {
        case .began, .changed:
            switch intent {
            case .orbit: rig.orbit(byScreenDelta: delta, in: view)
            case .truck: rig.truck(byScreenDelta: delta, in: view)
            }
        case .ended, .cancelled, .failed:
            // A cancelled gesture has no meaningful exit velocity — coasting off one is how a
            // camera runs away when a system gesture interrupts a drag.
            let velocity = g.state == .ended ? g.velocity(in: view) : .zero
            pendingRelease = PendingRelease(intent: intent, velocity: velocity)
            arbiter = nil
            rig.endCameraGesture()
            releaseIfIdle(in: view)
        default:
            break
        }
        // Continuous rendering is on for the whole gesture, so this is belt-and-braces — it
        // costs nothing and keeps the surface correct for any host that has not wired the
        // rig's `continuousRenderingSink`.
        view.setNeedsDisplay()
    }

    /// The host decided this pan is an edit drag after all. Give up the camera cleanly.
    func abandonPan() {
        guard arbiter != nil else { return }
        arbiter = nil
        rig.endCameraGesture()
        onPhaseChange?(isGestureInFlight)
    }

    // MARK: - Pinch

    func handlePinch(_ g: UIPinchGestureRecognizer, in view: SCNView) {
        switch g.state {
        case .began:
            pinchIsActive = true
            rig.beginCameraGesture()
            // Resolve the zoom anchor ONCE, here. See OrbitCameraRig.beginPinch.
            rig.beginPinch(at: g.location(in: view), in: view)
            g.scale = 1
            onPhaseChange?(true)
        case .changed:
            guard pinchIsActive else { return }
            rig.pinch(scale: g.scale, centroid: g.location(in: view), in: view)
            g.scale = 1
        case .ended, .cancelled, .failed:
            guard pinchIsActive else { return }
            pinchIsActive = false
            rig.pinch(scale: g.scale, centroid: g.location(in: view), in: view)
            g.scale = 1
            rig.endPinch()
            rig.endCameraGesture()
            releaseIfIdle(in: view)
        default:
            break
        }
        // Continuous rendering is on for the whole gesture, so this is belt-and-braces — it
        // costs nothing and keeps the surface correct for any host that has not wired the
        // rig's `continuousRenderingSink`.
        view.setNeedsDisplay()
    }

    // MARK: - Double tap

    func handleDoubleTap(at point: CGPoint, in view: SCNView, home: HomeModel) {
        rig.doubleTap(at: point, in: view, home: home)
    }

    // MARK: -

    /// Apply the release behaviour once — and only once — the last finger is up.
    private func releaseIfIdle(in view: SCNView) {
        guard !isGestureInFlight else { return }
        if let release = pendingRelease {
            pendingRelease = nil
            // Both paths end by settling: `endOrbit`/`endTruck` either launch inertia (which
            // settles when it runs out) or settle immediately. Every gesture-end path springs
            // back, which is the invariant the rubber band depends on.
            switch release.intent {
            case .orbit: rig.endOrbit(velocity: release.velocity, in: view)
            case .truck: rig.endTruck(velocity: release.velocity, in: view)
            }
        } else {
            rig.settle()
        }
        onPhaseChange?(false)
    }
}

#endif
