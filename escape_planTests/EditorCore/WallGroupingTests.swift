//  WallGroupingTests.swift — RoomPlan splits walls at doorways; the matcher must not care.
//
//  The defect (raised MEDIUM by the S9.1 audit, confirmed unfixed by the S9.2 audit, fixed
//  2026-09-16): `extractedLongestWall` took the longest raw wall SEGMENT. RoomPlan splits a
//  wall wherever a door interrupts it, so a 10 m living-room wall broken by two doorways
//  arrives as three ~3 m pieces and loses to an unbroken 4 m perpendicular wall. The matcher
//  aligns the scan to the model by that wall's direction, so the consequence is a permanent
//  90° rotation — silent, total, and previously only reproducible on a real scan.
//
//  It is testable at all because the merging was lifted OUT of the `#if canImport(RoomPlan)`
//  block into `WallGrouping`, which takes plain values. That is the point of the refactor:
//  logic written directly against `CapturedRoom` cannot run on any machine without a simulator,
//  which is how this survived two audits that both correctly identified it.

import Foundation
import XCTest
import simd

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class WallGroupingTests: XCTestCase {

    private let alongX = SIMD2<Float>(1, 0)
    private let alongZ = SIMD2<Float>(0, 1)

    private func segment(center: SIMD2<Float>, direction: SIMD2<Float>, length: Float)
        -> WallSegmentSample {
        WallSegmentSample(center: center, direction: direction, length: length)
    }

    // MARK: - The defect

    /// The exact shape from the audit: a 10 m wall in three pieces, against an unbroken 4 m
    /// perpendicular wall. Before the fix the 4 m wall won and every subsequent alignment was
    /// rotated 90°.
    func testASplitLongWallBeatsAnUnbrokenShorterOne() throws {
        let split = [
            segment(center: SIMD2(-3.5, 0), direction: alongX, length: 3),
            segment(center: SIMD2(0, 0), direction: alongX, length: 3),
            segment(center: SIMD2(3.5, 0), direction: alongX, length: 3),
        ]
        let perpendicular = [segment(center: SIMD2(5, 2), direction: alongZ, length: 4)]

        let result = try XCTUnwrap(WallGrouping.longestWall(from: split + perpendicular))

        XCTAssertEqual(abs(dot(result.direction, alongX)), 1, accuracy: 0.001,
                       "the merged 10 m wall must win; picking the 4 m wall rotates the whole "
                     + "scan 90°")
        XCTAssertEqual(result.length, 10, accuracy: 0.001,
                       "the span must include the doorway gaps — the wall is 10 m long whether "
                     + "or not you can walk through parts of it")
    }

    /// Stated from the other side, so the test above cannot be misread: the raw-segment rule
    /// really does pick the wrong wall. This is the old behaviour, written out.
    func testTheOldLongestSegmentRuleWouldHavePickedThePerpendicularWall() {
        let segments = [
            segment(center: SIMD2(-3.5, 0), direction: alongX, length: 3),
            segment(center: SIMD2(0, 0), direction: alongX, length: 3),
            segment(center: SIMD2(3.5, 0), direction: alongX, length: 3),
            segment(center: SIMD2(5, 2), direction: alongZ, length: 4),
        ]
        let longestRaw = segments.max(by: { $0.length < $1.length })
        XCTAssertEqual(longestRaw?.direction, alongZ,
                       "documents the defect: the longest SEGMENT is the perpendicular wall")
    }

    // MARK: - What must not merge

    /// Parallel is not collinear. The two long sides of a corridor are parallel and are
    /// emphatically not one wall — merging them would report a wall of the right length in a
    /// place with no wall at all.
    func testTheTwoSidesOfACorridorDoNotMerge() throws {
        let segments = [
            segment(center: SIMD2(0, 0), direction: alongX, length: 6),
            segment(center: SIMD2(0, 2), direction: alongX, length: 6),
        ]
        let result = try XCTUnwrap(WallGrouping.longestWall(from: segments))
        XCTAssertEqual(result.length, 6, accuracy: 0.001,
                       "two walls 2 m apart must not become one 6 m wall counted twice")
    }

    func testPerpendicularWallsDoNotMerge() throws {
        let segments = [
            segment(center: SIMD2(0, 0), direction: alongX, length: 5),
            segment(center: SIMD2(2.5, 2.5), direction: alongZ, length: 5),
        ]
        let result = try XCTUnwrap(WallGrouping.longestWall(from: segments))
        XCTAssertEqual(result.length, 5, accuracy: 0.001)
    }

    // MARK: - Real-scan tolerance

    /// RoomPlan's wall normals wobble a few degrees on a real scan. Segments a couple of
    /// degrees apart are one wall and must still merge, or the fix only works on synthetic
    /// input — which is exactly the failure mode this whole file exists to avoid.
    func testSegmentsAFewDegreesApartStillMerge() throws {
        let nudged = normalize(SIMD2<Float>(cos(0.05), sin(0.05)))  // ~2.9°
        let segments = [
            segment(center: SIMD2(-2.5, 0), direction: alongX, length: 4),
            segment(center: SIMD2(2.5, 0.1), direction: nudged, length: 4),
        ]
        let result = try XCTUnwrap(WallGrouping.longestWall(from: segments))
        XCTAssertGreaterThan(result.length, 8.5, "a slightly noisy pair must still be one wall")
    }

    /// But a genuinely different bearing must not be absorbed. 45° is the next angle that
    /// actually occurs in a home.
    func testAFortyFiveDegreeWallDoesNotMerge() throws {
        let diagonal = normalize(SIMD2<Float>(1, 1))
        let segments = [
            segment(center: SIMD2(-2, 0), direction: alongX, length: 4),
            segment(center: SIMD2(2, 0), direction: diagonal, length: 4),
        ]
        let result = try XCTUnwrap(WallGrouping.longestWall(from: segments))
        XCTAssertEqual(result.length, 4, accuracy: 0.001)
    }

    /// A wall scanned from the other side points the opposite way and is the same wall.
    func testOppositeFacingSegmentsOfOneWallMerge() throws {
        let segments = [
            segment(center: SIMD2(-2, 0), direction: alongX, length: 4),
            segment(center: SIMD2(2, 0), direction: -alongX, length: 4),
        ]
        let result = try XCTUnwrap(WallGrouping.longestWall(from: segments))
        XCTAssertEqual(result.length, 8, accuracy: 0.001)
    }

    // MARK: - Shape of the result

    func testTheNormalIsPerpendicularToTheDirection() throws {
        let result = try XCTUnwrap(WallGrouping.longestWall(
            from: [segment(center: .zero, direction: normalize(SIMD2<Float>(2, 1)), length: 5)]))
        XCTAssertEqual(dot(result.direction, result.normal), 0, accuracy: 0.001)
        XCTAssertEqual(length(result.direction), 1, accuracy: 0.001)
        XCTAssertEqual(length(result.normal), 1, accuracy: 0.001)
    }

    /// The order RoomPlan happens to hand over its walls must not change the answer.
    func testTheResultDoesNotDependOnSegmentOrder() throws {
        let segments = [
            segment(center: SIMD2(-3.5, 0), direction: alongX, length: 3),
            segment(center: SIMD2(3.5, 0), direction: alongX, length: 3),
            segment(center: SIMD2(0, 0), direction: alongX, length: 3),
            segment(center: SIMD2(5, 2), direction: alongZ, length: 4),
        ]
        let forwards = try XCTUnwrap(WallGrouping.longestWall(from: segments))
        let backwards = try XCTUnwrap(WallGrouping.longestWall(from: segments.reversed()))
        XCTAssertEqual(forwards.length, backwards.length, accuracy: 0.001)
        XCTAssertEqual(abs(dot(forwards.direction, backwards.direction)), 1, accuracy: 0.001)
    }

    func testNoWallsGivesNoAnswer() {
        XCTAssertNil(WallGrouping.longestWall(from: []))
    }

    /// Degenerate input must be ignored rather than producing a NaN direction that then
    /// poisons every downstream rotation.
    func testZeroLengthAndZeroDirectionSegmentsAreIgnored() throws {
        let segments = [
            segment(center: .zero, direction: alongX, length: 0),
            segment(center: .zero, direction: .zero, length: 5),
            segment(center: SIMD2(0, 3), direction: alongX, length: 6),
        ]
        let result = try XCTUnwrap(WallGrouping.longestWall(from: segments))
        XCTAssertEqual(result.length, 6, accuracy: 0.001)
        XCTAssertFalse(result.direction.x.isNaN || result.direction.y.isNaN)
    }
}
