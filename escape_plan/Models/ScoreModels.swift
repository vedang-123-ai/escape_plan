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

enum ChecklistCategory: String, Decodable {
    case smoke_alarm
    case practice
    case routes
    case agent_finding
    case recommendation
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
