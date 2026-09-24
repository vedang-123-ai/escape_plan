//  PreventionTipsFilter.swift
//  escape_plan — Readiness (S11.5)
//
//  Pure grouping/selection logic for the Home tab's "Prevent" section. No view code — SwiftUI
//  lives in Screens/HomeScreen.swift. Foundation-only, symlinked into tools/editorcore.

import Foundation

enum PreventionTipsFilter {

    /// All tips for one peril, in file order.
    static func tips(_ all: [PreventionTip], peril: PreventionTip.Peril) -> [PreventionTip] {
        all.filter { $0.peril == peril }
    }

    /// One tip per locked peril (fire, earthquake, tornado) — the Home tab's "Prevent" preview
    /// has room for a handful of cards, not the full 40-plus-tip library, so this picks the
    /// single most broadly-applicable tip per peril rather than truncating an unordered list.
    ///
    /// Deterministic: prefers the first `audience == .everyone` tip in file order, falling back
    /// to the first tip of any audience for a peril that (today) has none. The same home shows
    /// the same spotlight every launch rather than a different "random" pick each time, which
    /// would read as the app being unsure what it means to say.
    static func spotlight(_ all: [PreventionTip]) -> [PreventionTip] {
        PreventionTip.Peril.allCases.compactMap { peril in
            let forPeril = tips(all, peril: peril)
            return forPeril.first { $0.audience == .everyone } ?? forPeril.first
        }
    }
}
