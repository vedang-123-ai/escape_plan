//  SnappingTests.swift — snapping is what makes hand-authoring a home fast, so its rules are
//  pinned here rather than discovered by feel on a device.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class SnappingTests: XCTestCase {

    // MARK: - Grid

    func testGridRoundsToNearestCell() {
        let s = SnapSettings(gridEnabled: true, gridSizeM: 0.1,
                             axisEnabled: false, wallSnapEnabled: false)

        let r = SnapEngine.snap(Point2D(1.234, 5.678), context: .empty, settings: s)
        XCTAssertPointEqual(r.point, Point2D(1.2, 5.7), accuracy: 1e-9)
        XCTAssertEqual(r.kind, .grid)
    }

    func testGridSnapIsSymmetricAroundZero() {
        let s = SnapSettings(gridEnabled: true, gridSizeM: 0.1,
                             axisEnabled: false, wallSnapEnabled: false)
        let r = SnapEngine.snap(Point2D(-1.24, -1.26), context: .empty, settings: s)
        XCTAssertPointEqual(r.point, Point2D(-1.2, -1.3), accuracy: 1e-9)
    }

    func testDisabledSettingsPassCoordinatesThroughUntouched() {
        let r = SnapEngine.snap(Point2D(1.23456, 7.89), context: .empty, settings: .disabled)
        XCTAssertPointEqual(r.point, Point2D(1.23456, 7.89))
        XCTAssertEqual(r.kind, .none)
    }

    // MARK: - Axis

    func testAxisSnapLocksOntoAnAnchorCoordinate() {
        let s = SnapSettings(gridEnabled: false, axisEnabled: true, axisToleranceM: 0.05,
                            wallSnapEnabled: false)
        // Dragging a corner to x≈3.02 when its neighbour sits at x=3.0 should straighten the wall.
        let ctx = SnapContext(axisAnchors: [Point2D(3.0, 0), Point2D(0, 7.0)])

        let r = SnapEngine.snap(Point2D(3.02, 7.03), context: ctx, settings: s)
        XCTAssertPointEqual(r.point, Point2D(3.0, 7.0), accuracy: 1e-9)
        XCTAssertEqual(r.kind, .axis)
    }

    func testAxisSnapIgnoresAnchorsOutsideTolerance() {
        let s = SnapSettings(gridEnabled: false, axisEnabled: true, axisToleranceM: 0.05,
                            wallSnapEnabled: false)
        let ctx = SnapContext(axisAnchors: [Point2D(3.0, 0)])
        let r = SnapEngine.snap(Point2D(3.5, 1.0), context: ctx, settings: s)
        XCTAssertPointEqual(r.point, Point2D(3.5, 1.0))
        XCTAssertEqual(r.kind, .none)
    }

    func testAxisLockBeatsTheGridOnTheLockedAxisOnly() {
        // The point of composing them: aligning to a neighbour must not be dragged back off by
        // the grid, but the free coordinate should still land on a grid line.
        let s = SnapSettings(gridEnabled: true, gridSizeM: 0.1,
                             axisEnabled: true, axisToleranceM: 0.05, wallSnapEnabled: false)
        let ctx = SnapContext(axisAnchors: [Point2D(3.03, 0)])

        let r = SnapEngine.snap(Point2D(3.04, 5.67), context: ctx, settings: s)
        XCTAssertEqual(r.point.x, 3.03, accuracy: 1e-9, "x should hold the anchor, off-grid")
        XCTAssertEqual(r.point.y, 5.7, accuracy: 1e-9, "y is free, so it grids")
        XCTAssertEqual(r.kind, .axis)
    }

    // MARK: - Walls & vertices

    func testVertexSnapWins() {
        let s = SnapSettings.default
        let ctx = SnapContext(vertices: [Point2D(5, 4)],
                              segments: [[Point2D(5, 4), Point2D(10, 4)]])

        let r = SnapEngine.snap(Point2D(5.08, 4.06), context: ctx, settings: s)
        XCTAssertPointEqual(r.point, Point2D(5, 4), accuracy: 1e-9)
        XCTAssertEqual(r.kind, .vertex, "a corner in range must beat the wall it belongs to")
    }

    func testWallSnapProjectsOntoTheWall() {
        let s = SnapSettings.default
        let ctx = SnapContext(segments: [[Point2D(0, 4), Point2D(10, 4)]])

        // Near the middle of the wall, far from either end.
        let r = SnapEngine.snap(Point2D(6.03, 4.11), context: ctx, settings: s)
        XCTAssertPointEqual(r.point, Point2D(6.03, 4.0), accuracy: 1e-9)
        XCTAssertEqual(r.kind, .wall, "this is how a user connects a room to its neighbour")
    }

    func testWallSnapRespectsItsRadius() {
        let s = SnapSettings(wallSnapEnabled: true, wallSnapRadiusM: 0.25)
        let ctx = SnapContext(segments: [[Point2D(0, 4), Point2D(10, 4)]])

        let r = SnapEngine.snap(Point2D(6.0, 4.9), context: ctx, settings: s)
        XCTAssertNotEqual(r.kind, .wall, "0.9m away is not a snap, it's a placement")
    }

    func testWallSnapBeatsGrid() {
        // Off-grid geometry (a scan-derived wall) must still be snappable — otherwise the grid
        // would make it impossible to close a gap against a converted scan.
        let s = SnapSettings.default
        let ctx = SnapContext(segments: [[Point2D(0, 4.03), Point2D(10, 4.03)]])

        let r = SnapEngine.snap(Point2D(6.0, 4.05), context: ctx, settings: s)
        XCTAssertEqual(r.kind, .wall)
        XCTAssertEqual(r.point.y, 4.03, accuracy: 1e-9)
    }

    // MARK: - Translations

    func testTranslationSnapsTheDeltaNotTheVertices() {
        // Dragging a whole room must preserve its shape exactly. Snapping each vertex
        // independently would deform an off-grid (scan-derived) footprint; snapping the delta
        // cannot.
        let s = SnapSettings(gridEnabled: true, gridSizeM: 0.1)
        let delta = SnapEngine.snapTranslation(Point2D(1.23, -0.44), settings: s)
        XCTAssertPointEqual(delta, Point2D(1.2, -0.4), accuracy: 1e-9)

        let offGrid = [Point2D(0.03, 0.07), Point2D(3.13, 0.07), Point2D(3.13, 2.57)]
        let moved = Geometry.translate(offGrid, by: delta)
        for (a, b) in zip(offGrid, moved) {
            XCTAssertEqual(Geometry.distance(a, b), Geometry.length(delta), accuracy: 1e-9)
        }
    }

    func testTranslationIsIdentityWhenGridIsOff() {
        let d = SnapEngine.snapTranslation(Point2D(1.23456, -0.4), settings: .disabled)
        XCTAssertPointEqual(d, Point2D(1.23456, -0.4))
    }

    // MARK: - Determinism

    func testSnappingIsDeterministic() {
        let s = SnapSettings.default
        let ctx = SnapContext(vertices: [Point2D(1, 1), Point2D(2, 2)],
                              segments: [[Point2D(0, 0), Point2D(5, 0)]],
                              axisAnchors: [Point2D(1.5, 1.5)])
        let first = SnapEngine.snap(Point2D(1.11, 0.98), context: ctx, settings: s)
        for _ in 0..<50 {
            XCTAssertEqual(SnapEngine.snap(Point2D(1.11, 0.98), context: ctx, settings: s), first)
        }
    }
}
