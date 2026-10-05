// ChecklistStateStore.swift
// Per-home checklist done-state for the S3.5 preparedness score.
//
// Stored in UserDefaults under "checklistState.<home_id>", NOT on the home document:
// the HomeModel schema is frozen (no checklist field without a schema_version bump), and
// HomeDocumentStore files are exactly HomeModel JSON by design ("export is the stored file").
// Trade-off, documented in docs/decisions.md: state doesn't travel with export/import, and a
// deleted home leaves an orphaned (tiny, harmless) entry behind.
//
// S11.35: a value is a Bool or a Date (when a recurring item was completed). UserDefaults stores
// both natively in one property-list dictionary, so a store written before S11.35 (Bools only)
// loads unchanged and re-saves as the same Bools: no migration step, and no invented dates.

import Foundation
import os

struct ChecklistStateStore {
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "escape_plan", category: "ChecklistStateStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for homeID: String) -> String { "checklistState.\(homeID)" }

    /// Item id -> mark. Missing ids mean "not done". A value that is neither a Bool nor a Date
    /// is dropped on its own (and logged); the rest of the home's ticks still load.
    func load(homeID: String) -> [String: ChecklistMark] {
        guard let raw = defaults.dictionary(forKey: key(for: homeID)) else { return [:] }
        var state: [String: ChecklistMark] = [:]
        for (id, value) in raw {
            if let date = value as? Date {
                // A date on an item that no longer recurs (the alarm test, 2026-10-05) is a tick.
                state[id] = ChecklistMark.completed(date).normalized(forItem: id)
            } else if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
                state[id] = .flag(number.boolValue)
            } else {
                Self.log.error("dropped unreadable checklist value for \(id, privacy: .public)")
            }
        }
        return state
    }

    func save(_ state: [String: ChecklistMark], homeID: String) {
        let raw: [String: Any] = state.mapValues { mark -> Any in
            switch mark {
            case .flag(let done): return done
            case .completed(let date): return date
            }
        }
        defaults.set(raw, forKey: key(for: homeID))
    }
}
