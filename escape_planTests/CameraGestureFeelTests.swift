//  CameraGestureFeelTests.swift
//
//  The renderer-side half of the Aug 2026 camera feel pass. The pure math and the pan/orbit
//  arbitration live in `CameraRigModelTests` (fast, EditorCore); everything here needs a real
//  SCNView and a real camera, because the defects it covers were in how the rig talks to the
//  node rather than in the model.

import SceneKit
import XCTest
@testable import escape_plan

@MainActor
final class CameraGestureFeelTests: XCTestCase {

    /// A rig attached to a laid-out view with a real scene, so unprojection has a viewport.
    private func makeAttachedRig(_ home: HomeModel) -> (OrbitCameraRig, SCNView) {
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        // The view needs the scene assigned, not just the rig parented into it: `hitTest`
        // asserts on a null scene, which is how the anchor path reaches SceneKit.
        let built = DollhouseSceneBuilder.build(home)
        view.scene = built.dollhouse.scene
        let rig = OrbitCameraRig(home: home)
        rig.attach(to: built.dollhouse.scene, view: view)
        return (rig, view)
    }

    // MARK: - #2 The pinch anchor is resolved once, at .began

    /// Zoom-toward-anchor is defined against a FIXED point. `anchor(at:in:)` used to be
    /// re-resolved on every recognizer update, which both ran a full-scene hit test 60–120
    /// times a second and let the anchor crawl under the fingers as the centroid drifted.
    func testPinchAnchorIsResolvedOnceAtBeganAndNotPerFrame() throws {
        let home = try FixtureLibrary.load(.bungalow)
        let start = CGPoint(x: 120, y: 300)
        let drifted = CGPoint(x: 300, y: 640)

        // Same `.began` point, wildly different centroid on the `.changed` event.
        let (cached, cachedView) = makeAttachedRig(home)
        cached.beginPinch(at: start, in: cachedView)
        cached.pinch(scale: 1.4, centroid: drifted, in: cachedView)

        // Same `.began` point, centroid that never moved.
        let (still, stillView) = makeAttachedRig(home)
        still.beginPinch(at: start, in: stillView)
        still.pinch(scale: 1.4, centroid: start, in: stillView)

        XCTAssertEqual(cached.model, still.model,
                       "a drifting centroid must not move the anchor mid-pinch")

        // Control: if the centroid were still being honoured, `drifted` WOULD change the
        // answer. Without this the test would also pass on a rig that ignored the anchor.
        let (uncached, uncachedView) = makeAttachedRig(home)
        uncached.pinch(scale: 1.4, centroid: drifted, in: uncachedView)
        XCTAssertNotEqual(uncached.model, cached.model,
                          "the two centroids must resolve to genuinely different anchors, or "
                          + "this test proves nothing")
    }

    func testEndPinchReleasesTheAnchorForTheNextGesture() throws {
        let home = try FixtureLibrary.load(.bungalow)
        let (rig, view) = makeAttachedRig(home)
        let a = CGPoint(x: 120, y: 300)
        let b = CGPoint(x: 300, y: 640)

        rig.beginPinch(at: a, in: view)
        rig.pinch(scale: 1.2, centroid: a, in: view)
        rig.endPinch()
        let afterFirst = rig.model

        // A second pinch with no `beginPinch` falls back to its own centroid — it must not
        // still be zooming toward the previous gesture's anchor.
        rig.pinch(scale: 1.2, centroid: b, in: view)
        XCTAssertNotEqual(rig.model, afterFirst)
    }

    // MARK: - #1 Panning under the projection the app actually ships

    /// The house must track the finger. Under the default orthographic camera the visible
    /// height is `2 × orthographicScale`, so a drag of N points must move the pivot by
    /// `N × 2 × scale / viewHeight` meters — the perspective form gave a constant wrong ratio.
    func testPanUnderOrthographicMovesThePivotByTheOrthographicRatio() throws {
        let home = try FixtureLibrary.load(.bungalow)
        let (rig, view) = makeAttachedRig(home)
        let camera = try XCTUnwrap(rig.node.camera)
        XCTAssertTrue(camera.usesOrthographicProjection,
                      "this test is only meaningful against the shipping projection")

        let before = rig.model
        // Yaw is fixed so `right`/`up` are stable across the move.
        let scale = camera.orthographicScale
        rig.truck(byScreenDelta: CGPoint(x: 100, y: 0), in: view, soft: false)

        let expected = 100 * 2 * scale / Double(view.bounds.height)
        let moved = (rig.model.pivot - before.pivot).length
        XCTAssertEqual(moved, expected, accuracy: expected * 0.01,
                       "the pan ratio must come from orthographicScale, not from the FOV")
    }

    /// The same drag under perspective must use the FOV form — proving the branch is live in
    /// both directions rather than accidentally right for one.
    func testPanUnderPerspectiveUsesTheFrustumRatio() throws {
        let home = try FixtureLibrary.load(.bungalow)
        let (rig, view) = makeAttachedRig(home)
        rig.node.camera?.usesOrthographicProjection = false

        let before = rig.model
        rig.truck(byScreenDelta: CGPoint(x: 100, y: 0), in: view, soft: false)

        let fov = CameraTuning.fieldOfViewDegrees
        let expected = 100 * 2 * before.distance * tan(fov * .pi / 180 / 2)
            / Double(view.bounds.height)
        let moved = (rig.model.pivot - before.pivot).length
        XCTAssertEqual(moved, expected, accuracy: expected * 0.01)
    }

    // MARK: - #3 The camera basis survives the switch off look(at:)

    /// `apply()` now writes one `simdTransform` instead of `position` + `look(at:)`. The
    /// orientation must be IDENTICAL or the tour handoff in `PlaybackCameraController` — which
    /// restores `pointOfView` to this node — shows as a jump.
    func testTransformMatchesWhatLookAtProduced() throws {
        let home = try FixtureLibrary.load(.bungalow)
        let (rig, view) = makeAttachedRig(home)
        rig.orbit(byScreenDelta: CGPoint(x: 60, y: -40), in: view)

        let reference = SCNNode()
        reference.position = rig.node.position
        reference.look(at: SCNVector3(Float(rig.model.pivot.x),
                                      Float(rig.model.pivot.y),
                                      Float(rig.model.pivot.z)))

        let a = rig.node.simdTransform, b = reference.simdTransform
        for column in 0..<4 {
            for row in 0..<4 {
                XCTAssertEqual(a[column][row], b[column][row], accuracy: 1e-4,
                               "column \(column) row \(row) diverged from look(at:)")
            }
        }
    }

    /// The camera must actually look AT the pivot — the property `look(at:)` guaranteed.
    func testCameraKeepsPointingAtThePivotAcrossOrbitAndPan() throws {
        let home = try FixtureLibrary.load(.bungalow)
        let (rig, view) = makeAttachedRig(home)
        rig.orbit(byScreenDelta: CGPoint(x: 120, y: 70), in: view)
        rig.truck(byScreenDelta: CGPoint(x: -30, y: 25), in: view, soft: false)

        // Camera forward is −Z of its own transform.
        let t = rig.node.simdTransform
        let forward = SIMD3<Float>(-t[2][0], -t[2][1], -t[2][2])
        let toPivot = simd_normalize(SIMD3<Float>(Float(rig.model.pivot.x),
                                                  Float(rig.model.pivot.y),
                                                  Float(rig.model.pivot.z))
                                     - SIMD3<Float>(t[3][0], t[3][1], t[3][2]))
        XCTAssertEqual(simd_dot(forward, toPivot), 1, accuracy: 1e-3)
    }

    // MARK: - #8 The loosened limits reach the live rig

    func testTheRecenterChipNoLongerFiresOnAnyZoomAtAll() throws {
        let home = try FixtureLibrary.load(.bungalow)
        let (rig, view) = makeAttachedRig(home)
        XCTAssertFalse(rig.isOffHome(home), "the opening shot is by definition on-home")

        // Zoom in to a point that is now well inside the allowed range. Before the pass, the
        // "off home" test fired below 0.7 × extent while the zoom floor was 0.8 × extent — so
        // the chip appeared on essentially any zoom-in.
        rig.beginPinch(at: CGPoint(x: 195, y: 400), in: view)
        rig.pinch(scale: 1.6, centroid: CGPoint(x: 195, y: 400), in: view, soft: false)
        rig.endPinch()
        XCTAssertGreaterThan(rig.model.distance, rig.model.distanceRange.lowerBound,
                             "the zoom must not have bottomed out — that is a different case")
        XCTAssertFalse(rig.isOffHome(home),
                       "a single zoom-in step is not 'the user has lost the house'")
    }
}
