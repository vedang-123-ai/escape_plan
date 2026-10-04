// ScoreModels.swift
// Swift mirror of the S3.5 /score contract (backend/app/scoring/score.py + checklist.py,
// request model in backend/app/main.py). Field names intentionally stay snake_case to match
// the backend exactly, like HomeModel.swift — see .claude/rules/languages/swift.md.
//
// The client never computes score math: every checklist toggle re-POSTs /score and displays
// what the server returns, so the number always matches docs/preparedness-score-weights.md
// by construction.

import Foundation
import os

/// One request body for POST /score. The backend's ScoreRequest also accepts
/// `constraints`, `findings`, `profile`, and `include_recommendations`, all with server
/// defaults — omitted here until /analyze (S3.2) and recommendations are wired in. With no
/// findings sent, the findings component sits at full marks (20/20) by design.
struct ScoreRequest: Encodable {
    var home: HomeModel
    var checklist_state: [String: ChecklistMark]
}

/// One checklist value as the app stores and sends it (S11.35, AUD-026). The server's contract
/// (`backend/app/scoring/checklist.py`) is `bool | ISO-8601 string`: a recurring item that was
/// completed is sent as the time it was completed, and the server decides whether that is still
/// recent enough. Everything else is a plain Bool.
///
/// A Bool literal is a `.flag`, so `["alarm.every_level": true]` still reads as before.
enum ChecklistMark: Equatable, Encodable, ExpressibleByBooleanLiteral {
    case flag(Bool)
    case completed(Date)

    init(booleanLiteral value: Bool) { self = .flag(value) }

    /// The wire form of a completion time: UTC, `Z` suffix, whole seconds
    /// ("2026-10-04T12:00:00Z"). The server rejects the WHOLE request (422) on a string it
    /// cannot parse, so this one formatter is the only way a date is written.
    static func wireString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .flag(let done): try container.encode(done)
        case .completed(let date): try container.encode(Self.wireString(date))
        }
    }
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
    /// S11.34: how many days a completion counts for, or nil if the item does not recur. Which
    /// items recur is the server's call; the app reads it from here, never from its own list.
    var recurrence_days: Int?
    /// S11.34: when the server last saw this recurring item completed (UTC string), or nil
    /// (never completed, a legacy `true` with no date, or not recurring). Kept as the server's
    /// string; `completedAt` parses it.
    var completed_at: String?
    
    enum CodingKeys: String, CodingKey {
        case id, category, title, detail, done, source_citation, scoring, component, hazard, severity
        case recurrence_days, completed_at
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
        // IfPresent: a ScoreCache file written before S11.35 has neither key.
        recurrence_days = try container.decodeIfPresent(Int.self, forKey: .recurrence_days)
        completed_at = try container.decodeIfPresent(String.self, forKey: .completed_at)
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
        try container.encodeIfPresent(recurrence_days, forKey: .recurrence_days)
        try container.encodeIfPresent(completed_at, forKey: .completed_at)
    }
    
    // Memberwise init for tests
    init(id: String, category: ChecklistCategory, title: String, detail: String, done: Bool, source_citation: String? = nil, scoring: Bool, component: String? = nil, hazard: HazardTag? = nil, severity: ItemSeverity = .info, recurrence_days: Int? = nil, completed_at: String? = nil) {
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
        self.recurrence_days = recurrence_days
        self.completed_at = completed_at
    }
}

// MARK: - Recurrence label (S11.35)

extension ChecklistItem {
    /// `completed_at` as a Date. The server writes whole seconds today; fractional seconds are
    /// accepted too, so a server-side formatting change costs no label.
    var completedAt: Date? {
        guard let completed_at else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: completed_at) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: completed_at) { return date }
        // The row falls back to "Repeats every …"; the log says why (a server format change).
        Logger(subsystem: "escape_plan", category: "ScoreModels")
            .error("unparseable completed_at for \(self.id, privacy: .public)")
        return nil
    }

    /// The line under a recurring task, or nil for one that does not recur. Wording chosen by
    /// the owner 2026-10-04. Whether the item is done is the server's `done`; only the words are
    /// worked out here, from the server's own `completed_at` and `recurrence_days`.
    ///
    ///   done, dated:      "Done 3 months ago · due in 3 months"
    ///   not done, dated:  "Done 7 months ago · due again now"
    ///   no date known:    "Repeats every 6 months" (a tick from before dates were kept, or never done)
    ///
    /// `shownDone` is what the row shows, which differs from `done` only while a tick the user
    /// just made waits for the server's answer (or failed to reach it).
    func recurrenceLabel(now: Date, shownDone: Bool? = nil) -> String? {
        guard let days = recurrence_days else { return nil }
        let shownDone = shownDone ?? done
        if shownDone, !done { return "Done today · due in \(Self.span(days: days))" }
        guard shownDone == done, let completed = completedAt else {
            let every = Self.span(days: days)
            return "Repeats every \(every.hasPrefix("1 ") ? String(every.dropFirst(2)) : every)"
        }
        let ageDays = max(0, Int(now.timeIntervalSince(completed) / 86_400))
        let doneText: String
        switch ageDays {
        case 0: doneText = "Done today"
        case 1: doneText = "Done yesterday"
        default: doneText = "Done \(Self.span(days: ageDays)) ago"
        }
        guard done else { return "\(doneText) · due again now" }
        let due = completed.addingTimeInterval(TimeInterval(days) * 86_400)
        let leftDays = Int((due.timeIntervalSince(now) / 86_400).rounded(.up))
        switch leftDays {
        // Server said done but the time is up: a cached answer read offline.
        case ...0: return "\(doneText) · due again now"
        case 1: return "\(doneText) · due within a day"
        default: return "\(doneText) · due in \(Self.span(days: leftDays))"
        }
    }

    /// "5 days", "3 weeks", "6 months", "2 years": coarse on purpose, a task row is not a calendar.
    static func span(days: Int) -> String {
        func unit(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }
        switch days {
        case ..<14: return unit(days, "day")
        case ..<28: return unit(days / 7, "week")
        case ..<365: return unit(max(1, Int((Double(days) / 30.44).rounded())), "month")
        default: return unit(days / 365, "year")
        }
    }
}

/// POST /score response: the 0–100 score plus the exact breakdown it came from.
struct ScoreBreakdown: Codable {
    var home_id: String
    var home_name: String
    var score: Int
    var sub_scores: [String: Int]
    /// Per-peril evidence tier (S11.2), keyed exactly like `sub_scores`:
    /// `"code_quantified"` for fire, which is measured against IRC/NFPA numbers,
    /// `"guidance_based"` for earthquake and severe weather, which have no
    /// app-checkable numeric threshold in the corpus. Optional because a server
    /// predating S11.2 omits the key entirely.
    ///
    /// Typed as `String` rather than an enum on purpose: decoding an unknown
    /// future case into an enum throws and would fail the whole response.
    /// S11.5 renders the label; nothing here interprets it.
    var basis: [String: String]?
    var components: [ScoreComponent]
    var checklist: [ChecklistItem]
}
