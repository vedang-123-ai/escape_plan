//  SnapshotHazardSummary.swift
//  escape_plan — Export module
//
//  A pure rollup of the deterministic hazard engine's own output for the Responder Snapshot's
//  "hazard summary" section (S11.6). It counts findings the engine already produced — it
//  NEVER re-judges the home, and it deliberately does not fold every category into one
//  number. See docs/decisions.md (S11.6, "no aggregate clutter score"): the engine has no
//  defensible weighting across a blocked exit, an unsecured water heater and a too-small
//  egress window, and the scope lock forbids claiming transient clutter is detected at all.
//
//  Foundation-only: this file is symlinked verbatim into tools/editorcore/Sources/EditorCore
//  so `swift test --package-path tools/editorcore` reaches it without a simulator. No
//  SwiftUI/UIKit import here, ever — see .claude/rules/paths/editorcore.md.
//
//  SOURCE OF TRUTH: `ChecklistItem` (Models/ScoreModels.swift) already mirrors the backend's
//  deterministic findings 1:1 — `backend/app/scoring/checklist.py` — with a stable id shape
//  and a citation. Rather than re-deriving from `RoutePlan`/`ObjectHazard` and risking a
//  second, drifting notion of "hazard", this reads the same checklist the Score screen does:
//    - category "routes":     id "routes.<FindingKind>.<room_id>[...]"        (route_items)
//    - category "egress":     id "egress.window.<opening_id>"                 (egress_window_items)
//    - category "mitigation": id "hazard.<rule_id>.<object_id>"               (object_hazard_items)
//  "mitigation.secure.*" and per-home "mitigation.<slug>" items are earthquake PREPARATION
//  suggestions, not findings the engine detected on this home — excluded on purpose so this
//  summary never claims to have "found" something it only recommends doing.
import Foundation

enum SnapshotHazardSummary {

    /// One rolled-up row: how many times a given rule fired, in which checklist category,
    /// with the citation the engine attached (verbatim — never backfilled or guessed).
    struct Entry: Codable, Equatable {
        var category: String
        var ruleID: String
        var count: Int
        var citation: String?
    }

    /// Categories that represent findings the engine detected on THIS home, as opposed to
    /// general preparedness advice. Order here is the order entries are reported in.
    private static let hazardCategories: Set<ChecklistCategory> = [.routes, .egress, .mitigation]

    static func summarize(checklist: [ChecklistItem]) -> [Entry] {
        var byKey: [String: Entry] = [:]
        var order: [String] = []

        for item in checklist {
            guard isHazardFinding(item) else { continue }
            let ruleID = Self.ruleID(fromItemID: item.id)
            let key = "\(item.category.rawValue).\(ruleID)"
            if var existing = byKey[key] {
                existing.count += 1
                if existing.citation == nil { existing.citation = item.source_citation }
                byKey[key] = existing
            } else {
                byKey[key] = Entry(category: item.category.rawValue, ruleID: ruleID,
                                    count: 1, citation: item.source_citation)
                order.append(key)
            }
        }

        // Deterministic order: category, then rule id — never insertion order, which a
        // dictionary does not guarantee anyway.
        return order.compactMap { byKey[$0] }
            .sorted { $0.category == $1.category ? $0.ruleID < $1.ruleID : $0.category < $1.category }
    }

    private static func isHazardFinding(_ item: ChecklistItem) -> Bool {
        switch item.category {
        case .routes, .egress:
            return true
        case .mitigation:
            // Only the actual object-hazard findings ("hazard.<rule_id>.<object_id>"),
            // never the "secure this anyway" / whole-home preparation suggestions.
            return item.id.hasPrefix("hazard.")
        default:
            return false
        }
    }

    /// "routes.no_secondary_egress.room_1" -> "no_secondary_egress"
    /// "egress.window.opening_3"           -> "window"
    /// "hazard.topple.obj_2"               -> "topple"
    private static func ruleID(fromItemID id: String) -> String {
        let parts = id.split(separator: ".")
        guard parts.count >= 2 else { return id }
        return String(parts[1])
    }
}
