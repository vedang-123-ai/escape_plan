// ChecklistStateStore.swift
// Per-home checklist done-state for the S3.5 preparedness score.
//
// Stored in UserDefaults under "checklistState.<home_id>", NOT on the home document:
// the HomeModel schema is frozen (no checklist field without a schema_version bump), and
// HomeDocumentStore files are exactly HomeModel JSON by design ("export is the stored file").
// Trade-off, documented in docs/decisions.md: state doesn't travel with export/import, and a
// deleted home leaves an orphaned (tiny, harmless) entry behind.

import Foundation

struct ChecklistStateStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for homeID: String) -> String { "checklistState.\(homeID)" }

    /// Item id -> done. Missing ids mean "not done".
    func load(homeID: String) -> [String: Bool] {
        defaults.dictionary(forKey: key(for: homeID)) as? [String: Bool] ?? [:]
    }

    func save(_ state: [String: Bool], homeID: String) {
        defaults.set(state, forKey: key(for: homeID))
    }
}
