//  ScoreModelsTests.swift
//  escape_planTests
//
//  S3.5 /score contract on the client: ScoreBreakdown decoding (via HomeModel.decoder, the
//  same decoder APIClient+Score uses) and ScoreRequest encoding. ScoreModels is deliberately
//  strict — unlike RoutePlan there is no lenient defaulting, because the backend always sends
//  the full breakdown; these tests pin that contract so a silent backend field rename fails
//  loudly here instead of as a blank Score screen.

import XCTest
@testable import escape_plan

final class ScoreModelsTests: XCTestCase {

    // MARK: - Payload helpers

    private func componentJSON(key: String = "smoke_alarms") -> String {
        """
        {
          "key": "\(key)",
          "label": "Smoke alarms",
          "earned_points": 7.5,
          "max_points": 15,
          "detail": "1 of 2 alarm items done",
          "rationale": "Working alarms halve the risk of dying in a fire [cite: nfpa-alarms]."
        }
        """
    }

    private func itemJSON(id: String = "alarm.every_level",
                          category: String = "smoke_alarm",
                          extra: String = "") -> String {
        """
        {
          "id": "\(id)",
          "category": "\(category)",
          "title": "Alarm on every level",
          "detail": "Install at least one smoke alarm per floor.",
          "done": false,
          "scoring": true\(extra)
        }
        """
    }

    private func breakdownJSON(components: [String]? = nil,
                               checklist: [String]? = nil,
                               scoreLine: String = #""score": 75,"#) -> Data {
        let componentList = (components ?? [componentJSON()]).joined(separator: ",")
        let checklistList = (checklist ?? [itemJSON()]).joined(separator: ",")
        return Data("""
        {
          "home_id": "home-1",
          "home_name": "Twostory",
          \(scoreLine)
          "components": [\(componentList)],
          "checklist": [\(checklistList)]
        }
        """.utf8)
    }

    private func decodeBreakdown(_ data: Data) throws -> ScoreBreakdown {
        try HomeModel.decoder.decode(ScoreBreakdown.self, from: data)
    }

    // MARK: - Decoding

    func testFullBreakdownDecodes() throws {
        let breakdown = try decodeBreakdown(breakdownJSON())

        XCTAssertEqual(breakdown.home_id, "home-1")
        XCTAssertEqual(breakdown.home_name, "Twostory")
        XCTAssertEqual(breakdown.score, 75)

        let component = try XCTUnwrap(breakdown.components.first)
        XCTAssertEqual(component.key, "smoke_alarms")
        XCTAssertEqual(component.earned_points, 7.5)
        XCTAssertEqual(component.max_points, 15)

        let item = try XCTUnwrap(breakdown.checklist.first)
        XCTAssertEqual(item.category, .smoke_alarm)
        XCTAssertFalse(item.done)
        XCTAssertTrue(item.scoring)
    }

    func testChecklistItemOptionalFieldsDefaultToNil() throws {
        let bare = try decodeBreakdown(breakdownJSON())
        let item = try XCTUnwrap(bare.checklist.first)
        XCTAssertNil(item.source_citation, "missing source_citation must decode, as nil")
        XCTAssertNil(item.component, "missing component must decode, as nil")

        let annotated = try decodeBreakdown(breakdownJSON(checklist: [itemJSON(
            extra: #", "source_citation": "nfpa-alarms", "component": "smoke_alarms""#)]))
        let full = try XCTUnwrap(annotated.checklist.first)
        XCTAssertEqual(full.source_citation, "nfpa-alarms")
        XCTAssertEqual(full.component, "smoke_alarms")
    }

    func testEveryChecklistCategoryDecodes() throws {
        let categories = ["smoke_alarm", "practice", "routes", "agent_finding", "recommendation"]
        let breakdown = try decodeBreakdown(breakdownJSON(
            checklist: categories.enumerated().map { itemJSON(id: "item.\($0.offset)", category: $0.element) }))
        XCTAssertEqual(breakdown.checklist.map(\.category),
                       [.smoke_alarm, .practice, .routes, .agent_finding, .recommendation])
    }

    // MARK: - Strictness (deliberate contrast with RoutePlan's lenient keys)

    func testMissingScoreThrows() {
        XCTAssertThrowsError(try decodeBreakdown(breakdownJSON(scoreLine: "")),
                             "ScoreBreakdown has no lenient defaults — a missing score is a contract break")
    }

    func testUnknownChecklistCategoryThrows() {
        XCTAssertThrowsError(
            try decodeBreakdown(breakdownJSON(checklist: [itemJSON(category: "earthquake")])),
            "an unknown category means the backend contract moved — fail loudly, don't skip the row")
    }

    func testMissingRequiredComponentFieldThrows() {
        let truncated = """
        { "key": "practice", "label": "Practice", "earned_points": 5, "max_points": 10 }
        """
        XCTAssertThrowsError(try decodeBreakdown(breakdownJSON(components: [truncated])))
    }

    // MARK: - Identity

    func testScoreComponentIdIsItsKey() throws {
        let breakdown = try decodeBreakdown(breakdownJSON())
        let component = try XCTUnwrap(breakdown.components.first)
        XCTAssertEqual(component.id, component.key)
    }

    // MARK: - Request encoding

    func testScoreRequestEncodesExactlyHomeAndChecklistState() throws {
        let home = try FixtureLoader.load(.twostory)
        let request = ScoreRequest(home: home, checklist_state: ["alarm.every_level": true])

        let data = try HomeModel.encoder().encode(request)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["home", "checklist_state"],
                       "the backend defaults everything else; extra keys are not part of the v1 request")
        let state = try XCTUnwrap(object["checklist_state"] as? [String: Bool])
        XCTAssertEqual(state, ["alarm.every_level": true])
    }
}
