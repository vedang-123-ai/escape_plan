//  SceneKitEditorBridge.swift — the ONLY device-coupled file in the editor.
//
//  ============================ TODO(integration) — READ FIRST ============================
//  S1.3 (the SceneKit renderer, owner P2) was built in a parallel lane and is NOT on this
//  branch. This file therefore has no renderer to talk to yet, and is written against an
//  explicit seam — the `EditorSceneAdapter` protocol below — rather than against S1.3's node
//  graph, which nobody here has seen.
//
//  On merge, S1.3's renderer conforms to `EditorSceneAdapter` and everything else here works
//  unchanged. There are exactly three things to wire:
//
//    1. `worldPoint(from:)`  — unproject a screen touch onto the active floor's plane.
//       S1.3 owns the camera, so S1.3 owns this. Everything below is in floor-local meters
//       and does not care how the projection happens.
//    2. `metersPerPoint()`   — how many meters one screen point covers at the current zoom.
//       Drives touch tolerances; a fixed meter tolerance would be unusable at either extreme.
//    3. `highlight(_:)`      — draw the selection (handles on a selected room, etc).
//
//  Everything ELSE about editing — what a tap selects, what a drag does, whether a mutation is
//  legal — is already done, in `Editor/Core/`, and is unit-tested without a device. That split
//  is deliberate: the untestable part of this session is this file and nothing else.
//  ========================================================================================
//
//  Deferred to an on-device session (also blocked on S1.3, per the S2.1 handoff):
//    - the "build the bungalow by hand in < 5 minutes" acceptance run and its recording
//    - haptics tuning (the rejection buzz is wired below but has never been felt)

import Foundation

#if canImport(SceneKit) && canImport(UIKit)
import SceneKit
import UIKit

// MARK: - The seam

/// What the editor needs from the renderer. S1.3 conforms to this on merge.
///
/// It is intentionally tiny: three calls, none of which leak SceneKit types into the editor
/// core. If this protocol grows past a handful of methods, the split has gone wrong.
@MainActor
protocol EditorSceneAdapter: AnyObject {
    /// Unprojects a touch onto the active floor's ground plane. Returns nil when the ray misses
    /// (e.g. the user tapped the sky). Result is in floor-local meters — the schema's frame.
    func worldPoint(from screenPoint: CGPoint) -> Point?

    /// Meters covered by one screen point at the current camera zoom.
    func metersPerPoint() -> Double

    /// Draw the current selection. `.none` means clear it.
    func highlight(_ selection: Selection)
}

// MARK: - Gesture driver

/// Turns raw gestures into `EditAction`s. Holds no model state of its own — the store is the
/// only source of truth (rules/languages/swift.md), and this class is a translator, not an
/// editor.
@MainActor
final class SceneKitEditorBridge {

    private let store: HomeModelStore
    private weak var scene: EditorSceneAdapter?

    /// A touch target of ~44pt is the platform minimum; corners get a little more because they
    /// are the smallest thing on screen and the most precise thing to grab.
    var vertexHandlePoints: Double = 22
    var wallHandlePoints: Double = 14

    /// Set to false in tests / previews. Haptics are the "no gesture puts the model in an
    /// invalid state" feedback the playbook asks for — a rejected drag must FEEL rejected.
    var hapticsEnabled = true

    /// Where the in-progress drag started, in floor-local meters, plus what it grabbed.
    private var dragOrigin: Point?
    private var dragSubject: Selection = .none
    /// The last point actually committed, so each gesture update sends a delta rather than an
    /// absolute — the store's edge/room drags are translations.
    private var lastDragPoint: Point?

    init(store: HomeModelStore, scene: EditorSceneAdapter?) {
        self.store = store
        self.scene = scene
    }

    func attach(scene: EditorSceneAdapter) {
        self.scene = scene
    }

    // MARK: Tap

    /// TODO(integration): call from a UITapGestureRecognizer on S1.3's SCNView.
    func handleTap(at screenPoint: CGPoint) {
        guard let scene, let world = scene.worldPoint(from: screenPoint) else { return }

        let selection = HitTesting.hitTest(world, floor: store.activeFloor,
                                           tolerances: tolerances())
        store.select(selection)
        scene.highlight(selection)
        if selection != .none { play(.selection) }
    }

    // MARK: Drag

    /// TODO(integration): call from a UIPanGestureRecognizer on S1.3's SCNView.
    ///
    /// One gesture = many dispatches. That is fine for the model (each is validated) but S2.2
    /// must coalesce them into ONE undo entry — see `EditAction.isContinuousDrag`.
    func handleDrag(_ state: UIGestureRecognizer.State, at screenPoint: CGPoint) {
        guard let scene, let world = scene.worldPoint(from: screenPoint) else { return }

        switch state {
        case .began:
            // Grab whatever is under the finger; if it's nothing, this pan belongs to the
            // camera, not the editor.
            let subject = HitTesting.hitTest(world, floor: store.activeFloor,
                                             tolerances: tolerances())
            guard subject != .none else { return }
            dragSubject = subject
            dragOrigin = world
            lastDragPoint = world
            store.select(subject)
            scene.highlight(subject)

        case .changed:
            guard let last = lastDragPoint else { return }
            let delta = Geometry.subtract(world, last)
            guard let action = action(for: dragSubject, target: world, delta: delta) else { return }

            switch store.dispatch(action) {
            case .applied:
                // Advance from where the drag actually is, not where the snapper put the
                // geometry — otherwise the shape creeps every time a snap fires.
                lastDragPoint = world
            case .rejected:
                // Hold `lastDragPoint` so the delta accumulates: the user can keep dragging
                // back out of an illegal position and the shape recovers instead of sticking.
                play(.rejected)
            }

        case .ended, .cancelled, .failed:
            dragSubject = .none
            dragOrigin = nil
            lastDragPoint = nil

        default:
            break
        }
    }

    private func action(for subject: Selection, target: Point, delta: Point) -> EditAction? {
        switch subject {
        case .vertex(let roomId, let index):
            // Corners are absolute: the vertex goes where the finger is (then snaps).
            return .dragVertex(roomId: roomId, vertexIndex: index, to: target)
        case .wall(let roomId, let edgeIndex):
            return .dragEdge(roomId: roomId, edgeIndex: edgeIndex, by: delta)
        case .room(let roomId):
            return .dragRoom(roomId: roomId, by: delta)
        case .opening:
            // Sliding an opening along its wall is S2.2 (the t-parameter drag).
            return nil
        case .none:
            return nil
        }
    }

    // MARK: Tolerances

    /// Converts the point-sized touch targets into the meter-sized tolerances the pure core
    /// works in, using the live zoom.
    private func tolerances() -> HitTesting.Tolerances {
        let mpp = scene?.metersPerPoint() ?? 0.01
        return HitTesting.Tolerances(vertexRadiusM: vertexHandlePoints * mpp,
                                     wallRadiusM: wallHandlePoints * mpp)
    }

    // MARK: Haptics

    private enum Feedback { case selection, rejected }

    private func play(_ feedback: Feedback) {
        guard hapticsEnabled else { return }
        switch feedback {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .rejected:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

#endif
