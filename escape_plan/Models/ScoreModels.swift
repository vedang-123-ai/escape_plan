// ScoreModels.swift
// Swift mirror of the S3.5 /score contract (backend/app/scoring/score.py + checklist.py,
// request model in backend/app/main.py). Field names intentionally stay snake_case to match
// the backend exactly, like HomeModel.swift — see .claude/rules/languages/swift.md.
//
// The client never computes score math: every checklist toggle re-POSTs /score and displays
// what the server returns, so the number always matches docs/preparedness-score-weights.md
// by construction.

import Foundation

/// One request body for POST /score. The backend's ScoreRequest also accepts
/// `constraints`, `findings`, `profile`, and `include_recommendations`, all with server
/// defaults — omitted here until /analyze (S3.2) and recommendations are wired in. With no
/// findings sent, the findings component sits at full marks (20/20) by design.
struct ScoreRequest: Encodable {
    var home: HomeModel
    var checklist_state: [String: Bool]
}

/// One of the five weighted components (primary_routes, secondary_routes, findings,
/// smoke_alarms, practice — always in that server order). `detail` spells out the
/// arithmetic in words; `rationale` explains the weight, cited where applicable.
struct ScoreComponent: Decodable, Identifiable, Hashable {
    var key: String
    var label: String
    var earned_points: Double
    var max_points: Double
    var detail: String
    var rationale: String

    var id: String { key }
}

/// Checklist categories the backend emits (`backend/app/scoring/checklist.py`).
///
/// Decoding is deliberately tolerant. A raw-value enum that throws on an unknown string
/// fails its PARENT's decode, so one unrecognized category takes down the whole
/// `ScoreBreakdown` and the user sees "Couldn't get your score" — which is exactly what
/// happened between 2026-07-27 and 2026-08-02, when the backend started emitting `egress`
/// and Swift had no case for it (broken on apartment + twostory, i.e. the demo home).
/// An unknown category must cost one odd-looking row, never the screen.
///
/// Adding a case here is not the whole job: `ScoreScreen.categoryOrder` is a whitelist and
/// silently drops anything absent from it.
enum ChecklistCategory: String, Decodable, CaseIterable {
    case smoke_alarm
    case practice
    case routes
    case egress
    case agent_finding
    case recommendation
    /// Anything the backend added that this build predates.
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChecklistCategory(rawValue: raw) ?? .other
    }
}

/// A checklist row. Only items with `scoring == true` (smoke_alarm and practice
/// categories) move the score; the rest are advisory.
struct ChecklistItem: Decodable, Identifiable, Hashable {
    var id: String
    var category: ChecklistCategory
    var title: String
    var detail: String
    var done: Bool
    var source_citation: String?
    var scoring: Bool
    var component: String?
}

/// POST /score response: the 0–100 score plus the exact breakdown it came from.
struct ScoreBreakdown: Decodable {
    var home_id: String
    var home_name: String
    var score: Int
    var components: [ScoreComponent]
    var checklist: [ChecklistItem]
}
