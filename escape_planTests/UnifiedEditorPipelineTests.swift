//  UnifiedEditorPipelineTests.swift — the unified editor's screen→model pipeline, end to end
//  minus the gesture recognizers: SCNView projection → UnifiedSceneController.worldPoint →
//  GestureArbiter → SceneKitEditorBridge → HomeModelStore. Mirrors the manual-build recording
//  driver's join step (two rooms, drag a corner onto the neighbor) so a regression here is
//  caught in the fast suite instead of a 2-minute env-gated UI run.

import SceneKit
import XCTest
@testable import escape_plan

@MainActor
final class UnifiedEditorPipelineTests: XCTestCase {

    private func makeTwoRoomHome() -> HomeModel {
        HomeModel(
            schema_version: HomeModel.currentSchemaVersion,
            home_id: "pipeline-test",
            name: "Pipeline",
            floors: [
                Floor(id: "f0", level: 0, name: "Ground", height_m: 2.7,
                      rooms: [
                        Room(id: "r1", name: "Room 1", type: .other,
                             polygon: [Point(0, 0), Point(3, 0), Point(3, 3), Point(0, 3)],
                             source: .manual, confidence: nil),
                        Room(id: "r2", name: "Room 2", type: .other,
                             polygon: [Point(3.5, 0), Point(6.5, 0), Point(6.5, 3), Point(3.5, 3)],
                             source: .manual, confidence: nil),
                      ],
                      openings: [])
            ],
            stairs: [],
            meta: Meta(created: .distantPast, modified: .distantPast)
        )
    }

    /// Screen point for a plan point via the live camera — the inverse of what
    /// `worldPoint(from:)` does, so the two must round-trip.
    private func screen(_ x: Double, _ y: Double, view: SCNView) -> CGPoint {
        let p = view.projectPoint(SCNVector3(Float(x), 0, Float(-y)))
        return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }

    /// Same pipeline under `-editor.topDownCamera` — the mode the recording driver runs in.
    /// Also asserts the driver's own coordinate math: it converts meters to normalized view
    /// offsets by inverting the documented ortho frame, so project→unproject must agree.
    func testTopDownAutomationModePipeline() throws {
        UserDefaults.standard.set(true, forKey: "editor.topDownCamera")
        defer { UserDefaults.standard.removeObject(forKey: "editor.topDownCamera") }

        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        let home = makeTwoRoomHome()
        let store = try HomeModelStore(model: home)
        let controller = UnifiedSceneController(scnView: view, home: home)
        controller.currentHome = store.model
        controller.rebuild(home: store.model, activeFloorId: "f0")
        let bridge = SceneKitEditorBridge(store: store, scene: controller)
        bridge.hapticsEnabled = false

        XCTAssertTrue(view.pointOfView?.camera?.usesOrthographicProjection == true,
                      "automation mode must pin the deterministic ortho camera")

        // The driver's framing inverse: bbox (0,0)-(6.5,3) + 1.5 padding → scale 4.75.
        // Its normalized offset for plan (x, y): u/v from the ortho frame. Replicate and
        // assert the resulting screen point unprojects back to the same plan point.
        let scale = 4.75
        let cx = 3.25, cy = 1.5
        let aspect = 874.0 / 402.0
        let halfW = scale * aspect
        for (x, y) in [(5.0, 1.5), (3.5, 0.0), (3.0, 1.5)] {
            let u = (x - cx) / (2 * halfW) + 0.5
            let v = (-(y - cy)) / (2 * scale) + 0.5
            let screenPoint = CGPoint(x: u * 874.0, y: v * 402.0)
            let world = try XCTUnwrap(controller.worldPoint(from: screenPoint),
                                      "top-down unprojection returned nil for (\(x), \(y))")
            XCTAssertEqual(world.x, x, accuracy: 0.1, "x mismatch for plan (\(x), \(y))")
            XCTAssertEqual(world.y, y, accuracy: 0.1, "y mismatch for plan (\(x), \(y))")
        }

        // Select + arbitrated corner drag, exactly like the driver's join step.
        bridge.handleTap(at: screen(5.0, 1.5, view: view))
        XCTAssertEqual(store.selection, .room(roomId: "r2"))
        XCTAssertEqual(bridge.dragIntent(at: screen(3.5, 0, view: view)), .edit)
        bridge.handleDrag(.began, at: screen(3.5, 0, view: view))
        bridge.handleDrag(.changed, at: screen(3.02, 0.02, view: view))
        bridge.handleDrag(.ended, at: screen(3.02, 0.02, view: view))
        let dragged = try XCTUnwrap(store.model.floors[0].rooms.first { $0.id == "r2" })
        XCTAssertEqual(dragged.polygon[0].x, 3.0, accuracy: 0.15)
    }

    func testTapSelectsThenArbitratedCornerDragJoinsRooms() throws {
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        let home = makeTwoRoomHome()
        let store = try HomeModelStore(model: home)
        let controller = UnifiedSceneController(scnView: view, home: home)
        controller.currentHome = store.model
        controller.rebuild(home: store.model, activeFloorId: "f0")
        let bridge = SceneKitEditorBridge(store: store, scene: controller)
        bridge.hapticsEnabled = false

        // 0. Screen→world must round-trip through the real camera.
        let probe = screen(5.0, 1.5, view: view)
        let world = try XCTUnwrap(controller.worldPoint(from: probe),
                                  "unprojection onto the floor plane returned nil")
        XCTAssertEqual(world.x, 5.0, accuracy: 0.05)
        XCTAssertEqual(world.y, 1.5, accuracy: 0.05)

        // 1. Tap the second room's body: selects it.
        bridge.handleTap(at: probe)
        XCTAssertEqual(store.selection, .room(roomId: "r2"))

        // 2. A drag beginning on the selected room's corner is an EDIT...
        let corner = screen(3.5, 0, view: view)
        XCTAssertEqual(bridge.dragIntent(at: corner), .edit)
        // ...and one beginning on the other room orbits.
        XCTAssertEqual(bridge.dragIntent(at: screen(1.0, 2.5, view: view)), .camera)

        // 3. Drag the corner onto Room 1's corner (the driver's join move).
        bridge.handleDrag(.began, at: corner)
        bridge.handleDrag(.changed, at: screen(3.02, 0.02, view: view))
        bridge.handleDrag(.ended, at: screen(3.02, 0.02, view: view))

        let dragged = try XCTUnwrap(store.model.floors[0].rooms.first { $0.id == "r2" })
        let v = dragged.polygon[0]
        XCTAssertEqual(v.x, 3.0, accuracy: 0.15,
                       "corner should have moved to ~(3,0) — snap lands it exactly")
        XCTAssertEqual(v.y, 0.0, accuracy: 0.15)
    }
}
