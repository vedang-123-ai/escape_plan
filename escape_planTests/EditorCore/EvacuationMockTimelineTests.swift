import Foundation
import XCTest

// MockTimeline lives in the iOS renderer target (though its own implementation is
// Foundation-only), so the SwiftPM EditorCore harness intentionally compiles this file empty.
#if !SWIFT_PACKAGE
@testable import escape_plan

final class EvacuationMockTimelineTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // EditorCore/
        .deletingLastPathComponent()  // escape_planTests/
        .deletingLastPathComponent()  // repo root

    private func loadHome(_ name: String) throws -> HomeModel {
        let url = Self.repoRoot.appendingPathComponent("escape_plan/Fixtures/\(name).json")
        return try HomeModel.decoder.decode(HomeModel.self, from: Data(contentsOf: url))
    }

    private func loadRoutePlan(_ name: String) throws -> RoutePlan {
        let url = Self.repoRoot.appendingPathComponent("docs/route-samples/\(name).routeplan.json")
        return try HomeModel.decoder.decode(RoutePlan.self, from: Data(contentsOf: url))
    }

    func testGenericFactoryExercisesAllThreeFixturesWithoutInventingPaths() throws {
        let fixtures: [(name: String, expectedTracks: Int, expectedIssues: Int)] = [
            ("bungalow", 4, 0),     // no profiles: one DEBUG-only occupant per room
            // Sam, and Biscuit the cat (added 2026-09-17, `72bf34e`). The pet track is intended:
            // `MockTimeline` gives a `.pet`-tagged profile its own gait.
            ("apartment", 2, 0),
            // The unscoped sample sends Grandpa down stairs. The mock must omit that track
            // rather than visually claim it is compatible with a wheelchair.
            ("twostory", 1, 1),
        ]

        for fixture in fixtures {
            let home = try loadHome(fixture.name)
            let plan = try loadRoutePlan(fixture.name)
            let origin = try XCTUnwrap(home.floors.flatMap(\.rooms).first { $0.type == .kitchen })
            let result = try MockTimeline.make(home: home, routePlan: plan,
                                               originRoomID: origin.id)

            XCTAssertEqual(result.issues.count, fixture.expectedIssues, fixture.name)
            XCTAssertEqual(result.timeline.tracks.count, fixture.expectedTracks, fixture.name)
            XCTAssertTrue(result.timeline.is_illustrative, fixture.name)
            XCTAssertEqual(result.timeline.origin_room_id, origin.id, fixture.name)
            XCTAssertEqual(result.timeline.hazard.first?.room_id, origin.id, fixture.name)
            XCTAssertEqual(result.timeline.hazard.first?.untenable_at_s, 0, fixture.name)
            XCTAssertEqual(result.timeline.hazard.count,
                           home.floors.reduce(0) { $0 + $1.rooms.count }, fixture.name)

            for track in result.timeline.tracks {
                XCTAssertGreaterThanOrEqual(track.steps.count, 2, fixture.name)
                XCTAssertEqual(track.steps.last?.kind, "exterior", fixture.name)
                XCTAssertEqual(track.egress_time_s, track.steps.last?.t_s, fixture.name)
                XCTAssertGreaterThan(track.distance_m, 0, fixture.name)
                for pair in zip(track.steps, track.steps.dropFirst()) {
                    XCTAssertLessThanOrEqual(pair.0.t_s, pair.1.t_s, fixture.name)
                }

                // The final semantic segment has non-zero time despite coincident opening /
                // EXTERIOR coordinates, and reads differently for a window versus a door.
                let finalDuration = track.steps[track.steps.count - 1].t_s
                    - track.steps[track.steps.count - 2].t_s
                XCTAssertEqual(finalDuration, track.uses_window ? 15 : 2,
                               accuracy: 0.001, fixture.name)
            }
        }
    }

    func testProfileGaitPrecedenceMatchesEndpointContract() throws {
        let home = try loadHome("twostory")
        let plan = try loadRoutePlan("twostory")
        let result = try MockTimeline.make(home: home, routePlan: plan,
                                           originRoomID: "r_kitchen")
        let gaitByID = Dictionary(uniqueKeysWithValues: result.timeline.tracks.map {
            ($0.profile_id, $0.gait)
        })
        XCTAssertEqual(gaitByID["p_maya"], .child)
        XCTAssertNil(gaitByID["p_grandpa"])
        XCTAssertTrue(result.issues.contains { $0.contains("Grandpa") && $0.contains("stairs") })
    }

    func testMissingRoutePlanProducesIssuesAndNoFabricatedTracks() throws {
        let home = try loadHome("apartment")
        let result = try MockTimeline.make(home: home, routePlans: [],
                                           originRoomID: "r_kitchen")
        XCTAssertTrue(result.timeline.tracks.isEmpty)
        XCTAssertEqual(result.issues.count, home.profiles.count)
        XCTAssertFalse(result.timeline.hazard.isEmpty,
                       "the independent abstract hazard mock remains useful")
    }
}
#endif
