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

    /// The engine's no-interior-room sentence, copied from backend/app/routing/engine.py.
    private static let noSafeRoomDetail = "No interior room could be reached from here. If you "
        + "are in a mobile or manufactured home, go now to a nearby sturdy building or "
        + "community shelter."

    private static let noRouteDetail = "No route to an exit could be found from this room."

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

    /// Every notice the builder can produce, for the sweep tests below.
    private func allNotices() throws -> [DrillNotice] {
        [
            DrillNotice.differentHome,
            DrillNotice.noPlan(profileName: "Sam"),
            DrillNotice.routeTooShort(profileName: "Sam"),
            try XCTUnwrap(DrillNotice.cannotStart(
                room: room(primary: false, findings: [("no_viable_safe_room", Self.noSafeRoomDetail, "redcross-tornado")]),
                profileName: "Sam", peril: "tornado")),
            try XCTUnwrap(DrillNotice.cannotStart(
                room: room(primary: false, findings: [("no_viable_route", Self.noRouteDetail, "nfpa-escape-planning")]),
                profileName: "Sam", peril: "fire")),
            try XCTUnwrap(DrillNotice.cannotStart(
                room: room(primary: false, findings: []), profileName: "Sam", peril: "earthquake")),
        ]
    }

    // MARK: AUD-025

    func testTornadoNoInteriorRoomShowsExactlyTheEngineText() throws {
        let notice = try XCTUnwrap(DrillNotice.cannotStart(
            room: room(primary: false, findings: [("no_viable_safe_room", Self.noSafeRoomDetail, "redcross-tornado")]),
            profileName: "Sam", peril: "tornado"))
        XCTAssertEqual(notice.text, Self.noSafeRoomDetail)
        XCTAssertEqual(notice.citations, ["redcross-tornado"])
    }

    func testTornadoFindingWinsEvenWhenAPrimaryRouteCameBack() throws {
        let notice = try XCTUnwrap(DrillNotice.cannotStart(
            room: room(primary: true, findings: [("no_viable_safe_room", Self.noSafeRoomDetail, "redcross-tornado")]),
            profileName: "Sam", peril: "tornado"))
        XCTAssertEqual(notice.text, Self.noSafeRoomDetail)
    }

    func testFindingWithoutCitationCarriesNoChips() throws {
        let notice = try XCTUnwrap(DrillNotice.cannotStart(
            room: room(primary: false, findings: [("no_viable_safe_room", Self.noSafeRoomDetail, nil)]),
            profileName: "Sam", peril: "tornado"))
        XCTAssertEqual(notice.text, Self.noSafeRoomDetail)
        XCTAssertEqual(notice.citations, [])
    }

    func testNoPrimaryRouteNamesTheProfileThenTheEngineFindingVerbatim() throws {
        let notice = try XCTUnwrap(DrillNotice.cannotStart(
            room: room(primary: false, findings: [("no_viable_route", Self.noRouteDetail, "nfpa-escape-planning")]),
            profileName: "Sam", peril: "fire"))
        XCTAssertEqual(notice.text, "No primary route for Sam. \(Self.noRouteDetail)")
        XCTAssertEqual(notice.citations, ["nfpa-escape-planning"])
    }

    func testWalkableRoomHasNoNotice() throws {
        let oneWayOut = try room(primary: true, findings: [("no_secondary_egress", "Only one way out.", nil)])
        XCTAssertNil(DrillNotice.cannotStart(room: oneWayOut, profileName: "Sam", peril: "fire"))
        let clear = try room(primary: true, findings: [])
        XCTAssertNil(DrillNotice.cannotStart(room: clear, profileName: "Sam", peril: "tornado"))
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
            for detail in [Self.noSafeRoomDetail, Self.noRouteDetail] {
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
