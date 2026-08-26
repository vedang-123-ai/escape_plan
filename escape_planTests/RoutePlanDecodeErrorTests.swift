//  RoutePlanDecodeErrorTests.swift
//  escape_planTests
//
//  The error side of the /routes contract — RoutePlanTests covers the happy paths and the
//  deliberately lenient keys (findings/bottlenecks/profile_id). These tests pin where the
//  leniency STOPS: everything else is required, unknown enum values throw, and
//  RoutingConstraints' defaulted memberwise init does not make its decoding lenient.
//  Decoded with HomeModel.decoder, the same decoder APIClient+Routes uses.

import XCTest
@testable import escape_plan

final class RoutePlanDecodeErrorTests: XCTestCase {

    private func decodePlan(_ json: String) throws -> RoutePlan {
        try HomeModel.decoder.decode(RoutePlan.self, from: Data(json.utf8))
    }

    /// v1.1 revamp: the engine now emits "path" waypoints (within-room curve
    /// points around objects) and "blocked_opening" findings — both must decode.
    func testV11PathWaypointAndBlockedOpeningFindingDecode() throws {
        let json = """
        {
          "home_id": "home-1",
          "home_name": "Bungalow",
          "constraints": { "avoid_stairs": false, "avoid_windows": false },
          "rooms": [
            {
              "room_id": "r_living",
              "room_name": "Living Room",
              "floor_id": "f1",
              "primary": {
                "waypoints": [
                  { "x": 1.0, "y": 2.0, "floor_id": "f1", "node_id": "r_living", "kind": "room" },
                  { "x": 1.6, "y": 1.2, "floor_id": "f1", "node_id": "d_front", "kind": "path" },
                  { "x": 2.5, "y": 0.0, "floor_id": "f1", "node_id": "d_front", "kind": "opening" },
                  { "x": 2.5, "y": 0.0, "floor_id": "f1", "node_id": "EXTERIOR", "kind": "exterior" }
                ],
                "length_m": 3.1,
                "uses_stairs": false,
                "uses_window": false,
                "exit_id": "d_front"
              },
              "findings": [
                { "kind": "blocked_opening", "room_id": "r_living",
                  "detail": "Opening 'd_side' can't be reached from inside 'Living Room'." }
              ]
            }
          ]
        }
        """
        let plan = try decodePlan(json)
        let room = try XCTUnwrap(plan.rooms.first)
        XCTAssertEqual(room.primary?.waypoints[1].kind, .path)
        XCTAssertEqual(room.findings.first?.kind, .blocked_opening)
    }

    /// A minimal valid plan; tests mutate one aspect at a time.
    private let minimalPlan = """
    {
      "home_id": "home-1",
      "home_name": "Bungalow",
      "constraints": { "avoid_stairs": false, "avoid_windows": false },
      "rooms": []
    }
    """

    private let route = """
    {
      "waypoints": [
        { "x": 1.0, "y": 2.0, "floor_id": "f1", "node_id": "room:r_living", "kind": "room" },
        { "x": 2.5, "y": 2.0, "floor_id": "f1", "node_id": "opening:d_front", "kind": "opening" },
        { "x": 3.0, "y": 2.0, "floor_id": "f1", "node_id": "EXTERIOR", "kind": "exterior" }
      ],
      "length_m": 2.0,
      "uses_stairs": false,
      "uses_window": false,
      "exit_id": "d_front"
    }
    """

    private func planWithRoute(_ routeJSON: String) -> String {
        """
        {
          "home_id": "home-1",
          "home_name": "Bungalow",
          "constraints": { "avoid_stairs": false, "avoid_windows": false },
          "rooms": [
            {
              "room_id": "r_living",
              "room_name": "Living Room",
              "floor_id": "f1",
              "primary": \(routeJSON)
            }
          ]
        }
        """
    }

    // MARK: - Baseline: the minimal payloads used below are actually valid

    func testMinimalPlanAndRouteDecode() throws {
        _ = try decodePlan(minimalPlan)
        let plan = try decodePlan(planWithRoute(route))
        XCTAssertEqual(plan.rooms.first?.primary?.waypoints.count, 3)
    }

    // MARK: - Malformed data

    func testGarbageAndTruncatedDataThrow() {
        XCTAssertThrowsError(try decodePlan("not json at all"))
        XCTAssertThrowsError(try decodePlan(String(minimalPlan.dropLast(20))),
                             "a connection cut mid-body must surface as a decode error, not a partial plan")
    }

    // MARK: - Required keys (the leniency boundary)

    func testMissingRequiredTopLevelKeyThrows() {
        let noHomeId = minimalPlan.replacingOccurrences(of: #""home_id": "home-1","#, with: "")
        XCTAssertThrowsError(try decodePlan(noHomeId), "home_id has no default")

        let noRooms = minimalPlan.replacingOccurrences(of: #","rooms": []"#, with: "")
            .replacingOccurrences(of: #""rooms": []"#, with: "")
        XCTAssertThrowsError(try decodePlan(noRooms),
                             "rooms is required — only findings/bottlenecks/profile_id are lenient")
    }

    func testMissingRouteExitIdThrows() {
        let noExit = planWithRoute(route.replacingOccurrences(of: #","exit_id": "d_front""#, with: "")
            .replacingOccurrences(of: #""exit_id": "d_front""#, with: ""))
        XCTAssertThrowsError(try decodePlan(noExit), "Route has no lenient keys at all")
    }

    func testConstraintsDecodingRequiresTheBoolKeys() {
        // RoutingConstraints(avoid_stairs: ...) has defaults, but they are init-only sugar:
        // decoding is synthesized and still requires both bools. Pinned on purpose — if this
        // ever needs to change (backend omitting the bools), it's a decision, not a drift.
        let emptyConstraints = minimalPlan.replacingOccurrences(
            of: #"{ "avoid_stairs": false, "avoid_windows": false }"#, with: "{}")
        XCTAssertThrowsError(try decodePlan(emptyConstraints))
    }

    // MARK: - Enum strictness

    /// Same reasoning as the finding-kind case: waypoints are nested inside the plan, so
    /// throwing costs every route. The waypoint keeps its coordinates either way, so the
    /// leg still draws — only kind-specific decoration is lost.
    func testUnknownWaypointKindDegradesInsteadOfKillingThePlan() throws {
        let badKind = planWithRoute(route.replacingOccurrences(of: #""kind": "room""#,
                                                               with: #""kind": "teleporter""#))
        let decoded = try decodePlan(badKind)
        let kinds = decoded.rooms.flatMap { $0.primary?.waypoints ?? [] }.map(\.kind)
        XCTAssertTrue(kinds.contains(.unknown), "the teleporter waypoint should decode as .unknown")
        XCTAssertFalse(kinds.isEmpty, "the route's waypoints must survive")
    }

    /// A finding kind newer than this build must NOT cost the whole plan. Findings are
    /// nested inside RoutePlan, so throwing here means zero routes render — strictly worse
    /// than one generically-labelled badge. This stopped being hypothetical the day
    /// `narrows_route` shipped server-side: builds predating it took this path and still
    /// rendered their routes. The sample kind below must stay one the engine does NOT
    /// emit, or this test silently stops testing anything.
    func testUnknownFindingKindDegradesInsteadOfKillingThePlan() throws {
        let plan = """
        {
          "home_id": "home-1",
          "home_name": "Bungalow",
          "constraints": { "avoid_stairs": false, "avoid_windows": false },
          "rooms": [
            {
              "room_id": "r_living",
              "room_name": "Living Room",
              "floor_id": "f1",
              "findings": [
                { "kind": "smoke_logged_stairwell", "room_id": "r_living",
                  "detail": "The path to 'd_entry' squeezes to 0.62 m past the sofa." }
              ]
            }
          ]
        }
        """
        let decoded = try decodePlan(plan)
        XCTAssertEqual(decoded.rooms.count, 1, "the plan itself must still decode")
        XCTAssertEqual(decoded.rooms[0].findings[0].kind, .unknown)
        // The engine's prose is what the user actually reads — it must survive intact.
        XCTAssertTrue(decoded.rooms[0].findings[0].detail.contains("0.62 m"))
    }

    // MARK: - narrows_route (2026-08-25)

    /// The engine computed narrowings from the B3 revamp onward and nothing rendered
    /// them. Now that it emits them, the kind must decode as ITSELF — landing in
    /// `.unknown` would still render, which is exactly why the gap survived so long.
    func testNarrowsRouteDecodesAsItsOwnKindNotUnknown() throws {
        let plan = """
        {
          "home_id": "home-1",
          "home_name": "Bungalow",
          "constraints": { "avoid_stairs": false, "avoid_windows": false },
          "rooms": [
            {
              "room_id": "r_bedroom",
              "room_name": "Bedroom",
              "floor_id": "f1",
              "findings": [
                { "kind": "narrows_route", "room_id": "r_bedroom",
                  "detail": "The path squeezes to 0.90 m past the wardrobe.",
                  "object_ids": ["o_wardrobe_narrowing"] }
              ]
            }
          ]
        }
        """
        let finding = try decodePlan(plan).rooms[0].findings[0]
        XCTAssertEqual(finding.kind, .narrows_route)
        XCTAssertEqual(finding.object_ids, ["o_wardrobe_narrowing"])
    }

    /// A squeeze is the mildest thing the engine reports. Giving it the severe tint —
    /// the one `no_viable_route` uses — would overstate the engine's own answer with
    /// presentation, which is the one thing this layer must never do.
    func testNarrowsRouteIsNotStyledAsSevere() {
        let squeeze = RouteFindingStyle.of(.narrows_route)
        let severe = RouteFindingStyle.of(.no_viable_route)
        XCTAssertNotEqual(squeeze.title, severe.title)
        XCTAssertNotEqual(squeeze.tint, severe.tint)
        XCTAssertEqual(squeeze.tint, RouteFindingStyle.of(.blocked_opening).tint,
                       "no new colour: it shares the existing non-severe tier")
    }

    /// The exported plan is read aloud by VoiceOver and printed in the PDF, so the
    /// distinction has to survive into prose, not just into a badge colour.
    func testNarrowsRouteNarratesAsPassableRatherThanBlocked() throws {
        let home = try FixtureLoader.load(.bungalow)
        let finding = RouteFinding(kind: .narrows_route,
                                   room_id: home.floors[0].rooms[0].id,
                                   detail: "The path squeezes to 0.90 m past the wardrobe.",
                                   object_ids: [])
        let sentence = RouteNarration.findingSentence(finding, in: home)
        XCTAssertTrue(sentence.contains("passable but tight"))
        XCTAssertTrue(sentence.contains(finding.detail),
                      "the engine's wording must survive verbatim")
        XCTAssertFalse(sentence.contains("is blocked"))
    }

    // MARK: - Type mismatches

    func testWrongTypeForLengthThrows() {
        let stringLength = planWithRoute(route.replacingOccurrences(of: #""length_m": 2.0"#,
                                                                    with: #""length_m": "2.0""#))
        XCTAssertThrowsError(try decodePlan(stringLength))
    }
}
