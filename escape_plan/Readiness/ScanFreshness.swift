//  ScanFreshness.swift
//  escape_plan — Readiness (S11.5)
//
//  The firefighter's warning that drove this file: "remodels make stored layouts stale"
//  (docs/playbook/01-product-spec.md §2). The Home tab has to say how old a home's scan is and
//  nudge a re-scan — honestly: this is resident-maintained, never verified against the real
//  house. Pure logic only; SwiftUI rendering lives in Screens/HomeScreen.swift. Foundation-only,
//  symlinked into tools/editorcore.

import Foundation

enum ScanFreshness {

    /// Nudge threshold: 180 days (~6 months). This is not a new number — HomeScreen.swift
    /// already nudged at exactly this threshold before S11.5 ("It's been over 6 months since
    /// this home was scanned"); this file gives that existing judgement call a name, a
    /// fallback for homes with no scan at all, and a second trigger (wall edits) it didn't
    /// have before. Six months is long enough that a genuinely unchanged home isn't nagged on
    /// every visit, short enough to precede most of the remodel/furniture cycles the
    /// firefighter described. Logged in docs/decisions.md.
    static let staleThresholdDays = 180

    /// Days since the home was last scanned, falling back to `modified` for a home that has
    /// never been scanned at all (built manually or via the text/photo draft path) — per the
    /// mission brief. Returns nil only if the reference timestamp is in the future, which
    /// should never happen for a real document; better to say nothing than a negative age.
    static func daysSince(lastScanned: Date?, modified: Date, now: Date = Date()) -> Int? {
        let reference = lastScanned ?? modified
        let interval = now.timeIntervalSince(reference)
        guard interval >= 0 else { return nil }
        return Int(interval / 86400)
    }

    static func isStaleByAge(days: Int?) -> Bool {
        guard let days else { return false }
        return days > staleThresholdDays
    }

    /// "Scanned 12 days ago." / "Scanned today." / "Built by hand — not yet scanned." Always
    /// honest about which case it is; never implies a scan happened when the home was only
    /// ever hand-built or drafted from a photo.
    static func scanAgeText(lastScanned: Date?, modified: Date, now: Date = Date()) -> String {
        guard lastScanned != nil else {
            return "Built by hand — not yet scanned."
        }
        guard let days = daysSince(lastScanned: lastScanned, modified: modified, now: now) else {
            return "Scan date unavailable."
        }
        switch days {
        case 0: return "Scanned today."
        case 1: return "Scanned 1 day ago."
        default: return "Scanned \(days) days ago."
        }
    }

    /// Total wall-edges across every room on every floor. Rooms are 2D polygons
    /// (schema/homemodel.schema.json — "never store meshes"); a closed polygon's edge count
    /// equals its point count, and there is no dedicated wall list to count instead. This is
    /// the cheapest honest proxy for "how many walls does this home have" without a schema
    /// change (schema.md — the schema is frozen outside its own process).
    static func wallEdgeCount(_ home: HomeModel) -> Int {
        home.floors.reduce(0) { floorSum, floor in
            floorSum + floor.rooms.reduce(0) { roomSum, room in roomSum + room.polygon.count }
        }
    }

    /// True when the home's current wall-edge count differs from the count recorded at the
    /// last scan. `nil` (no recorded count — the home predates this feature, or has never been
    /// scanned) is never treated as a change: silence, not a false alarm.
    static func wallsChanged(currentEdgeCount: Int, recordedEdgeCount: Int?) -> Bool {
        guard let recordedEdgeCount else { return false }
        return currentEdgeCount != recordedEdgeCount
    }

    enum NudgeReason: Equatable {
        /// The age threshold passed.
        case stale
        /// A wall was added or removed since the last scan, regardless of age.
        case wallsEdited
    }

    /// Walls-edited takes priority: it is evidence of an actual change, not just elapsed time,
    /// so it is the more specific and more urgent of the two reasons.
    static func nudgeReason(daysSinceScan: Int?, wallsChanged: Bool) -> NudgeReason? {
        if wallsChanged { return .wallsEdited }
        if isStaleByAge(days: daysSinceScan) { return .stale }
        return nil
    }

    /// Copy for the re-scan nudge card. Always says the plan is resident-maintained, not
    /// verified — the honesty rule this whole file exists to serve.
    static func nudgeMessage(_ reason: NudgeReason) -> String {
        switch reason {
        case .stale:
            return "It's been over 6 months since this home was scanned. Layouts change — "
                + "rearranged furniture, a new wall, someone moving in or out. This plan is "
                + "resident-maintained, not verified: a re-scan keeps it accurate."
        case .wallsEdited:
            return "A wall was added or removed since the last scan. This plan is "
                + "resident-maintained, not verified — a re-scan keeps your routes accurate."
        }
    }
}
