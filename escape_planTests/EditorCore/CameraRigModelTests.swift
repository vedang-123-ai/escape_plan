//  CameraRigModelTests.swift — the pure orbit-camera math the unified 3D view stands on.
//
//  The one invariant that makes pinch feel right: zooming toward an anchor keeps the
//  camera→anchor direction fixed while the distance scales — that is exactly "the point
//  under your fingers stays under your fingers".

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class CameraRigModelTests: XCTestCase {

    typealias Vec3 = CameraRigModel.Vec3

    private func makeRig() -> CameraRigModel {
        CameraRigModel(pivot: Vec3(x: 2, y: 1, z: -3), yaw: 0.7, pitch: 0.5, distance: 12)
    }

    private func assertEqual(_ a: Vec3, _ b: Vec3, accuracy: Double = 1e-9,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Basis

    func testPositionSitsAtDistanceFromPivot() {
        let rig = makeRig()
        XCTAssertEqual((rig.position - rig.pivot).length, rig.distance, accuracy: 1e-9)
    }

    func testBasisIsOrthonormalAndUpIsUpward() {
        let rig = makeRig()
        let f = (rig.pivot - rig.position).normalized()
        XCTAssertEqual(rig.right.length, 1, accuracy: 1e-9)
        XCTAssertEqual(rig.up.length, 1, accuracy: 1e-9)
        // right ⊥ forward, up ⊥ both.
        XCTAssertEqual(rig.right.x * f.x + rig.right.y * f.y + rig.right.z * f.z, 0, accuracy: 1e-9)
        XCTAssertEqual(rig.up.x * f.x + rig.up.y * f.y + rig.up.z * f.z, 0, accuracy: 1e-9)
        // An orbit camera never rolls: right stays horizontal, up points skyward.
        XCTAssertEqual(rig.right.y, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(rig.up.y, 0)
    }

    // MARK: - Orbit

    func testOrbitClampsPitchAtBothEnds() {
        var rig = makeRig()
        rig.orbit(deltaYaw: 0, deltaPitch: 10)
        XCTAssertEqual(rig.pitch, rig.pitchRange.upperBound, accuracy: 1e-12)
        rig.orbit(deltaYaw: 0, deltaPitch: -10)
        XCTAssertEqual(rig.pitch, rig.pitchRange.lowerBound, accuracy: 1e-12)
    }

    func testOrbitKeepsPivotAndDistance() {
        var rig = makeRig()
        let pivot = rig.pivot
        rig.orbit(deltaYaw: 1.3, deltaPitch: -0.2)
        assertEqual(rig.pivot, pivot)
        XCTAssertEqual(rig.distance, 12, accuracy: 1e-12)
    }

    // MARK: - Truck

    func testTruckMovesPivotInCameraPlaneOnly() {
        var rig = makeRig()
        let before = rig
        rig.truck(rightMeters: 2, upMeters: -1)
        assertEqual(rig.pivot, before.pivot + before.right * 2 + before.up * -1)
        // Orientation and zoom are untouched — the whole frame translates.
        XCTAssertEqual(rig.yaw, before.yaw, accuracy: 1e-12)
        XCTAssertEqual(rig.pitch, before.pitch, accuracy: 1e-12)
        XCTAssertEqual(rig.distance, before.distance, accuracy: 1e-12)
        assertEqual(rig.position - rig.pivot, before.position - before.pivot)
    }

    // MARK: - Zoom

    func testZoomTowardAnchorHoldsAnchorDirectionAndScalesDistance() {
        var rig = makeRig()
        let anchor = Vec3(x: 4, y: 0.5, z: -1)
        let before = rig.position
        let scale = 1.8

        rig.zoom(scale: scale, towardAnchor: anchor)

        // The camera moves straight toward the anchor: same direction, 1/scale the distance.
        let expected = anchor + (before - anchor) * (1 / scale)
        assertEqual(rig.position, expected, accuracy: 1e-9)
        XCTAssertEqual(rig.distance, 12 / scale, accuracy: 1e-9)
        // Orientation is untouched — zoom never re-aims the camera.
        XCTAssertEqual(rig.yaw, 0.7, accuracy: 1e-12)
        XCTAssertEqual(rig.pitch, 0.5, accuracy: 1e-12)
    }

    func testZoomOutMovesAwayFromAnchor() {
        var rig = makeRig()
        let anchor = rig.pivot
        rig.zoom(scale: 0.5, towardAnchor: anchor)
        XCTAssertEqual(rig.distance, 24, accuracy: 1e-9)
    }

    func testZoomClampStopsPivotDrift() {
        var rig = makeRig()
        rig.distanceRange = 10...100
        let anchor = Vec3(x: 0, y: 0, z: 0)
        // Requested distance 12/100 would blow through the floor of 10; the pivot slide must
        // shrink to the clamped effective scale, not keep marching into the anchor.
        let before = rig.position
        rig.zoom(scale: 100, towardAnchor: anchor)
        XCTAssertEqual(rig.distance, 10, accuracy: 1e-12)
        let effective = 12.0 / 10.0
        assertEqual(rig.position, anchor + (before - anchor) * (1 / effective), accuracy: 1e-9)
    }

    func testDegenerateZoomScaleIsIgnored() {
        var rig = makeRig()
        let before = rig
        rig.zoom(scale: 0, towardAnchor: Vec3.zero)
        XCTAssertEqual(rig, before)
    }

    // MARK: - Meters per point

    func testMetersPerPointMatchesFrustumHeight() {
        let rig = makeRig()
        // At fov 50° and distance 12, the frustum spans 2·12·tan(25°) meters vertically.
        let expected = 2 * 12 * tan(25 * Double.pi / 180) / 800
        XCTAssertEqual(rig.metersPerPoint(fovDegrees: 50, viewHeightPoints: 800),
                       expected, accuracy: 1e-12)
        XCTAssertEqual(rig.metersPerPoint(fovDegrees: 50, viewHeightPoints: 0), 0.01)
    }

    // MARK: - Framing

    func testFramingLooksAtHouseCenterFromThreeQuarterAngle() {
        let rig = CameraRigModel.framing(center: Vec3(x: 5, y: 0, z: -4),
                                         extent: 10, totalHeight: 5.4)
        XCTAssertEqual(rig.pivot.x, 5, accuracy: 1e-12)
        XCTAssertEqual(rig.pivot.y, 5.4 * 0.35, accuracy: 1e-12)
        XCTAssertEqual(rig.pivot.z, -4, accuracy: 1e-12)
        // 2.2 × extent: the 35° long lens sees a narrower span than the old 50°, so the camera
        // backs off to frame the same house. Same number the recenter chip springs back to.
        XCTAssertEqual(rig.distance, 22, accuracy: 1e-12)
        XCTAssertTrue(rig.pitchRange.contains(rig.pitch))
        XCTAssertTrue(rig.distanceRange.contains(rig.distance),
                      "the opening shot must sit inside the zoom limits, not on their edge")
        // The camera must sit above the house looking down at it.
        XCTAssertGreaterThan(rig.position.y, rig.pivot.y)
    }

    func testFramingSurvivesDegenerateExtent() {
        let rig = CameraRigModel.framing(center: .zero, extent: 0, totalHeight: 0)
        XCTAssertGreaterThan(rig.distance, 0)
        XCTAssertTrue(rig.distanceRange.contains(rig.distance))
    }

    // MARK: - White Model overhaul (Aug 2026): bounds, rubber band, axis lock

    func testPitchClampKeepsTheCameraOutOfOpaqueWalls() {
        var rig = CameraRigModel(pivot: .zero, yaw: 0, pitch: 0, distance: 10)
        rig.orbit(deltaYaw: 0, deltaPitch: -10)
        XCTAssertEqual(rig.pitch, 12 * .pi / 180, accuracy: 1e-9,
                       "5° let the camera skim inside walls once they became opaque")
        rig.orbit(deltaYaw: 0, deltaPitch: 10)
        XCTAssertEqual(rig.pitch, 80 * .pi / 180, accuracy: 1e-9)
    }

    func testFramingTiesZoomLimitsToTheHouseSize() {
        let rig = CameraRigModel.framing(center: .zero, extent: 10, totalHeight: 5)
        XCTAssertEqual(rig.distanceRange.lowerBound, 3.5, accuracy: 1e-9,
                       "0.8 × extent stopped the user short of inspecting a single room")
        XCTAssertEqual(rig.distanceRange.upperBound, 40.0, accuracy: 1e-9)
        XCTAssertTrue(rig.distanceRange.contains(rig.distance))
    }

    // MARK: - Feel pass (Aug 2026): projection-correct panning, arbitration, looser limits

    func testMetersPerPointUnderOrthographicIgnoresDistanceAndFOV() {
        var rig = makeRig()
        // The whole point: under ortho the visible height is 2 × orthographicScale, full stop.
        let near = rig.metersPerPoint(projection: .orthographic(halfHeight: 6), viewHeightPoints: 800)
        XCTAssertEqual(near, 12.0 / 800, accuracy: 1e-12)

        rig.distance = 40
        XCTAssertEqual(rig.metersPerPoint(projection: .orthographic(halfHeight: 6),
                                          viewHeightPoints: 800),
                       near, accuracy: 1e-12,
                       "orthographic meters-per-point cannot depend on camera distance")
    }

    func testPerspectiveAndOrthographicDisagree() {
        // The bug: `truck` used the perspective form under the shipping orthographic camera.
        // At the framing the app actually ships — 35° FOV, and the orthographic scale matched
        // to it by CameraTuning — the two forms differ by a factor of about 3.2, which is why
        // the house did not track the finger.
        let rig = CameraRigModel(pivot: .zero, yaw: 0, pitch: 0.6, distance: 22)
        let perspective = rig.metersPerPoint(projection: .perspective(fovDegrees: 35),
                                             viewHeightPoints: 800)
        // Portrait aspect widening, as OrbitCameraRig.apply does it: scale /= aspect.
        let orthoHalfHeight = 22 * tan(35 * Double.pi / 180 / 2) / (390.0 / 844.0)
        let orthographic = rig.metersPerPoint(projection: .orthographic(halfHeight: orthoHalfHeight),
                                              viewHeightPoints: 800)
        XCTAssertGreaterThan(orthographic / perspective, 2.0,
                             "if these agreed, the projection branch would be pointless")
    }

    func testMetersPerPointRejectsADegenerateViewport() {
        let rig = makeRig()
        XCTAssertEqual(rig.metersPerPoint(projection: .orthographic(halfHeight: 6),
                                          viewHeightPoints: 0), 0.01)
        XCTAssertEqual(rig.metersPerPoint(projection: .orthographic(halfHeight: 0),
                                          viewHeightPoints: 800), 0.01,
                       accuracy: 0.01, "a zero-scale camera must not divide by zero")
    }

    func testOneFingerPanOrbits() {
        let arbiter = CameraRigModel.PanArbiter(touchCount: 1)
        XCTAssertEqual(arbiter.intent, .orbit)
        XCTAssertFalse(arbiter.orbitSuppressed)
    }

    func testTwoFingerPanNeverOrbits() {
        var arbiter = CameraRigModel.PanArbiter(touchCount: 2)
        XCTAssertEqual(arbiter.intent, .truck)
        arbiter.update(touchCount: 2)
        XCTAssertEqual(arbiter.intent, .truck)
    }

    func testASecondFingerArrivingMidGestureSuppressesOrbitImmediately() {
        var arbiter = CameraRigModel.PanArbiter(touchCount: 1)
        XCTAssertEqual(arbiter.intent, .orbit)
        arbiter.update(touchCount: 2)
        XCTAssertEqual(arbiter.intent, .truck,
                       "the pan kept orbiting at the two-finger centroid velocity while the "
                       + "pinch drove zoom — the camera fought itself")
    }

    func testOrbitDoesNotResumeWhenTheSecondFingerLifts() {
        var arbiter = CameraRigModel.PanArbiter(touchCount: 1)
        arbiter.update(touchCount: 2)
        arbiter.update(touchCount: 1)
        XCTAssertEqual(arbiter.intent, .truck)
        XCTAssertTrue(arbiter.orbitSuppressed)
        arbiter.update(touchCount: 0)
        XCTAssertEqual(arbiter.intent, .truck,
                       "handing the gesture to a different transition halfway through is the "
                       + "same self-fighting bug in a slower costume")
    }

    func testPanApronGivesRealRoomBeforeTheRubberBand() {
        let rig = CameraRigModel.framing(center: .zero, extent: 10, totalHeight: 5)
        let bounds = rig.pivotBounds!
        XCTAssertEqual(bounds.maxX, 6.0, accuracy: 1e-9,
                       "a quarter-extent apron read as 'I can't move the house'")
        XCTAssertEqual(bounds.minZ, -6.0, accuracy: 1e-9)
        // The clamp still exists — this is the bug it was added for.
        var moved = rig
        moved.yaw = 0
        moved.truck(rightMeters: 500, upMeters: 0)
        XCTAssertLessThanOrEqual(moved.pivot.x, bounds.maxX + 1e-9)
    }

    func testAxisLockNeedsMoreTravelBeforeItCommits() {
        // 15 pt of travel used to be enough to commit; it is inside the noise of a flick.
        XCTAssertFalse(CameraRigModel.shouldLockToYaw(dx: 14, dy: 1),
                       "12 pt let a short flick commit to an axis from a sample that had "
                       + "barely started")
        XCTAssertTrue(CameraRigModel.shouldLockToYaw(dx: 40, dy: 5))
    }

    func testPanCannotPushTheHouseOffScreen() {
        var rig = CameraRigModel.framing(center: .zero, extent: 10, totalHeight: 5)
        rig.yaw = 0
        rig.truck(rightMeters: 500, upMeters: 0)
        let bounds = try? XCTUnwrap(rig.pivotBounds)
        XCTAssertNotNil(bounds)
        XCTAssertLessThanOrEqual(rig.pivot.x, bounds!.maxX + 1e-9,
                                 "unbounded pan was the 'I lost the house' bug")
    }

    func testSoftClampAllowsOvershootAndSettleBringsItBack() {
        var rig = CameraRigModel.framing(center: .zero, extent: 10, totalHeight: 5)
        rig.yaw = 0
        let maxX = rig.pivotBounds!.maxX
        rig.truck(rightMeters: 100, upMeters: 0, soft: true)
        XCTAssertGreaterThan(rig.pivot.x, maxX, "a gesture in progress may overshoot…")
        XCTAssertLessThan(rig.pivot.x, maxX + 100, "…but only by a damped fraction")
        XCTAssertEqual(rig.settled().pivot.x, maxX, accuracy: 1e-9, "…and springs back on release")
    }

    func testAxisLockPicksTurntableOnlyForClearlyHorizontalDrags() {
        XCTAssertTrue(CameraRigModel.shouldLockToYaw(dx: 40, dy: 5))
        XCTAssertFalse(CameraRigModel.shouldLockToYaw(dx: 40, dy: 30))
        XCTAssertFalse(CameraRigModel.shouldLockToYaw(dx: 5, dy: 40))
        XCTAssertFalse(CameraRigModel.shouldLockToYaw(dx: 3, dy: 1),
                       "below the sample threshold the gesture is still undecided")
    }

    func testRecenteredSnapsYawToTheNearestDiagonal() {
        var rig = CameraRigModel.framing(center: .zero, extent: 10, totalHeight: 5)
        rig.yaw = 0.9 * .pi / 4          // just under a diagonal
        let framed = rig.recentered(on: CameraRigModel.Vec3(x: 1, y: 2, z: 3), extent: 10)
        XCTAssertEqual(framed.yaw, .pi / 4, accuracy: 1e-9)
        XCTAssertEqual(framed.pitch, 38 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(framed.distance, 22, accuracy: 1e-9)
    }
}
