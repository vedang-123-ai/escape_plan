//  PathSamplerTests.swift
//  Boundary, degenerate-path, stair-transition, and circular-heading coverage.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class PathSamplerTests: XCTestCase {

    private func step(_ x: Double, _ y: Double,
                      floor: String = "f1", time: Double,
                      kind: String = "path") -> TimedStep {
        TimedStep(x: x, y: y, floor_id: floor, t_s: time, kind: kind)
    }

    private func unwrap(_ sampler: PathSampler, at time: Double,
                        file: StaticString = #filePath, line: UInt = #line) -> PathSample {
        guard let sample = sampler.sample(at: time) else {
            XCTFail("expected a sample", file: file, line: line)
            return PathSample(position: PathPosition(x: 0, y: 0), heading: 0,
                              floorID: "", kind: "", segmentIndex: nil,
                              segmentProgress: 0, floorTransition: nil,
                              groundSpeed: 0, groundDistance: 0,
                              isBeforeStart: false, isAfterEnd: false,
                              hasReachedEnd: false)
        }
        return sample
    }

    private func assertFinite(_ sample: PathSample,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(sample.position.x.isFinite, file: file, line: line)
        XCTAssertTrue(sample.position.y.isFinite, file: file, line: line)
        XCTAssertTrue(sample.heading.isFinite, file: file, line: line)
        XCTAssertTrue(sample.segmentProgress.isFinite, file: file, line: line)
        XCTAssertTrue(sample.groundSpeed.isFinite, file: file, line: line)
        XCTAssertTrue(sample.groundDistance.isFinite, file: file, line: line)
        if let transition = sample.floorTransition {
            XCTAssertTrue(transition.progress.isFinite, file: file, line: line)
        }
    }

    private func circularDistance(_ a: Double, _ b: Double) -> Double {
        abs(atan2(sin(a - b), cos(a - b)))
    }

    func testEmptyTrackHasNoPositionToInvent() {
        let sampler = PathSampler(steps: [])
        XCTAssertNil(sampler.sample(at: 0))
        XCTAssertNil(sampler.startTime)
        XCTAssertNil(sampler.endTime)
        XCTAssertEqual(sampler.totalGroundDistance, 0)
    }

    func testLinearInterpolationCarriesFloorKindHeadingSpeedAndDistance() {
        let sampler = PathSampler(steps: [
            step(1, 2, time: 2, kind: "room"),
            step(5, 2, time: 4, kind: "opening"),
        ])
        let sample = unwrap(sampler, at: 3)

        XCTAssertEqual(sample.position.x, 3, accuracy: 1e-12)
        XCTAssertEqual(sample.position.y, 2, accuracy: 1e-12)
        XCTAssertEqual(sample.heading, 0, accuracy: 1e-12)
        XCTAssertEqual(sample.floorID, "f1")
        XCTAssertEqual(sample.kind, "room")
        XCTAssertEqual(sample.currentKind, "room")
        XCTAssertEqual(sample.segmentIndex, 0)
        XCTAssertEqual(sample.segmentProgress, 0.5, accuracy: 1e-12)
        XCTAssertEqual(sample.groundSpeed, 2, accuracy: 1e-12)
        XCTAssertEqual(sample.groundDistance, 2, accuracy: 1e-12)
        XCTAssertTrue(sample.isInMotion)
        XCTAssertFalse(sample.hasReachedEnd)
    }

    func testHeadingUsesPlanCoordinates() {
        let north = PathSampler(steps: [step(0, 0, time: 0), step(0, 2, time: 1)])
        XCTAssertEqual(unwrap(north, at: 0.5).heading, .pi / 2, accuracy: 1e-12)

        let south = PathSampler(steps: [step(0, 0, time: 0), step(0, -2, time: 1)])
        XCTAssertEqual(unwrap(south, at: 0.5).heading, -.pi / 2, accuracy: 1e-12)
    }

    func testBeforeStartAndAfterEndClampWithExplicitState() {
        let sampler = PathSampler(steps: [
            step(1, 2, time: 2, kind: "room"),
            step(5, 6, time: 4, kind: "exterior"),
        ])

        let before = unwrap(sampler, at: -10)
        XCTAssertEqual(before.position, PathPosition(x: 1, y: 2))
        XCTAssertTrue(before.isBeforeStart)
        XCTAssertFalse(before.isAfterEnd)
        XCTAssertFalse(before.hasReachedEnd)
        XCTAssertEqual(before.groundSpeed, 0)

        let atStart = unwrap(sampler, at: 2)
        XCTAssertFalse(atStart.isBeforeStart)
        XCTAssertFalse(atStart.hasReachedEnd)

        let atEnd = unwrap(sampler, at: 4)
        XCTAssertEqual(atEnd.position, PathPosition(x: 5, y: 6))
        XCTAssertEqual(atEnd.floorID, "f1")
        XCTAssertEqual(atEnd.kind, "exterior")
        XCTAssertFalse(atEnd.isAfterEnd)
        XCTAssertTrue(atEnd.hasReachedEnd)
        XCTAssertEqual(atEnd.groundSpeed, 0)

        let after = unwrap(sampler, at: 40)
        XCTAssertEqual(after.position, atEnd.position)
        XCTAssertTrue(after.isAfterEnd)
        XCTAssertTrue(after.hasReachedEnd)
        XCTAssertEqual(after.groundDistance, atEnd.groundDistance)
    }

    func testExactInteriorBoundaryActivatesDestinationStep() {
        let sampler = PathSampler(steps: [
            step(0, 0, time: 0, kind: "room"),
            step(1, 0, time: 1, kind: "opening"),
            step(2, 0, time: 2, kind: "exterior"),
        ])

        let sample = unwrap(sampler, at: 1)
        XCTAssertEqual(sample.position, PathPosition(x: 1, y: 0))
        XCTAssertEqual(sample.segmentIndex, 1)
        XCTAssertEqual(sample.segmentProgress, 0)
        XCTAssertEqual(sample.kind, "opening")
    }

    func testSingletonIsFiniteAndSettlesAtItsOnlyTimestamp() {
        let sampler = PathSampler(steps: [step(3, 7, floor: "upper", time: 5,
                                                      kind: "exterior")])
        let before = unwrap(sampler, at: 4)
        let exact = unwrap(sampler, at: 5)
        let after = unwrap(sampler, at: 6)

        XCTAssertTrue(before.isBeforeStart)
        XCTAssertFalse(before.hasReachedEnd)
        XCTAssertTrue(exact.hasReachedEnd)
        XCTAssertTrue(after.isAfterEnd)
        XCTAssertNil(exact.segmentIndex)
        for sample in [before, exact, after] {
            XCTAssertEqual(sample.position, PathPosition(x: 3, y: 7))
            XCTAssertEqual(sample.floorID, "upper")
            XCTAssertEqual(sample.kind, "exterior")
            assertFinite(sample)
        }
    }

    func testSharedXYFloorCrossingPreservesVerticalInterpolationContract() throws {
        let sampler = PathSampler(steps: [
            step(0, 0, floor: "f2", time: 0, kind: "room"),
            step(1, 0, floor: "f2", time: 1, kind: "stair"),
            step(1, 0, floor: "f1", time: 3, kind: "stair"),
            step(2, 0, floor: "f1", time: 4, kind: "exterior"),
        ])

        let middle = unwrap(sampler, at: 2)
        let transition = try XCTUnwrap(middle.floorTransition)
        XCTAssertEqual(middle.position, PathPosition(x: 1, y: 0))
        XCTAssertEqual(middle.floorID, "f2", "source floor remains active in flight")
        XCTAssertEqual(middle.kind, "stair")
        XCTAssertEqual(transition.fromFloorID, "f2")
        XCTAssertEqual(transition.toFloorID, "f1")
        XCTAssertEqual(transition.progress, 0.5, accuracy: 1e-12)
        XCTAssertEqual(middle.groundSpeed, 0)
        XCTAssertEqual(middle.groundDistance, 1, accuracy: 1e-12)
        XCTAssertTrue(middle.isInMotion, "vertical motion is still motion")

        let landed = unwrap(sampler, at: 3)
        XCTAssertEqual(landed.floorID, "f1")
        XCTAssertEqual(landed.position, middle.position)
        XCTAssertNil(landed.floorTransition)
        XCTAssertEqual(landed.groundDistance, middle.groundDistance)
    }

    func testSameFloorDwellIsStationaryAndKeepsDistance() {
        let sampler = PathSampler(steps: [
            step(0, 0, time: 0),
            step(1, 0, time: 1),
            step(1, 0, time: 3),
            step(2, 0, time: 4),
        ])
        let dwell = unwrap(sampler, at: 2)
        XCTAssertEqual(dwell.groundSpeed, 0)
        XCTAssertEqual(dwell.groundDistance, 1)
        XCTAssertFalse(dwell.isInMotion)
        assertFinite(dwell)
    }

    func testAllDegenerateSegmentsNeverProduceNaN() {
        let sampler = PathSampler(steps: [
            step(2, 2, floor: "f2", time: 0, kind: "stair"),
            step(2, 2, floor: "f1", time: 0, kind: "stair"),
            step(2, 2, floor: "f1", time: 3, kind: "path"),
            step(2, 2, floor: "f1", time: 3, kind: "exterior"),
        ])

        for time in stride(from: -1.0, through: 4.0, by: 0.125) {
            let sample = unwrap(sampler, at: time)
            assertFinite(sample)
            XCTAssertEqual(sample.heading, 0)
            XCTAssertEqual(sample.groundDistance, 0)
        }
    }

    func testDuplicateTimestampsAreAtomicAndDeterministic() {
        let sampler = PathSampler(steps: [
            step(0, 0, time: 0, kind: "room"),
            step(1, 0, time: 0, kind: "opening"),
            step(2, 0, time: 1, kind: "exterior"),
        ])

        let first = unwrap(sampler, at: 0)
        let second = unwrap(sampler, at: 0)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.position, PathPosition(x: 1, y: 0))
        XCTAssertEqual(first.kind, "opening")
        XCTAssertEqual(first.segmentIndex, 1)
        XCTAssertEqual(first.groundDistance, 1)
        assertFinite(first)
    }

    func testGroundDistanceIsMonotonicAcrossWholeTrack() {
        let sampler = PathSampler(steps: [
            step(0, 0, time: 0),
            step(3, 0, time: 2),
            step(3, 4, time: 6),
            step(3, 4, time: 7),
            step(4, 4, time: 8),
        ])

        var previous = -Double.infinity
        for index in 0...800 {
            let sample = unwrap(sampler, at: Double(index) / 100)
            XCTAssertGreaterThanOrEqual(sample.groundDistance + 1e-12, previous)
            previous = sample.groundDistance
            assertFinite(sample)
        }
        XCTAssertEqual(sampler.totalGroundDistance, 8, accuracy: 1e-12)
    }

    func testCornerHeadingIsContinuousAcrossWaypoint() {
        let sampler = PathSampler(steps: [
            step(0, 0, time: 0),
            step(1, 0, time: 1),
            step(1, 1, time: 2),
        ])

        let before = unwrap(sampler, at: 1 - 1e-6).heading
        let at = unwrap(sampler, at: 1).heading
        let after = unwrap(sampler, at: 1 + 1e-6).heading
        XCTAssertLessThan(circularDistance(before, at), 1e-8)
        XCTAssertLessThan(circularDistance(at, after), 1e-8)
        XCTAssertEqual(at, .pi / 4, accuracy: 1e-12)
    }

    func testCircularSmoothingTakesShortWayAcrossPiBoundary() {
        let dy = tan(Double.pi / 180)
        let sampler = PathSampler(steps: [
            step(0, 0, time: 0),
            step(-1, dy, time: 1),       // about +179 degrees
            step(-2, 0, time: 2),        // about -179 degrees
        ])
        let corner = unwrap(sampler, at: 1).heading
        XCTAssertLessThan(abs(abs(corner) - .pi), 1e-10,
                          "circular mean must face west, not wrap through east")
    }

    func testNonFiniteInputAndQueryAreSanitizedWithoutNaN() {
        let sampler = PathSampler(steps: [
            step(.nan, .infinity, time: .nan, kind: "room"),
            step(2, 4, time: 2, kind: "exterior"),
        ])

        let nanQuery = unwrap(sampler, at: .nan)
        XCTAssertEqual(nanQuery.position, PathPosition(x: 0, y: 0))
        assertFinite(nanQuery)
        assertFinite(unwrap(sampler, at: -.infinity))
        assertFinite(unwrap(sampler, at: .infinity))
        assertFinite(unwrap(sampler, at: 1))
    }

    func testBackwardsTimestampsClampInPlaceRatherThanReorderingRoute() {
        let sampler = PathSampler(steps: [
            step(0, 0, time: 2, kind: "room"),
            step(1, 0, time: 1, kind: "opening"),
            step(2, 0, time: 3, kind: "exterior"),
        ])
        let sample = unwrap(sampler, at: 2)
        XCTAssertEqual(sample.position, PathPosition(x: 1, y: 0))
        XCTAssertEqual(sample.kind, "opening")
        assertFinite(sample)
    }
}
