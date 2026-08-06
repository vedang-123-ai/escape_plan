import Foundation
import XCTest

// SceneKit playback belongs to the iOS target; the Foundation-only SwiftPM harness compiles
// this file empty and exercises PathSampler/GaitCycle in their dedicated suites instead.
// The platform imports live INSIDE the guard on purpose — UIKit does not exist on macOS, and
// an import outside it fails the whole fast package build, not just this file.
#if !SWIFT_PACKAGE
import SceneKit
import UIKit
@testable import escape_plan

@MainActor
final class EvacuationSceneLayerTests: XCTestCase {

    func testHazardFrontUsesSuppliedTimesCapsParticlesAndClearsOnlyOwnedNodes() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = HazardLayer(dollhouse: built.dollhouse)
        let timeline = EvacuationTimeline(
            home_id: home.home_id,
            origin_room_id: "r_kitchen",
            tracks: [],
            hazard: [
                HazardEvent(room_id: "r_kitchen", floor_id: "f1", untenable_at_s: 0),
                HazardEvent(room_id: "r_living", floor_id: "f1", untenable_at_s: 10),
            ],
            duration_s: 10
        )

        let rootCount = built.dollhouse.scene.rootNode.childNodes.count
        XCTAssertTrue(layer.show(timeline: timeline, home: home).isEmpty)
        let origin = try material(named: "hazardFloor:r_kitchen", in: built.dollhouse.scene)
        let later = try material(named: "hazardFloor:r_living", in: built.dollhouse.scene)
        XCTAssertEqual(origin.transparency, EvacuationPalette.maximumFloorWashOpacity,
                       accuracy: 0.0001)
        XCTAssertEqual(later.transparency, 0, accuracy: 0.0001)

        layer.update(time: 8.5, reduceMotion: false)
        XCTAssertGreaterThan(later.transparency, 0)
        XCTAssertLessThan(later.transparency, EvacuationPalette.maximumFloorWashOpacity)

        layer.update(time: 9.9, reduceMotion: true)
        XCTAssertEqual(later.transparency, 0, accuracy: 0.0001)
        layer.update(time: 10, reduceMotion: true)
        XCTAssertEqual(later.transparency, EvacuationPalette.maximumFloorWashOpacity,
                       accuracy: 0.0001)

        var reduceMotionBirthRate: CGFloat = 0
        built.dollhouse.scene.rootNode.enumerateChildNodes { node, _ in
            for system in node.particleSystems ?? [] {
                reduceMotionBirthRate += system.birthRate
            }
        }
        XCTAssertEqual(reduceMotionBirthRate, 0,
                       "Reduce Motion must retain area state and suppress drifting particles")

        layer.update(time: 10, reduceMotion: false)
        var totalBirthRate: CGFloat = 0
        built.dollhouse.scene.rootNode.enumerateChildNodes { node, _ in
            for system in node.particleSystems ?? [] { totalBirthRate += system.birthRate }
        }
        XCTAssertLessThanOrEqual(totalBirthRate, 120.001)

        layer.clear()
        XCTAssertNil(built.dollhouse.scene.rootNode.childNode(
            withName: "hazardFloor:r_kitchen", recursively: true))
        XCTAssertEqual(built.dollhouse.scene.rootNode.childNodes.count, rootCount,
                       "clear must leave the built dollhouse untouched")
    }

    func testHazardRejectsUnknownReferencesInsteadOfPaintingTheOrigin() throws {
        let home = try FixtureLoader.load(.apartment)
        let built = DollhouseSceneBuilder.build(home)
        let layer = HazardLayer(dollhouse: built.dollhouse)
        let timeline = EvacuationTimeline(
            home_id: home.home_id,
            origin_room_id: "missing",
            tracks: [],
            hazard: [HazardEvent(room_id: "missing", floor_id: "missing-floor",
                                 untenable_at_s: 0)],
            duration_s: 0
        )
        let issues = layer.show(timeline: timeline, home: home)
        XCTAssertEqual(issues.count, 1)
        XCTAssertNil(built.dollhouse.scene.rootNode.childNode(
            withName: "hazard:missing", recursively: true))
    }

    func testTimelineTrackDrawsSuppliedFloorRunsAndCrossingInCanonicalCoolInk() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let layer = EvacuationTrackLayer(dollhouse: built.dollhouse)
        let timeline = makeStairTimeline(home: home)
        let before = descendantCount(of: built.dollhouse.scene.rootNode)

        XCTAssertTrue(layer.show(timeline: timeline, home: home).isEmpty)
        let upper = try XCTUnwrap(built.dollhouse.scene.rootNode.childNode(
            withName: "evacuationTrack:track-person:f2", recursively: true))
        let lower = try XCTUnwrap(built.dollhouse.scene.rootNode.childNode(
            withName: "evacuationTrack:track-person:f1", recursively: true))
        let crossing = try XCTUnwrap(built.dollhouse.scene.rootNode.childNode(
            withName: "evacuationTrack:track-person:floorCrossing", recursively: true))
        for node in [upper, lower, crossing] {
            let color = try XCTUnwrap(node.geometry?.firstMaterial?.diffuse.contents as? UIColor)
            XCTAssertTrue(color.isEqual(DollhousePalette.routePrimary))
            XCTAssertFalse(color.isEqual(DollhousePalette.hazardCore))
        }
        XCTAssertGreaterThan(descendantCount(of: built.dollhouse.scene.rootNode), before)

        layer.clear()
        XCTAssertEqual(descendantCount(of: built.dollhouse.scene.rootNode), before)
    }

    func testTimelineTrackBreaksAtInvalidDataRatherThanInventingShortcut() throws {
        let home = try FixtureLoader.load(.apartment)
        let built = DollhouseSceneBuilder.build(home)
        let layer = EvacuationTrackLayer(dollhouse: built.dollhouse)
        let track = OccupantTrack(
            profile_id: "broken",
            profile_name: "Broken",
            gait: .adult,
            start_room_id: home.floors[0].rooms[0].id,
            exit_id: home.floors[0].openings.first?.id ?? "exit",
            steps: [
                TimedStep(x: 0, y: 0, floor_id: home.floors[0].id, t_s: 0, kind: "room"),
                TimedStep(x: .nan, y: 1, floor_id: home.floors[0].id, t_s: 1, kind: "path"),
                TimedStep(x: 5, y: 5, floor_id: home.floors[0].id, t_s: 2, kind: "exterior"),
            ],
            distance_m: 0,
            egress_time_s: 2
        )
        let timeline = EvacuationTimeline(home_id: home.home_id,
                                          origin_room_id: track.start_room_id,
                                          tracks: [track], hazard: [], duration_s: 2)
        let issues = layer.show(timeline: timeline, home: home)
        XCTAssertTrue(issues.contains { $0.contains("non-finite") })
        XCTAssertTrue(issues.contains { $0.contains("no drawable") })
        XCTAssertNil(built.dollhouse.scene.rootNode.childNode(
            withName: "evacuationTrack:broken:\(home.floors[0].id)", recursively: true))
    }

    func testCameraYieldsPermanentlyToManualRigUntilExplicitResume() throws {
        let home = try FixtureLoader.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.scene = built.dollhouse.scene
        let manualCamera = built.dollhouse.cameraNode
        view.pointOfView = manualCamera

        let timeline = makeStairTimeline(home: home)
        let people = PeopleLayer(dollhouse: built.dollhouse)
        XCTAssertTrue(people.show(timeline: timeline, home: home).isEmpty)
        let camera = PlaybackCameraController(
            dollhouse: built.dollhouse,
            view: view,
            manualCameraNode: manualCamera,
            mode: .allActive
        )
        XCTAssertTrue(camera.begin(timeline: timeline,
                                   figureNodes: people.figureNodesByProfileID).isEmpty)
        XCTAssertEqual(view.pointOfView?.name, "evacuationPlaybackCamera")

        people.update(time: 3, reduceMotion: false)
        camera.update(time: 3, isPlaying: false, reduceMotion: false)
        let scale = try XCTUnwrap(view.pointOfView?.camera?.orthographicScale)
        XCTAssertTrue(scale.isFinite)
        XCTAssertGreaterThan(scale, 0)

        camera.userDidBeginManualControl()
        XCTAssertTrue(view.pointOfView === manualCamera)
        XCTAssertTrue(camera.isUnderManualOverride)
        camera.update(time: 6, isPlaying: true, reduceMotion: false)
        XCTAssertTrue(view.pointOfView === manualCamera,
                      "playback updates must not steal the camera after a gesture")

        camera.resumeAutomaticFraming()
        XCTAssertEqual(view.pointOfView?.name, "evacuationPlaybackCamera")
        camera.clear()
        XCTAssertTrue(view.pointOfView === manualCamera)
        XCTAssertNil(built.dollhouse.scene.rootNode.childNode(
            withName: "evacuationPlaybackCamera", recursively: true))
    }

    func testRouteAndHazardRemainDistinctWithoutHue() {
        XCTAssertTrue(EvacuationPalette.routePrimary.isEqual(DollhousePalette.routePrimary))
        XCTAssertTrue(EvacuationPalette.routeSecondary.isEqual(DollhousePalette.routeSecondary))
        XCTAssertTrue(EvacuationPalette.hazardCore.isEqual(DollhousePalette.hazardCore))
        XCTAssertGreaterThan(abs(EvacuationPalette.routePrimary.relativeLuminance
                                 - EvacuationPalette.hazardCore.relativeLuminance), 0.08)
        XCTAssertGreaterThan(abs(EvacuationPalette.routeSecondary.relativeLuminance
                                 - EvacuationPalette.hazardCore.relativeLuminance), 0.08)
    }

    private func material(named name: String, in scene: SCNScene) throws -> SCNMaterial {
        let node = try XCTUnwrap(scene.rootNode.childNode(withName: name, recursively: true))
        return try XCTUnwrap(node.geometry?.firstMaterial)
    }

    private func descendantCount(of root: SCNNode) -> Int {
        var count = 0
        root.enumerateChildNodes { _, _ in count += 1 }
        return count
    }

    private func makeStairTimeline(home: HomeModel) -> EvacuationTimeline {
        let track = OccupantTrack(
            profile_id: "track-person",
            profile_name: "Track Person",
            gait: .adult,
            start_room_id: "r_bed_kids",
            exit_id: "d_front",
            steps: [
                TimedStep(x: 1, y: 1, floor_id: "f2", t_s: 0, kind: "room"),
                TimedStep(x: 5, y: 6, floor_id: "f2", t_s: 2, kind: "stair"),
                TimedStep(x: 5, y: 6, floor_id: "f1", t_s: 4, kind: "stair"),
                TimedStep(x: 2, y: 1, floor_id: "f1", t_s: 6, kind: "opening"),
                TimedStep(x: 1.5, y: 1, floor_id: "f1", t_s: 8, kind: "exterior"),
            ],
            distance_m: 10,
            egress_time_s: 8,
            uses_stairs: true
        )
        return EvacuationTimeline(home_id: home.home_id,
                                  origin_room_id: "r_kitchen",
                                  tracks: [track], hazard: [], duration_s: 8)
    }
}
#endif
