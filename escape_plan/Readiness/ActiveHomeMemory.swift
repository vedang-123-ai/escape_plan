//  ActiveHomeMemory.swift
//  escape_plan — Readiness (S11.57, defect S53-2)
//
//  Which home the app opens on. The home the user picked is remembered across launches; if it no
//  longer exists (deleted), the demo home opens, then the first home in the library. Before this
//  the app always opened on `library.homes.first`, so a relaunch dropped the user's choice and a
//  fresh install landed on whichever fixture sorted first.
//
//  UserDefaults, like ChecklistStateStore and ScanFreshnessStore: one small device-local value,
//  outside the HomeModel contract. Foundation-only, symlinked into tools/editorcore.

import Foundation

struct ActiveHomeMemory {
    static let defaultsKey = "readiness.activeHomeID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The home that was active when the app last changed homes, or nil if none was ever chosen.
    var remembered: String? { defaults.string(forKey: Self.defaultsKey) }

    /// Remembers `homeID`; nil (no home left) forgets it.
    func remember(_ homeID: String?) {
        if let homeID {
            defaults.set(homeID, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    /// The home to open, from the homes in the library (`available`, in library order): the
    /// remembered one if it still exists, else the demo home if it exists, else the first.
    /// Pure, so every way in (launch, a delete, a sync, onboarding) picks the same home.
    static func choose(remembered: String?, available: [String], demoHomeID: String?) -> String? {
        if let remembered, available.contains(remembered) { return remembered }
        if let demoHomeID, available.contains(demoHomeID) { return demoHomeID }
        return available.first
    }

    /// `choose` with this memory's remembered home.
    func choose(available: [String], demoHomeID: String?) -> String? {
        Self.choose(remembered: remembered, available: available, demoHomeID: demoHomeID)
    }
}
