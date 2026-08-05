//  RouteNarrationTests.swift
//  escape_planTests — printable escape plan (Export/)
//
//  `RouteNarration` is the shared step-sentence generator: the PDF's per-person summary and
//  the 3D scene's VoiceOver description both come from it. These tests pin the contract other
//  lanes will bind to — step numbering, the engine-only rule, and the invariant that a drawn
//  marker and a spoken step always carry the same number.

import Foundation
import Testing

@testable import escape_plan

@Suite("RouteNarration")
struct RouteNarrationTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // escape_planTests/
        .deletingLastPathComponent()   // repo root

    static func routeSample(_ name: String) throws -> RoutePlan {
        let url = repoRoot.appendingPathComponent("docs/route-samples/\(name).routeplan.json")
        return try HomeModel.decoder.decode(RoutePlan.self, from: Data(contentsOf: url))
    }

    // MARK: - Steps

    @Test("A ground-floor route becomes ordered plain-English steps that name real rooms")
    func groundFloorSteps() throws {
        let home = try FixtureLoader.load(.twostory)
        let plan = try Self.routeSample("twostory")
        let hall = try #require(plan.rooms.first { $0.room_id == "r_hall1" })

        let narrative = try #require(
            RouteNarration.narrate(room: hall, in: home, kind: .primary))

        #expect(narrative.roomName == "Entry Hall")
        #expect(narrative.kind == .primary)
        #expect(!narrative.steps.isEmpty)
        #expect(narrative.steps.map(\.number) == Array(1...narrative.steps.count))
        // The exit door step must mention the room it leaves and that it reaches outside.
        let joined = narrative.steps.map(\.text).joined(separator: " ")
        #expect(joined.contains("Entry Hall"))
        #expect(joined.lowercased().contains("outside"))
        #expect(narrative.summary.contains("4.0 m"))
    }

    @Test("A floor crossing is one step that names the direction and the destination floor")
    func stairsStep() throws {
        let home = try FixtureLoader.load(.twostory)
        let plan = try Self.routeSample("twostory")
        let upstairs = try #require(plan.rooms.first {
            $0.floor_id != "f1" && $0.primary?.uses_stairs == true
        })
        let narrative = try #require(
            RouteNarration.narrate(room: upstairs, in: home, kind: .primary))

        let stairStep = try #require(narrative.steps.first { $0.text.contains("stairs") })
        #expect(stairStep.text.contains("down"))
        // The engine emits two stair waypoints for one crossing; that must be ONE instruction.
        let stairSteps = narrative.steps.filter { $0.text.contains("stairs") }
        #expect(stairSteps.count == 1)
        #expect(narrative.summary.contains("uses the stairs"))
    }

    @Test("The meeting point is appended only when the user supplied one")
    func meetingPointStep() throws {
        let home = try FixtureLoader.load(.twostory)
        let plan = try Self.routeSample("twostory")
        let hall = try #require(plan.rooms.first { $0.room_id == "r_hall1" })

        let without = try #require(RouteNarration.narrate(room: hall, in: home, kind: .primary))
        let with = try #require(RouteNarration.narrate(room: hall, in: home, kind: .primary,
                                                       meetingPoint: "the big oak across the street"))
        #expect(with.steps.count == without.steps.count + 1)
        #expect(with.steps.last?.text == "Go to your meeting point: the big oak across the street.")

        let blank = try #require(RouteNarration.narrate(room: hall, in: home, kind: .primary,
                                                        meetingPoint: "   "))
        #expect(blank.steps.count == without.steps.count)
    }

    @Test("A route the engine did not compute produces no narrative at all")
    func noInventedRoutes() throws {
        let home = try FixtureLoader.load(.apartment)
        let plan = try Self.routeSample("apartment")
        let room = try #require(plan.rooms.first)

        #expect(room.secondary == nil, "the apartment fixture is single-exit on purpose")
        #expect(RouteNarration.narrate(room: room, in: home, kind: .secondary) == nil)
        #expect(RouteNarration.narrate(room: room, in: home, kind: .primary) != nil)
    }

    @Test("Findings are turned into sentences that quote the engine's own detail")
    func findingSentences() throws {
        let home = try FixtureLoader.load(.apartment)
        let plan = try Self.routeSample("apartment")
        let finding = try #require(plan.rooms.flatMap(\.findings)
            .first { $0.kind == .no_secondary_egress })

        let sentence = RouteNarration.findingSentence(finding, in: home)
        #expect(sentence.contains("no second way out"))
        #expect(sentence.contains(finding.detail), "the engine's wording must survive verbatim")
    }

    // MARK: - Markers ↔ steps

    @Test("Every numbered step has exactly one anchor waypoint, in the same order")
    func stepAnchorsMatchSteps() throws {
        let home = try FixtureLoader.load(.twostory)
        let plan = try Self.routeSample("twostory")

        for room in plan.rooms {
            for kind in [RouteKind.primary, .secondary] {
                let route: Route? = kind == .primary ? room.primary : room.secondary
                guard let route,
                      let narrative = RouteNarration.narrate(room: room, in: home, kind: kind)
                else { continue }
                let anchors = RouteNarration.stepAnchors(for: route, startingIn: room.room_id)
                #expect(anchors.count == narrative.steps.count,
                        "\(room.room_id)/\(kind): a printed marker for every spoken step")
                #expect(anchors.map(\.number) == narrative.steps.map(\.number))
            }
        }
    }

    @Test("Adding a meeting point does not shift the numbers printed on the drawing")
    func meetingPointDoesNotRenumberMarkers() throws {
        let home = try FixtureLoader.load(.twostory)
        let plan = try Self.routeSample("twostory")
        let room = try #require(plan.rooms.first { $0.primary != nil })
        let route = try #require(room.primary)

        let anchors = RouteNarration.stepAnchors(for: route, startingIn: room.room_id)
        let narrative = try #require(RouteNarration.narrate(room: room, in: home, kind: .primary,
                                                            meetingPoint: "the mailbox"))
        for anchor in anchors {
            let step = try #require(narrative.steps.first { $0.number == anchor.number })
            #expect(!step.text.contains("meeting point"),
                    "the meeting-point step is off the drawing and must come last")
        }
        #expect(narrative.steps.count == anchors.count + 1)
    }

    @Test("`.path` waypoints round furniture are never instructions of their own")
    func pathWaypointsAreNotSteps() {
        let waypoints = [
            Waypoint(x: 0, y: 0, floor_id: "f1", node_id: "r1", kind: .room),
            Waypoint(x: 1, y: 0, floor_id: "f1", node_id: "d1", kind: .path),
            Waypoint(x: 2, y: 0, floor_id: "f1", node_id: "d1", kind: .path),
            Waypoint(x: 3, y: 0, floor_id: "f1", node_id: "d1", kind: .opening),
            Waypoint(x: 3, y: 0, floor_id: "f1", node_id: "EXTERIOR", kind: .exterior),
        ]
        let events = RouteNarration.events(in: waypoints, startingIn: "r1")
        #expect(events.count == 1, "one doorway = one step, however many curve points precede it")
    }

    // MARK: - VoiceOver

    @Test("The spoken description covers both routes and the engine's warnings")
    func spokenDescription() throws {
        let home = try FixtureLoader.load(.apartment)
        let plan = try Self.routeSample("apartment")
        let room = try #require(plan.rooms.first)

        let spoken = RouteNarration.spokenDescription(room: room, in: home)
        #expect(spoken.contains("Primary route"))
        #expect(spoken.contains("Hallway"), "the room is named, not just referenced by id")
        #expect(spoken.contains("no second way out"),
                "a screen-reader user must hear the engine's warning, not just see a badge")
        #expect(!spoken.contains("Backup route"),
                "this room has no secondary — nothing may be spoken as if it did")
    }
}
