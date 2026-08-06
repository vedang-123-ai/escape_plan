//  GaitCycleTests.swift
//  Procedural pose and distance/speed-derived phase-lock coverage.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class GaitCycleTests: XCTestCase {

    private func step(_ x: Double, _ y: Double,
                      floor: String = "f1", time: Double,
                      kind: String = "path") -> TimedStep {
        TimedStep(x: x, y: y, floor_id: floor, t_s: time, kind: kind)
    }

    private func assertFinite(_ pose: GaitPose,
                              file: StaticString = #filePath, line: UInt = #line) {
        for value in pose.allValues {
            XCTAssertTrue(value.isFinite, "non-finite pose value: \(value)",
                          file: file, line: line)
        }
    }

    private func assertFinite(_ sample: GaitPhaseSample,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(sample.phase.isFinite, file: file, line: line)
        XCTAssertTrue(sample.cycleCount.isFinite, file: file, line: line)
        XCTAssertTrue(sample.effectiveStrideLength.isFinite, file: file, line: line)
        XCTAssertTrue(sample.cadence.isFinite, file: file, line: line)
        XCTAssertTrue(sample.groundSpeed.isFinite, file: file, line: line)
    }

    func testPoseIsPeriodicAndDeterministic() {
        let gait = GaitCycle(kind: .adult)
        let reference = gait.pose(at: 0.25)
        XCTAssertEqual(reference, gait.pose(at: 1.25))
        XCTAssertEqual(reference, gait.pose(at: -0.75))
        XCTAssertEqual(reference, gait.pose(at: 0.25))
        assertFinite(reference)
    }

    func testBipedLeftAndRightChainsAreHalfCycleOpposites() {
        let gait = GaitCycle(kind: .adult)
        let pose = gait.pose(at: 0)
        XCTAssertEqual(pose.leftHip, -pose.rightHip, accuracy: 1e-12)
        XCTAssertEqual(pose.leftShoulder, -pose.rightShoulder, accuracy: 1e-12)
        XCTAssertEqual(pose.leftKnee, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(pose.rightKnee, 0)
        XCTAssertEqual(pose.torsoBob, 0, accuracy: 1e-12)
    }

    func testTorsoBobHasTwoNonnegativePeaksPerCycle() {
        let gait = GaitCycle(kind: .adult)
        XCTAssertEqual(gait.pose(at: 0).torsoBob, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(gait.pose(at: 0.25).torsoBob, 0)
        XCTAssertEqual(gait.pose(at: 0.5).torsoBob, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(gait.pose(at: 0.75).torsoBob, 0)
        for index in 0...100 {
            XCTAssertGreaterThanOrEqual(gait.pose(at: Double(index) / 100).torsoBob, 0)
        }
    }

    func testGaitKindConfigurationsAreVisiblyDistinct() {
        let adult = GaitCycle(kind: .adult)
        let child = GaitCycle(kind: .child)
        let elderly = GaitCycle(kind: .elderly)
        let wheelchair = GaitCycle(kind: .wheelchair)
        let pet = GaitCycle(kind: .pet)

        XCTAssertGreaterThan(child.cadence, adult.cadence)
        XCTAssertLessThan(child.strideLength, adult.strideLength)
        XCTAssertLessThan(elderly.cadence, adult.cadence)
        XCTAssertLessThan(elderly.amplitude, adult.amplitude)
        XCTAssertEqual(wheelchair.style, .wheelchair)
        XCTAssertEqual(pet.style, .quadruped)
        XCTAssertEqual(GaitCycle(kind: .unknown), adult)
    }

    func testEffectiveStrideDerivesFromSpeedAndCadenceThenCapsAtNominal() {
        let gait = GaitCycle(strideLength: 1, cadence: 2, amplitude: 1)
        XCTAssertEqual(gait.effectiveStrideLength(for: 0), 0)
        XCTAssertEqual(gait.effectiveStrideLength(for: 0.6), 0.3, accuracy: 1e-12)
        XCTAssertEqual(gait.effectiveStrideLength(for: 3), 1, accuracy: 1e-12)
        XCTAssertEqual(gait.effectiveStrideLength(for: .nan), 0)
        XCTAssertEqual(gait.effectiveStrideLength(for: .infinity), 0)
    }

    func testShortActualStrideReducesReachWithoutChangingNeutralPosture() {
        let gait = GaitCycle(strideLength: 1, cadence: 2, amplitude: 1)
        let full = gait.pose(at: 0, effectiveStrideLength: 1)
        let shuffle = gait.pose(at: 0, effectiveStrideLength: 0.25)
        let idle = gait.pose(at: 0, effectiveStrideLength: 0)

        XCTAssertLessThan(abs(shuffle.leftHip), abs(full.leftHip))
        XCTAssertEqual(shuffle.leftHip, full.leftHip * 0.25, accuracy: 1e-12)
        XCTAssertEqual(idle.leftHip, 0)
        XCTAssertEqual(idle.spinePitch, full.spinePitch, accuracy: 1e-12)
        XCTAssertEqual(idle.leftElbow, gait.pose(at: 0.5, effectiveStrideLength: 0).leftElbow)
    }

    func testWheelchairHasNoLegGaitAndUsesSymmetricPushAndWheels() {
        let gait = GaitCycle(kind: .wheelchair)
        let pose = gait.pose(at: 0.25)
        XCTAssertEqual(pose.leftHip, 0)
        XCTAssertEqual(pose.rightHip, 0)
        XCTAssertEqual(pose.leftKnee, 0)
        XCTAssertEqual(pose.rightKnee, 0)
        XCTAssertEqual(pose.leftAnkle, 0)
        XCTAssertEqual(pose.rightAnkle, 0)
        XCTAssertEqual(pose.leftShoulder, pose.rightShoulder)
        XCTAssertEqual(pose.leftElbow, pose.rightElbow)
        XCTAssertEqual(pose.wheelRotation, -.pi / 2, accuracy: 1e-12)
        assertFinite(pose)
    }

    func testZeroAmplitudeStopsWheelchairArmArticulation() {
        let gait = GaitCycle(strideLength: 1, cadence: 1, amplitude: 0,
                             style: .wheelchair)
        let first = gait.pose(at: 0)
        let second = gait.pose(at: 0.5)
        XCTAssertEqual(first.leftShoulder, second.leftShoulder)
        XCTAssertEqual(first.rightShoulder, second.rightShoulder)
        XCTAssertEqual(first.leftElbow, second.leftElbow)
        XCTAssertEqual(first.rightElbow, second.rightElbow)
        XCTAssertEqual(first.torsoBob, second.torsoBob)
    }

    func testPetUsesDiagonalTrotAndTail() {
        let gait = GaitCycle(kind: .pet)
        let pose = gait.pose(at: 0)
        XCTAssertEqual(pose.leftHip, pose.rightShoulder, accuracy: 1e-12)
        XCTAssertEqual(pose.rightHip, pose.leftShoulder, accuracy: 1e-12)
        XCTAssertNotEqual(pose.tailSwing, 0)
        XCTAssertEqual(pose.wheelRotation, 0)
    }

    func testPathologicalParametersAndPhasesNeverProduceNaN() {
        let gait = GaitCycle(strideLength: .infinity,
                             cadence: .nan,
                             amplitude: -.infinity,
                             stairStrideScale: .nan,
                             stairCadenceScale: .infinity,
                             hipSwing: .nan,
                             kneeLift: .infinity,
                             spineLean: -.infinity)
        for phase in [Double.nan, -.infinity, .infinity, -1e300, 0, 1e300] {
            assertFinite(gait.pose(at: phase, effectiveStrideLength: .nan))
        }
    }

    func testGroundPhaseUsesDistanceOverSpeedDerivedStride() {
        let cycle = GaitCycle(strideLength: 1, cadence: 2, amplitude: 1)
        let sampler = PathSampler(steps: [
            step(0, 0, time: 0),
            step(1, 0, time: 1),       // 1 m/s: effective stride 0.5, two cycles
            step(2, 0, time: 1.5),     // 2 m/s: effective stride 1, one cycle
        ])
        let lock = GaitPhaseLock(sampler: sampler, cycle: cycle)

        let firstQuarter = lock.sample(at: 0.25)
        XCTAssertEqual(firstQuarter,
                       lock.sample(for: sampler.sample(at: 0.25)!))
        XCTAssertEqual(firstQuarter.source, .groundDistance)
        XCTAssertEqual(firstQuarter.effectiveStrideLength, 0.5, accuracy: 1e-12)
        XCTAssertEqual(firstQuarter.cadence, 2, accuracy: 1e-12)
        XCTAssertEqual(firstQuarter.cycleCount, 0.5, accuracy: 1e-12)
        XCTAssertEqual(firstQuarter.phase, 0.5, accuracy: 1e-12)

        let secondMiddle = lock.sample(at: 1.25)
        XCTAssertEqual(secondMiddle.effectiveStrideLength, 1, accuracy: 1e-12)
        XCTAssertEqual(secondMiddle.cycleCount, 2.5, accuracy: 1e-12)
        XCTAssertEqual(secondMiddle.phase, 0.5, accuracy: 1e-12)
    }

    func testActualSpeedChangesStrideRatherThanLettingFeetSkate() {
        let cycle = GaitCycle(strideLength: 1, cadence: 1, amplitude: 1)
        let slow = GaitPhaseLock(steps: [
            step(0, 0, time: 0), step(1, 0, time: 2),
        ], cycle: cycle)
        let fast = GaitPhaseLock(steps: [
            step(0, 0, time: 0), step(1, 0, time: 0.5),
        ], cycle: cycle)

        let slowMid = slow.sample(at: 1)
        let fastMid = fast.sample(at: 0.25)
        XCTAssertEqual(slowMid.effectiveStrideLength, 0.5, accuracy: 1e-12)
        XCTAssertEqual(fastMid.effectiveStrideLength, 1, accuracy: 1e-12)
        // Both samples have traveled 0.5 m, but the slow shuffle needs a full cycle while the
        // fast nominal stride needs half: the foot reach matches the distance actually covered.
        XCTAssertEqual(slowMid.cycleCount, 1, accuracy: 1e-12)
        XCTAssertEqual(fastMid.cycleCount, 0.5, accuracy: 1e-12)
    }

    func testSameFloorDwellFreezesPhase() {
        let cycle = GaitCycle(strideLength: 1, cadence: 1, amplitude: 1)
        let lock = GaitPhaseLock(steps: [
            step(0, 0, time: 0),
            step(1, 0, time: 1),
            step(1, 0, time: 3),
            step(2, 0, time: 4),
        ], cycle: cycle)

        let start = lock.sample(at: 1)
        let middle = lock.sample(at: 2)
        let end = lock.sample(at: 3)
        XCTAssertEqual(start.source, .idle)
        XCTAssertEqual(middle.source, .idle)
        XCTAssertEqual(start.cycleCount, middle.cycleCount, accuracy: 1e-12)
        XCTAssertEqual(middle.cycleCount, end.cycleCount, accuracy: 1e-12)
        XCTAssertFalse(middle.isMoving)
    }

    func testFloorTransitionAdvancesASeparateShortStepPhase() {
        let cycle = GaitCycle(strideLength: 1, cadence: 2, amplitude: 1,
                              stairStrideScale: 0.4, stairCadenceScale: 0.75)
        let lock = GaitPhaseLock(steps: [
            step(0, 0, floor: "f2", time: 0),
            step(1, 0, floor: "f2", time: 1, kind: "stair"),
            step(1, 0, floor: "f1", time: 3, kind: "stair"),
            step(2, 0, floor: "f1", time: 4),
        ], cycle: cycle)

        let startCount = lock.sample(at: 1).cycleCount
        let middle = lock.sample(at: 2)
        XCTAssertEqual(middle.source, .floorTransition)
        XCTAssertTrue(middle.isMoving)
        XCTAssertEqual(middle.effectiveStrideLength, 0.4, accuracy: 1e-12)
        XCTAssertEqual(middle.cadence, 1.5, accuracy: 1e-12)
        XCTAssertEqual(middle.groundSpeed, 0)
        XCTAssertEqual(middle.cycleCount - startCount, 1.5, accuracy: 1e-12)
    }

    func testBoundaryStatesAreIdleButPreserveAccumulatedPhase() {
        let cycle = GaitCycle(strideLength: 1, cadence: 1, amplitude: 1)
        let lock = GaitPhaseLock(steps: [
            step(0, 0, time: 2), step(1, 0, time: 3),
        ], cycle: cycle)

        let before = lock.sample(at: 1)
        let end = lock.sample(at: 3)
        let after = lock.sample(at: 30)
        XCTAssertEqual(before.source, .idle)
        XCTAssertEqual(before.cycleCount, 0)
        XCTAssertEqual(end.source, .idle)
        XCTAssertEqual(end.cycleCount, 1, accuracy: 1e-12)
        XCTAssertEqual(after, end)
    }

    func testCycleCountIsMonotonicAndScrubbingIsDeterministic() {
        let cycle = GaitCycle(kind: .child)
        let lock = GaitPhaseLock(steps: [
            step(0, 0, time: 0),
            step(2, 0, time: 1),
            step(2, 0, time: 2),
            step(2, 0, floor: "f2", time: 4, kind: "stair"),
            step(4, 0, floor: "f2", time: 5),
        ], cycle: cycle)

        var previous = -Double.infinity
        for index in 0...500 {
            let time = Double(index) / 100
            let first = lock.sample(at: time)
            let second = lock.sample(at: time)
            XCTAssertEqual(first, second)
            XCTAssertGreaterThanOrEqual(first.cycleCount + 1e-12, previous)
            previous = first.cycleCount
            assertFinite(first)
            assertFinite(cycle.pose(at: first.phase,
                                    effectiveStrideLength: first.effectiveStrideLength))
        }
    }

    func testZeroDurationMovementAndDegenerateTrackStayFinite() {
        let cycle = GaitCycle(kind: .adult)
        let lock = GaitPhaseLock(steps: [
            step(0, 0, time: 0),
            step(1, 0, time: 0),
            step(1, 0, time: 2),
        ], cycle: cycle)
        for time in [Double.nan, -.infinity, -1, 0, 1, 2, 3, .infinity] {
            let sample = lock.sample(at: time)
            assertFinite(sample)
            XCTAssertGreaterThanOrEqual(sample.cycleCount, 0)
        }
    }
}
