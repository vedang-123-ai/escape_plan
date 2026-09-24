//  SnapshotHazardSummaryTests.swift — the Responder Snapshot's hazard rollup (S11.6).
//
//  Ground truth for the id shapes asserted here is `backend/app/scoring/checklist.py`:
//  route_items() emits "routes.<kind>.<room_id>", egress_window_items() emits
//  "egress.window.<opening_id>", object_hazard_items() emits "hazard.<rule_id>.<object_id>",
//  and mitigation_items()/earthquake_prep_items() emit "mitigation.secure.*" / "mitigation.<slug>"
//  for preparedness suggestions rather than detected findings. There is no local Python venv
//  on this machine (BLOCKERS §4), so these fixtures are hand-built to match those exact id
//  shapes rather than captured from a live engine run — flagged in the session note.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class SnapshotHazardSummaryTests: XCTestCase {

    private func item(id: String, category: ChecklistCategory, citation: String?) -> ChecklistItem {
        ChecklistItem(id: id, category: category, title: "t", detail: "d", done: false,
                      source_citation: citation, scoring: false)
    }

    func testCountsAndGroupsByRuleIDWithinCategory() {
        let checklist = [
            item(id: "routes.no_secondary_egress.room_1", category: .routes, citation: "nfpa-escape-planning"),
            item(id: "routes.no_secondary_egress.room_2", category: .routes, citation: "nfpa-escape-planning"),
            item(id: "routes.blocked_opening.room_1.obj_1", category: .routes, citation: "usfa-escape-plans"),
        ]
        let summary = SnapshotHazardSummary.summarize(checklist: checklist)
        XCTAssertEqual(summary, [
            .init(category: "routes", ruleID: "blocked_opening", count: 1, citation: "usfa-escape-plans"),
            .init(category: "routes", ruleID: "no_secondary_egress", count: 2, citation: "nfpa-escape-planning"),
        ])
    }

    func testIncludesEgressAndObjectHazardFindings() {
        let checklist = [
            item(id: "egress.window.opening_3", category: .egress, citation: "irc-2021-r310"),
            item(id: "hazard.topple.obj_2", category: .mitigation, citation: "shakeout-guidance"),
            item(id: "hazard.water_heater_unsecured.obj_5", category: .mitigation, citation: "shakeout-guidance"),
        ]
        let summary = SnapshotHazardSummary.summarize(checklist: checklist)
        XCTAssertEqual(Set(summary.map(\.ruleID)), ["window", "topple", "water_heater_unsecured"])
        XCTAssertTrue(summary.allSatisfy { $0.citation != nil })
    }

    /// The rule this whole file exists to pin: preparedness SUGGESTIONS (not findings the
    /// engine detected on this home) never enter the summary, and neither does anything
    /// outside the three hazard-bearing categories.
    func testExcludesPreparednessSuggestionsAndNonHazardCategories() {
        let checklist = [
            item(id: "mitigation.secure.obj_1.renter", category: .mitigation, citation: "shakeout-guidance"),
            item(id: "mitigation.secure.obj_1", category: .mitigation, citation: "shakeout-guidance"),
            item(id: "mitigation.earthquake_kit", category: .mitigation, citation: "shakeout-guidance"),
            item(id: "smoke_alarm.kitchen", category: .smoke_alarm, citation: "usfa-smoke-alarms"),
            item(id: "practice.meeting_point", category: .practice, citation: nil),
            item(id: "agent_finding.0", category: .agent_finding, citation: "usfa-escape-plans"),
            item(id: "safe_room.basement", category: .safe_room, citation: "redcross-tornado"),
        ]
        XCTAssertEqual(SnapshotHazardSummary.summarize(checklist: checklist), [])
    }

    func testMissingCitationIsSurfacedAsNilNeverBackfilled() {
        let checklist = [item(id: "hazard.overhead.obj_9", category: .mitigation, citation: nil)]
        let summary = SnapshotHazardSummary.summarize(checklist: checklist)
        XCTAssertEqual(summary, [.init(category: "mitigation", ruleID: "overhead", count: 1, citation: nil)])
    }

    func testEmptyChecklistProducesEmptySummary() {
        XCTAssertEqual(SnapshotHazardSummary.summarize(checklist: []), [])
    }

    func testResultOrderingIsDeterministic() {
        let checklist = [
            item(id: "hazard.topple.b", category: .mitigation, citation: "shakeout-guidance"),
            item(id: "routes.no_viable_route.z", category: .routes, citation: "nfpa-escape-planning"),
            item(id: "hazard.overhead.a", category: .mitigation, citation: "shakeout-guidance"),
            item(id: "egress.window.opening_1", category: .egress, citation: "irc-2021-r310"),
        ]
        let ordered = SnapshotHazardSummary.summarize(checklist: checklist).map { "\($0.category).\($0.ruleID)" }
        XCTAssertEqual(ordered, ["egress.window", "mitigation.overhead", "mitigation.topple", "routes.no_viable_route"])
    }
}
