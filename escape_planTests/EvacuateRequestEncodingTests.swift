//  EvacuateRequestEncodingTests.swift — the POST /evacuate wire contract from the client side
//  (pattern: BuildRequestEncodingTests, ChatRequestEncodingTests).
//
//  App-target only, because it touches Networking/ — the SwiftPM editorcore package compiles
//  Models/ and Editor/Core/ only. The timeline decode and playback clock live in
//  escape_planTests/EditorCore/PlaybackModelTests.swift, which both runners compile.

import XCTest
@testable import escape_plan

final class EvacuateRequestEncodingTests: XCTestCase {

    private func encodedJSON(_ request: EvacuateRequest) throws -> [String: Any] {
        let data = try HomeModel.encoder().encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRequestEncodesHomeAndOriginRoom() throws {
        let home = try Fixtures.load("bungalow")
        let roomID = try XCTUnwrap(home.floors.first?.rooms.first?.id)
        let json = try encodedJSON(EvacuateRequest(home: home,
                                                   origin_room_id: roomID,
                                                   profile_set_id: nil))

        XCTAssertEqual(json["origin_room_id"] as? String, roomID)
        let encodedHome = try XCTUnwrap(json["home"] as? [String: Any])
        XCTAssertEqual(encodedHome["home_id"] as? String, home.home_id)
    }

    /// nil is omitted rather than sent as an explicit null, matching RoutesRequest — a backend
    /// that forbids extra/unknown-shaped keys must not see `"profile_set_id": null`.
    func testNilProfileSetIDIsOmittedEntirely() throws {
        let home = try Fixtures.load("bungalow")
        let json = try encodedJSON(EvacuateRequest(home: home,
                                                   origin_room_id: "r1",
                                                   profile_set_id: nil))
        XCTAssertFalse(json.keys.contains("profile_set_id"))
    }

    func testProfileSetIDIsSentWhenPresent() throws {
        let home = try Fixtures.load("bungalow")
        let json = try encodedJSON(EvacuateRequest(home: home,
                                                   origin_room_id: "r1",
                                                   profile_set_id: "ps-7"))
        XCTAssertEqual(json["profile_set_id"] as? String, "ps-7")
    }

    /// The request carries exactly the three documented keys — no client-invented extras that
    /// a strict backend would 422 on.
    func testRequestCarriesNoUndocumentedKeys() throws {
        let home = try Fixtures.load("bungalow")
        let json = try encodedJSON(EvacuateRequest(home: home,
                                                   origin_room_id: "r1",
                                                   profile_set_id: "ps-7"))
        XCTAssertEqual(Set(json.keys), ["home", "origin_room_id", "profile_set_id"])
    }
}
