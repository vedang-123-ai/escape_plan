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
        XCTAssertEqual(rig.distance, 19, accuracy: 1e-12)
        XCTAssertTrue(rig.pitchRange.contains(rig.pitch))
        // The camera must sit above the house looking down at it.
        XCTAssertGreaterThan(rig.position.y, rig.pivot.y)
    }

    func testFramingSurvivesDegenerateExtent() {
        let rig = CameraRigModel.framing(center: .zero, extent: 0, totalHeight: 0)
        XCTAssertGreaterThan(rig.distance, 0)
        XCTAssertTrue(rig.distanceRange.contains(rig.distance))
    }
}
