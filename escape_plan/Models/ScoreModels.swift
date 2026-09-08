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

/// S6.7: 0 or 1 entries — the single largest unresolved `scoring: true` checklist
/// deduction across all three peril sub-scores, not a fixed set of five weighted
/// components. `detail` spells out the arithmetic in words; `rationale` explains the
/// weight, cited where applicable. See docs/preparedness-score-weights.md.
struct ScoreComponent: Codable, Identifiable, Hashable {
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
enum ChecklistCategory: String, Codable, CaseIterable {
    case smoke_alarm
    case practice
    case routes
    case egress
    case agent_finding
    case recommendation
    case shutoffs
    case safe_room
    case mitigation
    case supply_kit
    case alerts
    /// Anything the backend added that this build predates.
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChecklistCategory(rawValue: raw) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

enum HazardTag: String, Codable, CaseIterable {
    case fire
    case earthquake
    case severe_weather
    case general
}

enum ItemSeverity: String, Codable {
    case info
    case high
    case unknown
    
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemSeverity(rawValue: raw) ?? .info
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

/// A checklist row. Only items with `scoring == true` (smoke_alarm and practice
/// categories) move the score; the rest are advisory.
struct ChecklistItem: Codable, Identifiable, Hashable {
    var id: String
    var category: ChecklistCategory
    var title: String
    var detail: String
    var done: Bool
    var source_citation: String?
    var scoring: Bool
    var component: String?
    var hazard: HazardTag?
    var severity: ItemSeverity
    
    enum CodingKeys: String, CodingKey {
        case id, category, title, detail, done, source_citation, scoring, component, hazard, severity
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(ChecklistCategory.self, forKey: .category)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        done = try container.decode(Bool.self, forKey: .done)
        source_citation = try container.decodeIfPresent(String.self, forKey: .source_citation)
        scoring = try container.decode(Bool.self, forKey: .scoring)
        component = try container.decodeIfPresent(String.self, forKey: .component)
        hazard = try container.decodeIfPresent(HazardTag.self, forKey: .hazard)
        severity = try container.decodeIfPresent(ItemSeverity.self, forKey: .severity) ?? .info
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(category, forKey: .category)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(done, forKey: .done)
        try container.encodeIfPresent(source_citation, forKey: .source_citation)
        try container.encode(scoring, forKey: .scoring)
        try container.encodeIfPresent(component, forKey: .component)
        try container.encodeIfPresent(hazard, forKey: .hazard)
        try container.encode(severity, forKey: .severity)
    }
    
    // Memberwise init for tests
    init(id: String, category: ChecklistCategory, title: String, detail: String, done: Bool, source_citation: String? = nil, scoring: Bool, component: String? = nil, hazard: HazardTag? = nil, severity: ItemSeverity = .info) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.done = done
        self.source_citation = source_citation
        self.scoring = scoring
        self.component = component
        self.hazard = hazard
        self.severity = severity
    }
}

/// POST /score response: the 0–100 score plus the exact breakdown it came from.
struct ScoreBreakdown: Codable {
    var home_id: String
    var home_name: String
    var score: Int
    var sub_scores: [String: Int]
    var components: [ScoreComponent]
    var checklist: [ChecklistItem]
}
