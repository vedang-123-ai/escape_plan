import Foundation
import XCTest

// SceneKit playback belongs to the iOS target; the Foundation-only SwiftPM harness compiles
// this file empty and exercises PathSampler/GaitCycle in their dedicated suites instead.
// The platform import lives INSIDE the guard for the same reason as EvacuationSceneLayerTests.
#if !SWIFT_PACKAGE
import SceneKit
@testable import escape_plan

@MainActor
final class EvacuationRenderingTests: XCTestCase {

    func testAnimatedFigureInterpolatesFloorsAndScrubsBackwardsDeterministically() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        let timeline = makeStairTimeline(home: home, trackCount: 1)

        XCTAssertTrue(layer.show(timeline: timeline, home: home).isEmpty)
        let root = try XCTUnwrap(layer.figureNodesByProfileID["evac-0"])
        let joints = try XCTUnwrap(PersonFixture.jointHandles(in: root))
        let heights = DollhouseGeometry.floorBaseHeights(of: home)

        layer.update(time: 3, reduceMotion: false)
        XCTAssertEqual(Double(root.position.y),
                       ((heights["f2"] ?? 0) + (heights["f1"] ?? 0)) / 2,
                       accuracy: 0.0001)
        XCTAssertGreaterThan(abs(joints.spine.eulerAngles.x), 0.1,
                             "a floor crossing should visibly lean into its stair pose")

        layer.update(time: 1.25, reduceMotion: false)
        let firstPosition = root.position
        let firstYaw = root.eulerAngles.y
        let firstHip = joints.leftHip.eulerAngles

        layer.update(time: 7.5, reduceMotion: false)
        layer.update(time: 1.25, reduceMotion: false)
        XCTAssertEqual(root.position.x, firstPosition.x, accuracy: 0.00001)
        XCTAssertEqual(root.position.y, firstPosition.y, accuracy: 0.00001)
        XCTAssertEqual(root.position.z, firstPosition.z, accuracy: 0.00001)
        XCTAssertEqual(root.eulerAngles.y, firstYaw, accuracy: 0.00001)
        XCTAssertEqual(joints.leftHip.eulerAngles.x, firstHip.x, accuracy: 0.00001)
        XCTAssertEqual(joints.leftHip.eulerAngles.y, firstHip.y, accuracy: 0.00001)
        XCTAssertEqual(joints.leftHip.eulerAngles.z, firstHip.z, accuracy: 0.00001)

        layer.update(time: timeline.duration_s, reduceMotion: false)
        let settledPosition = root.position
        let settledHip = joints.leftHip.eulerAngles
        layer.update(time: timeline.duration_s + 100, reduceMotion: false)
        XCTAssertEqual(root.position.x, settledPosition.x, accuracy: 0.00001)
        XCTAssertEqual(root.position.y, settledPosition.y, accuracy: 0.00001)
        XCTAssertEqual(root.position.z, settledPosition.z, accuracy: 0.00001)
        XCTAssertEqual(joints.leftHip.eulerAngles.x, settledHip.x, accuracy: 0.00001,
                       "a figure must remain settled outside after egress")
    }

    func testReduceMotionSnapsToSuppliedWaypointsWithNeutralJoints() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        let timeline = makeStairTimeline(home: home, trackCount: 1)
        XCTAssertTrue(layer.show(timeline: timeline, home: home).isEmpty)
        let root = try XCTUnwrap(layer.figureNodesByProfileID["evac-0"])
        let joints = try XCTUnwrap(PersonFixture.jointHandles(in: root))

        layer.update(time: 1.75, reduceMotion: false)
        let interpolated = root.position
        layer.update(time: 1.75, reduceMotion: true)
        let snapped = root.position

        XCTAssertNotEqual(snapped.x, interpolated.x)
        XCTAssertNotEqual(snapped.z, interpolated.z)
        XCTAssertEqual(joints.leftHip.eulerAngles.x, 0, accuracy: 0.00001)
        XCTAssertEqual(joints.rightHip.eulerAngles.x, 0, accuracy: 0.00001)
        XCTAssertEqual(joints.leftShoulder.eulerAngles.x, 0, accuracy: 0.00001)

        layer.update(time: .infinity, reduceMotion: true)
        XCTAssertEqual(root.position.x, 1.5, accuracy: 0.00001)
        XCTAssertEqual(root.position.z, -1, accuracy: 0.00001,
                       "an unbounded seek should settle at the supplied exterior waypoint")
    }

    func testPlanHeadingsAndCoordinatesMapToSceneCardinalDirections() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        let track = OccupantTrack(
            profile_id: "cardinal",
            profile_name: "Cardinal Walker",
            gait: .adult,
            start_room_id: "r_living",
            exit_id: "d_front",
            steps: [
                TimedStep(x: 1, y: 1, floor_id: "f1", t_s: 0, kind: "room"),
                TimedStep(x: 3, y: 1, floor_id: "f1", t_s: 2, kind: "path"),
                TimedStep(x: 3, y: 3, floor_id: "f1", t_s: 4, kind: "exterior"),
            ],
            distance_m: 4,
            egress_time_s: 4
        )
        let timeline = EvacuationTimeline(
            home_id: home.home_id,
            origin_room_id: "r_kitchen",
            tracks: [track],
            hazard: [],
            duration_s: 4
        )
        XCTAssertTrue(layer.show(timeline: timeline, home: home).isEmpty)
        let root = try XCTUnwrap(layer.figureNodesByProfileID[track.profile_id])

        layer.update(time: 1, reduceMotion: false)
        XCTAssertEqual(root.position.x, 2, accuracy: 0.00001)
        XCTAssertEqual(root.position.z, -1, accuracy: 0.00001)
        XCTAssertEqual(sin(Double(root.eulerAngles.y)), 1, accuracy: 0.00001,
                       "plan +x must face scene +x")
        XCTAssertEqual(cos(Double(root.eulerAngles.y)), 0, accuracy: 0.00001)

        layer.update(time: 3, reduceMotion: false)
        XCTAssertEqual(root.position.x, 3, accuracy: 0.00001)
        XCTAssertEqual(root.position.z, -2, accuracy: 0.00001,
                       "plan +y must map to scene -z")
        XCTAssertEqual(sin(Double(root.eulerAngles.y)), 0, accuracy: 0.00001)
        XCTAssertEqual(cos(Double(root.eulerAngles.y)), -1, accuracy: 0.00001,
                       "the +z-authored rig must face scene -z")
    }

    func testAnimatedWheelchairAndPetRetainDistinctDeterministicRigMotion() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        let steps = [
            TimedStep(x: 1, y: 1, floor_id: "f1", t_s: 0, kind: "room"),
            TimedStep(x: 5, y: 1, floor_id: "f1", t_s: 2, kind: "exterior"),
        ]
        let tracks = [
            OccupantTrack(profile_id: "wheelchair-user", profile_name: "Wheelchair User",
                          gait: .wheelchair, start_room_id: "r_living", exit_id: "d_front",
                          steps: steps, distance_m: 4, egress_time_s: 2),
            OccupantTrack(profile_id: "pet", profile_name: "Pet",
                          gait: .pet, start_room_id: "r_living", exit_id: "d_front",
                          steps: steps, distance_m: 4, egress_time_s: 2),
        ]
        let timeline = EvacuationTimeline(
            home_id: home.home_id,
            origin_room_id: "r_kitchen",
            tracks: tracks,
            hazard: [],
            duration_s: 2
        )
        XCTAssertTrue(layer.show(timeline: timeline, home: home).isEmpty)
        let chairRoot = try XCTUnwrap(layer.figureNodesByProfileID["wheelchair-user"])
        let petRoot = try XCTUnwrap(layer.figureNodesByProfileID["pet"])
        let chair = try XCTUnwrap(PersonFixture.jointHandles(in: chairRoot))
        let pet = try XCTUnwrap(PersonFixture.jointHandles(in: petRoot))
        XCTAssertNotNil(chair.leftWheel)
        XCTAssertNil(chair.tail)
        XCTAssertNil(pet.leftWheel)
        XCTAssertNotNil(pet.tail)

        layer.update(time: 0.37, reduceMotion: false)
        let wheelRotation = try XCTUnwrap(chair.leftWheel).eulerAngles.x
        let tailYaw = try XCTUnwrap(pet.tail).eulerAngles.y
        XCTAssertGreaterThan(abs(wheelRotation), 0.1)
        XCTAssertEqual(chair.leftHip.eulerAngles.x, 0, accuracy: 0.00001,
                       "generic gait must not pull seated legs out of the chair")
        XCTAssertEqual(chair.rightHip.eulerAngles.x, 0, accuracy: 0.00001)
        XCTAssertGreaterThan(abs(tailYaw), 0.02)

        layer.update(time: 1.41, reduceMotion: false)
        layer.update(time: 0.37, reduceMotion: false)
        XCTAssertEqual(try XCTUnwrap(chair.leftWheel).eulerAngles.x,
                       wheelRotation, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(pet.tail).eulerAngles.y,
                       tailYaw, accuracy: 0.00001)
    }

    func testWindowExitUsesRealSillForControlledClimbAndReturnsToFloor() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        let track = OccupantTrack(
            profile_id: "window-user",
            profile_name: "Window User",
            gait: .adult,
            start_room_id: "r_living",
            exit_id: "w_living1",
            steps: [
                TimedStep(x: 2, y: 2, floor_id: "f1", t_s: 0, kind: "room"),
                TimedStep(x: 3, y: 2, floor_id: "f1", t_s: 2, kind: "opening"),
                TimedStep(x: 3, y: 2, floor_id: "f1", t_s: 4, kind: "exterior"),
            ],
            distance_m: 1,
            egress_time_s: 4,
            uses_window: true
        )
        let timeline = EvacuationTimeline(
            home_id: home.home_id,
            origin_room_id: "r_kitchen",
            tracks: [track],
            hazard: [],
            duration_s: 4
        )
        XCTAssertTrue(layer.show(timeline: timeline, home: home).isEmpty)
        let root = try XCTUnwrap(layer.figureNodesByProfileID[track.profile_id])
        let joints = try XCTUnwrap(PersonFixture.jointHandles(in: root))
        let base = DollhouseGeometry.floorBaseHeights(of: home)["f1"] ?? 0

        layer.update(time: 3, reduceMotion: false)
        XCTAssertGreaterThan(Double(root.position.y), base + 0.5,
                             "the 0.8 m fixture sill should lift the climb arc")
        XCTAssertGreaterThan(abs(joints.leftKnee.eulerAngles.x), 0.5)

        layer.update(time: 4, reduceMotion: false)
        XCTAssertEqual(Double(root.position.y), base, accuracy: 0.0001)
        layer.update(time: 3, reduceMotion: true)
        XCTAssertEqual(Double(root.position.y), base, accuracy: 0.0001,
                       "Reduce Motion degrades the climb to static waypoints")
    }

    func testStaticProfilesUseMobilitySilhouettesAndVisibilitySurvivesRedraw() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        layer.isVisible = false
        XCTAssertTrue(layer.show(profiles: home.profiles, home: home, highlighted: nil).isEmpty)

        let child = try XCTUnwrap(layer.figureNodesByProfileID["p_maya"])
        let wheelchair = try XCTUnwrap(layer.figureNodesByProfileID["p_grandpa"])
        XCTAssertTrue(child.isHidden)
        XCTAssertTrue(wheelchair.isHidden)
        XCTAssertNil(PersonFixture.jointHandles(in: child)?.leftWheel)
        XCTAssertNotNil(PersonFixture.jointHandles(in: wheelchair)?.leftWheel)

        layer.isVisible = true
        XCTAssertFalse(child.isHidden)
        XCTAssertFalse(wheelchair.isHidden)
    }

    func testEightFigureRenderHotPathStaysInsideSixtyHertzFrameBudget() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = PeopleLayer(dollhouse: built.dollhouse)
        let timeline = makeStairTimeline(home: home, trackCount: 8)
        XCTAssertTrue(layer.show(timeline: timeline, home: home).isEmpty)
        XCTAssertEqual(layer.figureNodesByProfileID.count, 8)

        let frameCount = 900
        let start = ProcessInfo.processInfo.systemUptime
        for frame in 0..<frameCount {
            let time = Double(frame % 480) / 60
            layer.update(time: time, reduceMotion: false)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let secondsPerFrame = elapsed / Double(frameCount)
        XCTAssertLessThan(secondsPerFrame, 1.0 / 60.0,
                          "8-figure transform work exceeded a 60 Hz CPU frame budget: "
                          + "\(secondsPerFrame * 1_000) ms/frame")
        XCTAssertEqual(layer.figureNodesByProfileID.count, 8,
                       "the hot path must not create replacement figure nodes")
    }

    private func makeStairTimeline(home: HomeModel, trackCount: Int) -> EvacuationTimeline {
        let steps = [
            TimedStep(x: 1, y: 1, floor_id: "f2", t_s: 0, kind: "room"),
            TimedStep(x: 5, y: 6, floor_id: "f2", t_s: 2, kind: "stair"),
            TimedStep(x: 5, y: 6, floor_id: "f1", t_s: 4, kind: "stair"),
            TimedStep(x: 2, y: 1, floor_id: "f1", t_s: 6, kind: "opening"),
            TimedStep(x: 1.5, y: 1, floor_id: "f1", t_s: 8, kind: "exterior"),
        ]
        let kinds: [GaitKind] = [.adult, .child, .elderly, .wheelchair, .pet]
        let tracks = (0..<trackCount).map { index in
            OccupantTrack(
                profile_id: "evac-\(index)",
                profile_name: "Occupant \(index)",
                gait: kinds[index % kinds.count],
                start_room_id: "r_bed_kids",
                exit_id: "d_front",
                steps: steps,
                distance_m: 10,
                egress_time_s: 8,
                uses_stairs: true
            )
        }
        return EvacuationTimeline(
            home_id: home.home_id,
            origin_room_id: "r_kitchen",
            tracks: tracks,
            hazard: [],
            duration_s: 8
        )
    }
}
#endif
