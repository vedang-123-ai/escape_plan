//
//  DrillModeTests.swift
//  escape_planTests — S4.2 drill mode
//

import XCTest
@testable import escape_plan

final class DrillSessionTests: XCTestCase {

    private func waypoint(_ x: Double, _ y: Double, floor: String, node: String,
                          kind: WaypointKind) -> Waypoint {
        Waypoint(x: x, y: y, floor_id: floor, node_id: node, kind: kind)
    }

    private func route(_ waypoints: [Waypoint], usesStairs: Bool = false) -> Route {
        Route(waypoints: waypoints, length_m: 10, uses_stairs: usesStairs,
              uses_window: false, exit_id: "exit-front")
    }

    private var profile: Profile {
        Profile(id: "p1", name: "Maya", tags: [.child], bedroom_room_id: "bed1")
    }

    // MARK: - Step derivation

    func testSingleFloorRouteDerivesStartMovesAndMeetingPoint() throws {
        let r = route([
            waypoint(0, 0, floor: "f0", node: "room:bed1", kind: .room),
            waypoint(1, 0, floor: "f0", node: "open:d1", kind: .opening),
            waypoint(2, 0, floor: "f0", node: "room:hall", kind: .room),
            waypoint(3, 0, floor: "f0", node: "open:front", kind: .exterior),
        ])
        let session = try XCTUnwrap(DrillSession(profile: profile, route: r,
                                                 startRoomName: "Maya's bedroom"))

        XCTAssertEqual(session.steps.count, 5) // start + 3 segments + meeting point
        XCTAssertEqual(session.steps.first, .start(roomName: "Maya's bedroom"))
        XCTAssertEqual(session.steps.last, .drillComplete(peril: "fire"))

        // Every middle step is a two-waypoint camera segment over the engine's own waypoints.
        for case let .move(segment, _) in session.steps {
            XCTAssertEqual(segment.waypoints.count, 2)
            XCTAssertEqual(segment.exit_id, r.exit_id)
        }
        if case .move(let segment, let kind) = session.steps[1] {
            XCTAssertEqual(segment.waypoints, Array(r.waypoints[0...1]))
            XCTAssertEqual(kind, .opening)
        } else {
            XCTFail("step 1 should be a move, got \(session.steps[1])")
        }
    }

    func testFloorCrossingBecomesStairsStepWithoutFlight() throws {
        // A crossing = two consecutive stair waypoints, same node_id/x/y, different floor_id.
        let r = route([
            waypoint(0, 0, floor: "f1", node: "room:bed2", kind: .room),
            waypoint(1, 1, floor: "f1", node: "stair:s1", kind: .stair),
            waypoint(1, 1, floor: "f0", node: "stair:s1", kind: .stair),
            waypoint(3, 0, floor: "f0", node: "open:front", kind: .exterior),
        ], usesStairs: true)
        let session = try XCTUnwrap(DrillSession(profile: profile, route: r,
                                                 startRoomName: "Upstairs bedroom"))

        XCTAssertEqual(session.steps[2], .stairs(fromFloorID: "f1", toFloorID: "f0"))
        // The crossing must not produce a camera segment — no move spans two floors.
        for case let .move(segment, _) in session.steps {
            XCTAssertEqual(segment.waypoints[0].floor_id, segment.waypoints[1].floor_id,
                           "a move segment must stay on one floor; the crossing is a card-only step")
        }
    }

    func testRouteWithFewerThanTwoWaypointsIsRejected() {
        let single = route([waypoint(0, 0, floor: "f0", node: "room:bed1", kind: .room)])
        XCTAssertNil(DrillSession(profile: profile, route: single, startRoomName: "Bedroom"))
    }

    // MARK: - Advancing

    func testAdvanceAndBackClampAtEnds() throws {
        let r = route([
            waypoint(0, 0, floor: "f0", node: "room:bed1", kind: .room),
            waypoint(3, 0, floor: "f0", node: "open:front", kind: .exterior),
        ])
        var session = try XCTUnwrap(DrillSession(profile: profile, route: r,
                                                 startRoomName: "Bedroom"))
        XCTAssertTrue(session.isAtStart)
        session.back()
        XCTAssertTrue(session.isAtStart, "back() at the start must clamp")

        while !session.isAtEnd { session.advance() }
        XCTAssertEqual(session.currentStep, .drillComplete(peril: "fire"))
        XCTAssertEqual(session.stepNumber, session.stepCount)
        session.advance()
        XCTAssertTrue(session.isAtEnd, "advance() at the end must clamp")
    }
}

final class DrillInstructionsTests: XCTestCase {

    /// The app never invents safety advice: every `[cite: id]` in the drill copy must resolve
    /// against the real backend/corpus/sources.json `sources` array.
    func testEveryCitationResolvesInCorpusSources() throws {
        let url = PersistenceFixtures.repoRoot
            .appendingPathComponent("backend/corpus/sources.json")
        let data = try Data(contentsOf: url)
        struct SourcesFile: Decodable {
            struct Source: Decodable { let id: String }
            let sources: [Source]
        }
        let citable = Set(try JSONDecoder().decode(SourcesFile.self, from: data)
            .sources.map(\.id))

        var sawACitation = false
        for body in DrillInstructions.auditableBodies {
            for id in DrillInstructions.citationIDs(in: body) {
                sawACitation = true
                XCTAssertTrue(citable.contains(id),
                              "drill copy cites '\(id)', which is not in sources.json")
            }
        }
        XCTAssertTrue(sawACitation, "drill safety copy should carry at least one citation")
    }

    func testNoTriangleOfLife() {
        for body in DrillInstructions.auditableBodies {
            XCTAssertFalse(body.lowercased().contains("triangle of life"), "Drill copy must never recommend the discredited Triangle of Life.")
            XCTAssertFalse(body.lowercased().contains("next to a desk"), "Drill copy must never recommend getting next to furniture instead of under it.")
            XCTAssertFalse(body.lowercased().contains("curling up next to"), "Drill copy must never recommend getting next to furniture instead of under it.")
        }
    }

    func testSafetyClaimCardsCarryCitationsAndNavCardsDoNot() {
        let start = DrillInstructions.card(for: .start(roomName: "Bedroom"), profileName: "Maya", peril: "fire")
        XCTAssertEqual(start.citations, ["nfpa-escape-planning"])

        let eqStart = DrillInstructions.card(for: .start(roomName: "Bedroom"), profileName: "Maya", peril: "earthquake")
        XCTAssertFalse(eqStart.citations.isEmpty, "Earthquake start card must make a cited safety claim")

        let torStart = DrillInstructions.card(for: .start(roomName: "Bedroom"), profileName: "Maya", peril: "tornado")
        XCTAssertFalse(torStart.citations.isEmpty, "Tornado start card must make a cited safety claim")

        let meeting = DrillInstructions.card(for: .drillComplete(peril: "fire"), profileName: "Maya", peril: "fire")
        XCTAssertFalse(meeting.citations.isEmpty)

        let stairs = DrillInstructions.card(for: .stairs(fromFloorID: "f1", toFloorID: "f0"),
                                            profileName: "Maya", peril: "fire")
        XCTAssertTrue(stairs.citations.isEmpty, "navigational copy makes no safety claim")
    }

    func testCitationParserFindsAndDedupesIDs() {
        let text = "Stay low. [cite: nfpa-escape-planning] Close doors. [cite: usfa-escape-plans] "
            + "Practice. [cite: nfpa-escape-planning]"
        XCTAssertEqual(DrillInstructions.citationIDs(in: text),
                       ["nfpa-escape-planning", "usfa-escape-plans"])
        XCTAssertEqual(DrillInstructions.citationIDs(in: "no tags here"), [])
    }
}

final class DrillPracticedStateTests: XCTestCase {

    /// "Mark plan as practiced" flips exactly the S3.5 scoring item `practice.drill_recent`
    /// in ChecklistStateStore; /score picks it up on ScoreScreen's next POST.
    func testMarkingPracticedPersistsAndLeavesOtherItemsAlone() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "s42-\(UUID().uuidString)"))
        let store = ChecklistStateStore(defaults: defaults)
        let homeID = "home-drill-test"

        store.save(["alarms.floor.f0": true, "practice.meeting_point": false], homeID: homeID)

        // What DrillScreen.markPracticed() does.
        var state = store.load(homeID: homeID)
        state["practice.drill_recent"] = true
        store.save(state, homeID: homeID)

        // A fresh store over the same defaults = relaunch.
        let reloaded = ChecklistStateStore(defaults: defaults).load(homeID: homeID)
        XCTAssertEqual(reloaded["practice.drill_recent"], true)
        XCTAssertEqual(reloaded["alarms.floor.f0"], true)
        XCTAssertEqual(reloaded["practice.meeting_point"], false)
        XCTAssertEqual(reloaded.count, 3)

        // Scoped per home: another home's state is untouched.
        XCTAssertTrue(ChecklistStateStore(defaults: defaults).load(homeID: "other").isEmpty)
    }
}
