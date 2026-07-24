//  SceneKitEditorBridge.swift — the ONLY device-coupled file in the editor.
//
//  Turns raw gestures into `EditAction`s against the `EditorSceneAdapter` seam below.
//  `EditorSceneController` is the conformer (it owns the camera and the unprojection);
//  `EditorSceneView` owns the gesture recognizers and routes them here. Everything else about
//  editing — what a tap selects, what a drag does, whether a mutation is legal — lives in
//  `Editor/Core/` and is unit-tested without a device; this file stays a thin translator.
//
//  Still open (device-only): haptics tuning — the rejection buzz is wired below but has only
//  been exercised on the simulator, where haptics don't fire.

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
    private let undoStack: UndoStack?

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

    init(store: HomeModelStore, scene: EditorSceneAdapter?, undoStack: UndoStack? = nil) {
        self.store = store
        self.scene = scene
        self.undoStack = undoStack
    }

    func attach(scene: EditorSceneAdapter) {
        self.scene = scene
    }

    // MARK: Arbitration

    /// Decides at `.began` whether a one-finger pan is an edit-drag or belongs to the camera.
    /// The caller latches the answer for the whole gesture (`GestureArbiter` doc).
    func dragIntent(at screenPoint: CGPoint) -> GestureArbiter.DragIntent {
        guard let scene, let world = scene.worldPoint(from: screenPoint) else { return .camera }
        let hit = HitTesting.hitTest(world, floor: store.activeFloor, tolerances: tolerances())
        return GestureArbiter.intent(hit: hit, current: store.selection)
    }

    /// Compact dump of the active floor's polygons for UI-automation debugging.
    func debugPolygons() -> String {
        store.activeFloor.rooms.map { room in
            let pts = room.polygon.map { String(format: "%.2f,%.2f", $0.x, $0.y) }
                .joined(separator: " ")
            return "\(room.name)[\(pts)]"
        }.joined(separator: " | ")
    }

    /// Compact diagnostic for UI-automation debugging (read back via accessibilityValue).
    func debugProbe(at screenPoint: CGPoint) -> String {
        guard let scene else { return "noscene" }
        guard let world = scene.worldPoint(from: screenPoint) else { return "noworld" }
        let t = tolerances()
        let hit = HitTesting.hitTest(world, floor: store.activeFloor, tolerances: t)
        return String(format: "w=%.2f,%.2f tol=%.2f hit=%@ sel=%@", world.x, world.y,
                      t.vertexRadiusM, "\(hit)", "\(store.selection)")
    }

    // MARK: Tap

    func handleTap(at screenPoint: CGPoint) {
        guard let scene, let world = scene.worldPoint(from: screenPoint) else { return }

        let selection = HitTesting.hitTest(world, floor: store.activeFloor,
                                           tolerances: tolerances())
        store.select(selection)
        scene.highlight(selection)
        if selection != .none { play(.selection) }
    }

    // MARK: Placement

    /// The Add Door / Add Window tap: resolves the touch to a parametric wall position and
    /// dispatches `addOpening` (adjacency decides interior vs. EXTERIOR — see
    /// `OpeningPlacement`). Returns whether an opening was actually added, so the caller can
    /// disarm its one-shot placement tool. The new opening is selected on success; a miss or
    /// a rejected placement (overlap, too-short wall) buzzes.
    @discardableResult
    func handlePlacementTap(at screenPoint: CGPoint, kind: OpeningKind) -> Bool {
        guard let scene, let world = scene.worldPoint(from: screenPoint) else { return false }
        guard let hit = HitTesting.wallPoint(world, floor: store.activeFloor,
                                             within: tolerances().wallRadiusM) else {
            play(.rejected)
            return false
        }
        switch store.dispatch(.addOpening(roomId: hit.roomId, edgeIndex: hit.edgeIndex,
                                          t: hit.t, kind: kind)) {
        case .applied:
            // The reducer appends to the active floor, so the new opening is `last`.
            if let placed = store.activeFloor.openings.last {
                let selection = Selection.opening(openingId: placed.id)
                store.select(selection)
                scene.highlight(selection)
            }
            play(.selection)
            return true
        case .rejected:
            play(.rejected)
            return false
        }
    }

    // MARK: Drag

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
            undoStack?.beginCoalescing(snapshot: store.model)

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
            undoStack?.endCoalescing()

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
            // Walls slide along their own normal; the along-edge component of the finger's
            // delta would skew the room, which no wall drag ever means.
            if let room = store.activeFloor.room(roomId),
               let edge = Geometry.edge(room.polygon, edgeIndex) {
                return .dragEdge(roomId: roomId, edgeIndex: edgeIndex,
                                 by: Geometry.projectOntoEdgeNormal(delta, edgeFrom: edge.a, to: edge.b))
            }
            return .dragEdge(roomId: roomId, edgeIndex: edgeIndex, by: delta)
        case .room(let roomId):
            return .dragRoom(roomId: roomId, by: delta)
        case .opening(let openingId):
            // Parametric: project the raw touch onto the opening's own host wall to get a new
            // midpoint-t, rather than the vertex/room delta machinery (which works in absolute/
            // delta meters, not wall-normalized units).
            guard let opening = store.activeFloor.openings.first(where: { $0.id == openingId }),
                  let host = store.activeFloor.room(opening.wall_segment.room_id),
                  let edge = Geometry.edge(host.polygon, opening.wall_segment.edge_index) else {
                return nil
            }
            let (_, t) = Geometry.closestPointOnSegment(target, edge.a, edge.b)
            return .dragOpening(openingId: openingId, t: t)
        case .stairs:
            // Stairs aren't drag-manipulated (placed/deleted only) — nothing to do here.
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
