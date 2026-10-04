//  ScoreModelsTests.swift
//  escape_planTests
//
//  S3.5 /score contract on the client: ScoreBreakdown decoding (via HomeModel.decoder, the
//  same decoder APIClient+Score uses) and ScoreRequest encoding.
//
//  ScoreModels stays strict about STRUCTURE — unlike RoutePlan there is no lenient defaulting
//  for missing fields, because the backend always sends the full breakdown, and a field that
//  vanished is a contract break worth failing on.
//
//  It is deliberately NOT strict about enum VALUES, and the distinction cost us a broken demo
//  screen. "Fail loudly on an unknown category" sounds like the same discipline, but a test
//  suite can't fail on a category that doesn't exist yet — only the user's app can, at
//  runtime, by refusing to show the Score screen at all. That is what happened when the
//  backend started emitting `egress` on 2026-07-27 (apartment + twostory, i.e. the demo home)
//  and nobody noticed until 2026-08-02. Strict about what the backend PROMISED; tolerant
//  about what it later ADDED.

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
          "sub_scores": {"fire": 75, "earthquake": 75, "severe_weather": 75},
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
        // `egress` is here because its absence broke the Score screen outright between
        // 2026-07-27 and 2026-08-02 — see the enum's doc comment.
        let categories = ["smoke_alarm", "practice", "routes", "egress",
                          "agent_finding", "recommendation", "shutoffs",
                          "safe_room", "mitigation", "supply_kit", "alerts"]
        let breakdown = try decodeBreakdown(breakdownJSON(
            checklist: categories.enumerated().map { itemJSON(id: "item.\($0.offset)", category: $0.element) }))
        XCTAssertEqual(breakdown.checklist.map(\.category),
                       [.smoke_alarm, .practice, .routes, .egress,
                        .agent_finding, .recommendation, .shutoffs,
                        .safe_room, .mitigation, .supply_kit, .alerts])
    }

    /// The regression guard. A category this build has never heard of must cost one row's
    /// label, not the whole screen — the failure mode was "Couldn't get your score" on two
    /// of three fixtures, including the demo home.
    func testUnknownChecklistCategoryFallsBackInsteadOfFailingTheScreen() throws {
        let breakdown = try decodeBreakdown(breakdownJSON(checklist: [
            itemJSON(id: "known", category: "smoke_alarm"),
            itemJSON(id: "from.the.future", category: "future_hazard"),
        ]))
        XCTAssertEqual(breakdown.checklist.count, 2, "the whole breakdown must still decode")
        XCTAssertEqual(breakdown.checklist[1].category, .other)
        // …and the row is still readable: only the category degraded.
        XCTAssertEqual(breakdown.checklist[1].id, "from.the.future")
    }

    func testSeverityDecodesTolerantly() throws {
        let defaultItem = try decodeBreakdown(breakdownJSON(checklist: [
            itemJSON(id: "item", category: "agent_finding")
        ]))
        XCTAssertEqual(defaultItem.checklist[0].severity, .info, "omitted severity defaults to .info")
        
        let highItem = try decodeBreakdown(breakdownJSON(checklist: [
            itemJSON(id: "item", category: "agent_finding", extra: #", "severity": "high""#)
        ]))
        XCTAssertEqual(highItem.checklist[0].severity, .high)
        
        let unknownItem = try decodeBreakdown(breakdownJSON(checklist: [
            itemJSON(id: "item", category: "agent_finding", extra: #", "severity": "critical""#)
        ]))
        XCTAssertEqual(unknownItem.checklist[0].severity, .info, "unknown severity falls back to .info")
    }



    // MARK: - Strictness (deliberate contrast with RoutePlan's lenient keys)

    func testMissingScoreThrows() {
        XCTAssertThrowsError(try decodeBreakdown(breakdownJSON(scoreLine: "")),
                             "ScoreBreakdown has no lenient defaults — a missing score is a contract break")
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

    // MARK: - S11.35: recurrence (the S11.34 contract)

    /// The server 422s the whole request on a string it cannot parse, so pin the exact text:
    /// UTC, `Z`, whole seconds.
    func testCompletedMarkEncodesAsExactISO8601UTCString() throws {
        let home = try FixtureLoader.load(.twostory)
        // 2026-10-04 12:34:56.789 UTC; the fraction must not reach the wire.
        let completed = Date(timeIntervalSince1970: 1_791_117_296.789)
        let request = ScoreRequest(home: home, checklist_state: [
            "practice.drill_recent": .completed(completed),
            "alarm.every_level": true,
            "practice.meeting_point": .flag(false),
        ])

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: HomeModel.encoder().encode(request))
                                   as? [String: Any])
        let state = try XCTUnwrap(object["checklist_state"] as? [String: Any])
        XCTAssertEqual(state["practice.drill_recent"] as? String, "2026-10-04T12:34:56Z")
        XCTAssertEqual(state["alarm.every_level"] as? Bool, true)
        XCTAssertEqual(state["practice.meeting_point"] as? Bool, false)
    }

    func testRecurrenceFieldsDecode() throws {
        let item = itemJSON(id: "practice.drill_recent", category: "practice",
                            extra: #", "recurrence_days": 183, "completed_at": "2026-07-04T09:00:00Z""#)
        let decoded = try XCTUnwrap(try decodeBreakdown(breakdownJSON(checklist: [item])).checklist.first)
        XCTAssertEqual(decoded.recurrence_days, 183)
        XCTAssertEqual(decoded.completed_at, "2026-07-04T09:00:00Z")
        XCTAssertEqual(decoded.completedAt, Date(timeIntervalSince1970: 1_783_155_600))
    }

    func testFractionalSecondsCompletedAtStillParses() throws {
        let item = itemJSON(id: "rescan.home", category: "practice",
                            extra: #", "recurrence_days": 183, "completed_at": "2026-07-04T09:00:00.250000Z""#)
        let decoded = try XCTUnwrap(try decodeBreakdown(breakdownJSON(checklist: [item])).checklist.first)
        XCTAssertEqual(try XCTUnwrap(decoded.completedAt).timeIntervalSince1970, 1_783_155_600.25, accuracy: 0.001)
    }

    /// A ScoreCache file written before S11.35 has neither key; it must still load, and say
    /// nothing about recurrence.
    func testCachedPayloadWithoutRecurrenceFieldsStillDecodesAndReEncodes() throws {
        let breakdown = try decodeBreakdown(breakdownJSON(checklist: [itemJSON(id: "practice.drill_recent",
                                                                               category: "practice")]))
        let item = try XCTUnwrap(breakdown.checklist.first)
        XCTAssertNil(item.recurrence_days)
        XCTAssertNil(item.completed_at)
        XCTAssertNil(item.recurrenceLabel(now: Date()))

        // Round-trip through the cache's own coder keeps the new fields when they are present.
        var dated = item
        dated.recurrence_days = 30
        dated.completed_at = "2026-10-01T00:00:00Z"
        let again = try HomeModel.decoder.decode(ChecklistItem.self, from: HomeModel.encoder().encode(dated))
        XCTAssertEqual(again, dated)
    }

    // MARK: Recurrence label (wording: owner, 2026-10-04)

    private func recurring(done: Bool, days: Int = 183, completedAt: String?) -> ChecklistItem {
        ChecklistItem(id: "practice.drill_recent", category: .practice, title: "Practice a fire drill",
                      detail: "", done: done, scoring: false, recurrence_days: days, completed_at: completedAt)
    }

    private let labelNow = Date(timeIntervalSince1970: 1_791_115_200) // 2026-10-04T12:00:00Z

    func testLabelDoneWithDateSaysAgoAndDueIn() {
        // 92 days before labelNow: 3 months ago, 91 days left of 183 = 3 months.
        let item = recurring(done: true, completedAt: "2026-07-04T12:00:00Z")
        XCTAssertEqual(item.recurrenceLabel(now: labelNow), "Done 3 months ago · due in 3 months")
    }

    /// The server said not done, so the row says due now, whatever the local arithmetic thinks.
    func testLabelFollowsServerDoneNotLocalArithmetic() {
        let item = recurring(done: false, completedAt: "2026-07-04T12:00:00Z")
        XCTAssertEqual(item.recurrenceLabel(now: labelNow), "Done 3 months ago · due again now")
    }

    func testLabelForTodayAndMonthlyItem() {
        let item = recurring(done: true, days: 30, completedAt: "2026-10-04T08:00:00Z")
        XCTAssertEqual(item.recurrenceLabel(now: labelNow), "Done today · due in 1 month")
    }

    func testLabelWithNoDateSaysHowOftenItRepeats() {
        XCTAssertEqual(recurring(done: true, completedAt: nil).recurrenceLabel(now: labelNow),
                       "Repeats every 6 months")
        XCTAssertEqual(recurring(done: false, days: 30, completedAt: nil).recurrenceLabel(now: labelNow),
                       "Repeats every month")
    }

    /// A cached answer read offline can say done after the time is up: never "due within a day".
    func testOverdueButCachedDoneSaysDueNow() {
        let item = recurring(done: true, completedAt: "2026-03-18T12:00:00Z") // 200 days before labelNow
        XCTAssertEqual(item.recurrenceLabel(now: labelNow), "Done 7 months ago · due again now")
    }

    /// The row's state while a tick waits for the server: the label must agree with the circle.
    func testLabelFollowsTheRowWhileATickIsPending() {
        let lapsed = recurring(done: false, completedAt: "2026-03-18T12:00:00Z")
        XCTAssertEqual(lapsed.recurrenceLabel(now: labelNow, shownDone: true), "Done today · due in 6 months")
        let fresh = recurring(done: true, completedAt: "2026-07-04T12:00:00Z")
        XCTAssertEqual(fresh.recurrenceLabel(now: labelNow, shownDone: false), "Repeats every 6 months")
    }

    func testNonRecurringItemHasNoLabel() {
        let item = ChecklistItem(id: "alarm.every_level", category: .smoke_alarm, title: "t", detail: "",
                                 done: true, scoring: true)
        XCTAssertNil(item.recurrenceLabel(now: labelNow))
    }
}
