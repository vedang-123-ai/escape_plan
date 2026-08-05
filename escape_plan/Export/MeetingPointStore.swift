//  MeetingPointStore.swift
//  escape_plan — Export module
//
//  The household's outside meeting place, remembered per home.
//
//  WHY THIS IS NOT IN THE SCHEMA: `schema/homemodel.schema.json` is the project's one law and
//  is frozen — adding a `meeting_point` field would be a schema_version bump plus sign-off
//  across JSON Schema, pydantic and the Swift mirror, for a string only the printout uses.
//  The engine does not route to it, the converter does not produce it, the agent does not
//  inspect it. So it lives here: user free text, captured in the export sheet, persisted in
//  UserDefaults under the home's id so it survives relaunch, and printed prominently.
//
//  Consequence worth knowing: it is device-local. Duplicating or re-importing a home mints a
//  new `home_id` (HomeDocumentStore does this deliberately) and the copy starts with an empty
//  meeting place rather than inheriting a stale one. That is the safer failure.
//
//  Follows the `ChecklistStateStore` precedent — small, per-home, UserDefaults-backed state
//  that is not part of the model contract.

import Foundation

struct MeetingPointStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(homeID: String) -> String { "export.meetingPoint.\(homeID)" }

    /// The saved meeting place, or "" when none has been entered.
    func meetingPoint(forHomeID homeID: String) -> String {
        defaults.string(forKey: Self.key(homeID: homeID)) ?? ""
    }

    /// Saves the text, trimmed. Saving an empty string clears the entry rather than storing
    /// whitespace that would print as a blank line.
    func setMeetingPoint(_ text: String, forHomeID homeID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.key(homeID: homeID))
        } else {
            defaults.set(trimmed, forKey: Self.key(homeID: homeID))
        }
    }
}
