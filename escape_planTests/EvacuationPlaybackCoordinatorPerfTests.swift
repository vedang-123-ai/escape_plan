import SceneKit
import UIKit
import XCTest
@testable import escape_plan

@MainActor
final class EvacuationPlaybackCoordinatorPerfTests: XCTestCase {

    func testCoordinatorLifecycleAndPlaybackTicking() throws {
        let home = try FixtureLoader.load(.bungalow)
        let scnView = SCNView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let controller = UnifiedSceneController(scnView: scnView, home: home)
        let playback = EvacuationPlaybackModel()
        let timeline = EvacuationTimeline(
            home_id: home.id,
            origin_room_id: "r1",
            tracks: [],
            hazard: [],
            duration_s: 30,
            is_illustrative: true
        )
        playback.load(timeline)

        let coordinator = controller.bindEvacuationPlayback(
            playback,
            staticPeopleLayer: { nil },
            suspendOrdinaryRoutes: nil,
            restoreOrdinaryRoutes: nil,
            onIssues: nil
        )

        XCTAssertNotNil(controller.evacuationPlaybackCoordinator)

        // Simulate 60 frames of playback ticks at 60 fps
        playback.play()
        for _ in 0..<60 {
            playback.tick(deltaTime: 0.016)
        }

        XCTAssertGreaterThan(playback.currentTime_s, 0)

        // Clean unbind
        controller.unbindEvacuationPlayback()
        XCTAssertNil(controller.evacuationPlaybackCoordinator)
    }

    func testRapidPlaybackSeekingCoalescesCleanly() throws {
        let home = try FixtureLoader.load(.bungalow)
        let scnView = SCNView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let controller = UnifiedSceneController(scnView: scnView, home: home)
        let playback = EvacuationPlaybackModel()

        controller.bindEvacuationPlayback(
            playback,
            staticPeopleLayer: { nil },
            suspendOrdinaryRoutes: nil,
            restoreOrdinaryRoutes: nil,
            onIssues: nil
        )

        // Rapid seeks in succession (e.g., user scrubbing)
        for t in stride(from: 0.0, through: 5.0, by: 0.1) {
            playback.seek(to: t)
        }

        controller.unbindEvacuationPlayback()
    }
}
