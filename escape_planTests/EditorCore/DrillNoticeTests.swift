//  DrillNoticeTests.swift — the drill's "cannot start" notices (AUD-025).
//
//  The drill once appended its own tornado advice to the engine's no-interior-room finding,
//  advice the engine reserves for mobile and manufactured homes, with a raw cite tag. These
//  tests pin the rule that replaced it: a notice is the engine's words verbatim plus the
//  engine's citation id, or status copy that makes no safety judgment.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class DrillNoticeTests: XCTestCase {

    // The engine's own sentences, copied from backend/app/routing/engine.py (room "Bedroom").
    private static let noSafeRoomDetail = "No interior room could be reached from here. If you "
        + "are in a mobile or manufactured home, go now to a nearby sturdy building or "
        + "community shelter."

    private static let noRouteDetail = "No viable escape route from 'Bedroom' under the current constraints."
    private static let noCoverDetail = "No cover in this room — drop to the ground and cover your head and neck "
        + "with your arms."

    private func room(primary: Bool, findings: [(kind: String, detail: String, citation: String?)])
        throws -> RoomRoutePlan {
        let findingsJSON = findings.map { finding -> [String: Any] in
            var json: [String: Any] = ["kind": finding.kind, "room_id": "bed", "detail": finding.detail]
            if let citation = finding.citation { json["citation"] = citation }
            return json
        }
        var json: [String: Any] = ["room_id": "bed", "room_name": "Bedroom", "floor_id": "f1",
                                   "findings": findingsJSON]
        if primary {
            json["primary"] = [
                "waypoints": [
                    ["x": 0, "y": 0, "floor_id": "f1", "node_id": "bed", "kind": "room"],
                    ["x": 1, "y": 0, "floor_id": "f1", "node_id": "EXTERIOR", "kind": "exterior"],
                ],
                "length_m": 1.0, "uses_stairs": false, "uses_window": false, "exit_id": "d1",
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(RoomRoutePlan.self, from: data)
    }

    private func notice(_ room: RoomRoutePlan, peril: String) throws -> DrillNotice {
        guard case .notice(let notice) = DrillNotice.start(room: room, profileName: "Sam", peril: peril) else {
            XCTFail("expected a notice, got a walk")
            throw CancellationError()
        }
        return notice
    }

    /// Every notice the builder can produce, for the sweep tests below.
    private func allNotices() throws -> [DrillNotice] {
        [
            DrillNotice.differentHome,
            DrillNotice.noPlan(profileName: "Sam"),
            DrillNotice.routeTooShort(profileName: "Sam"),
            try notice(room(primary: false, findings: [("no_viable_safe_room", Self.noSafeRoomDetail, "redcross-tornado")]),
                       peril: "tornado"),
            try notice(room(primary: false, findings: [("no_viable_route", Self.noRouteDetail, nil)]), peril: "fire"),
            try notice(room(primary: false, findings: [("no_cover_in_room", Self.noCoverDetail, "shakeout-guidance-dcho"),
                                                       ("no_viable_route", Self.noRouteDetail, nil)]),
                       peril: "earthquake"),
            try notice(room(primary: false, findings: []), peril: "earthquake"),
        ]
    }

    // MARK: AUD-025

    func testTornadoNoInteriorRoomShowsExactlyTheEngineText() throws {
        let notice = try notice(room(primary: false, findings: [("no_viable_safe_room", Self.noSafeRoomDetail, "redcross-tornado")]),
                                peril: "tornado")
        XCTAssertEqual(notice.text, Self.noSafeRoomDetail)
        XCTAssertEqual(notice.citations, ["redcross-tornado"])
    }

    func testTornadoFindingWinsEvenWhenAPrimaryRouteCameBack() throws {
        let notice = try notice(room(primary: true, findings: [("no_viable_safe_room", Self.noSafeRoomDetail, "redcross-tornado")]),
                                peril: "tornado")
        XCTAssertEqual(notice.text, Self.noSafeRoomDetail)
    }

    func testFindingWithoutCitationCarriesNoChips() throws {
        let notice = try notice(room(primary: false, findings: [("no_viable_safe_room", Self.noSafeRoomDetail, nil)]),
                                peril: "tornado")
        XCTAssertEqual(notice.text, Self.noSafeRoomDetail)
        XCTAssertEqual(notice.citations, [])
    }

    func testNoPrimaryRouteNamesTheProfileThenTheEngineFindingVerbatim() throws {
        let notice = try notice(room(primary: false, findings: [("no_viable_route", Self.noRouteDetail, nil)]),
                                peril: "fire")
        XCTAssertEqual(notice.text, "No primary route for Sam. \(Self.noRouteDetail)")
        XCTAssertEqual(notice.citations, [])
    }

    /// The engine lists the earthquake no-cover finding before no_viable_route; the notice must
    /// give the reason there is no route, not the cover advice.
    func testNoPrimaryRoutePrefersTheFindingThatExplainsIt() throws {
        let notice = try notice(room(primary: false, findings: [("no_cover_in_room", Self.noCoverDetail, "shakeout-guidance-dcho"),
                                                                ("no_viable_route", Self.noRouteDetail, nil)]),
                                peril: "earthquake")
        XCTAssertEqual(notice.text, "No primary route for Sam. \(Self.noRouteDetail)")
    }

    func testOtherwiseABlockedDoorwayExplainsIt() throws {
        let blocked = "Doorway blocked."
        let notice = try notice(room(primary: false, findings: [("no_secondary_egress", "Only one way out.", nil),
                                                                ("blocked_opening", blocked, "usfa-escape-plans")]),
                                peril: "fire")
        XCTAssertEqual(notice.text, "No primary route for Sam. \(blocked)")
        XCTAssertEqual(notice.citations, ["usfa-escape-plans"])
    }

    func testWalkableRoomHasNoNotice() throws {
        let oneWayOut = try room(primary: true, findings: [("no_secondary_egress", "Only one way out.", nil)])
        XCTAssertEqual(DrillNotice.start(room: oneWayOut, profileName: "Sam", peril: "fire"),
                       .walk(try XCTUnwrap(oneWayOut.primary)))
        let clear = try room(primary: true, findings: [])
        XCTAssertEqual(DrillNotice.start(room: clear, profileName: "Sam", peril: "tornado"),
                       .walk(try XCTUnwrap(clear.primary)))
    }

    // MARK: Sweep

    /// What is left of a notice once the engine's own words are removed must be one of the
    /// status lines below, none of which tells anyone what to do in an emergency.
    func testNoNoticeContainsSafetyTextOutsideTheEngineFinding() throws {
        let statusCopy: Set<String> = [
            "",
            "The saved plan is for a different home — try again online.",
            "The engine returned no plan for Sam's bedroom.",
            "The route for Sam is too short to walk through.",
            "No primary route for Sam.",
        ]
        for notice in try allNotices() {
            var rest = notice.text
            for detail in [Self.noSafeRoomDetail, Self.noRouteDetail, Self.noCoverDetail] {
                rest = rest.replacingOccurrences(of: detail, with: "")
            }
            rest = rest.trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(statusCopy.contains(rest), "Unexpected notice copy: \(rest)")
        }
    }

    func testNoNoticeShowsARawCiteTag() throws {
        for notice in try allNotices() {
            XCTAssertFalse(notice.text.contains("[cite:"), notice.text)
        }
    }

    func testTheClientTornadoSentenceIsGone() throws {
        for notice in try allNotices() {
            XCTAssertFalse(notice.text.contains("Leave immediately"), notice.text)
        }
    }
}
