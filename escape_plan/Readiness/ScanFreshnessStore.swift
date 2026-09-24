//  ScanFreshnessStore.swift
//  escape_plan — Readiness (S11.5)
//
//  Per-home wall-edge-count snapshot, recorded whenever a scan is imported, so the Home tab
//  can tell "a wall was added or removed since the last scan" (ScanFreshness.wallsChanged)
//  without a schema field. Follows the MeetingPointStore / ChecklistStateStore precedent:
//  small, per-home, UserDefaults-backed state that is device-local and outside the HomeModel
//  contract on purpose (schema/homemodel.schema.json is frozen outside its own process — see
//  .claude/rules/paths/schema.md). Foundation-only, symlinked into tools/editorcore.

import Foundation

struct ScanFreshnessStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(homeID: String) -> String { "readiness.wallEdgeCount.\(homeID)" }

    /// The wall-edge count recorded the last time a scan was imported for this home, or nil if
    /// this home predates the feature or has never been scanned at all.
    func recordedWallEdgeCount(homeID: String) -> Int? {
        let key = Self.key(homeID: homeID)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    func recordWallEdgeCount(_ count: Int, homeID: String) {
        defaults.set(count, forKey: Self.key(homeID: homeID))
    }
}
