//  Theme.swift
//  Screens — the semantic colour and type scale for app chrome.
//
//  The 3D model has exactly one rule: the escape route is the only hot colour in the frame.
//  That rule was being broken by the chrome around it. Seven screens used SwiftUI's `.orange`
//  for warnings and advisories — scan fallbacks, rejected edits, onboarding hints, the
//  Settings status dot — so a user could see route-orange and warning-orange in the same
//  scroll and have no way to know they meant different things.
//
//  So: **chrome contains no route orange.** `Theme.routeInk` exists only for legends that are
//  literally labelling a route, and nothing else in this file is allowed to approach that hue.
//  Advisories use a dark amber that cannot be mistaken for a lit route at a glance; genuine
//  faults use the palette's warning red; positive states use the app accent, which is the
//  deep safety green chosen precisely so it stays out of orange's way.
//
//  Colours bridge from `DollhousePalette` rather than being redeclared, so the renderer and
//  the chrome cannot drift.

import SwiftUI

enum Theme {

    // MARK: - Semantic colours

    /// Positive, selected, actionable. Same deep green as `AccentColor` and the 3D selection
    /// ring, so "the app's colour" means one thing everywhere.
    static let accent = Color.accentColor

    /// Something is wrong and the user should act: failed saves, invalid input, backend faults.
    static let warning = Color(DollhousePalette.warningBadge)

    /// Worth noticing, not broken: a low-confidence scan item, a rejected edit, a caveat.
    ///
    /// Deliberately a dark amber (#B45309) rather than SwiftUI's `.orange` (~#FF9500). At a
    /// glance the difference from route orange (#FF5A1F) is obvious — one is a dark ink, the
    /// other is a lit line — which is the entire reason this constant exists.
    static let caution = Color(red: 0.706, green: 0.325, blue: 0.035)

    /// ONLY for swatches and legends that label an actual escape route. Never for state.
    static let routeInk = Color(DollhousePalette.routePrimary)
    /// ONLY for swatches and legends that label an actual exit.
    static let exitInk = Color(DollhousePalette.exitGreen)

    /// Quiet supporting text. Named so screens stop reaching for `.secondary` in some places
    /// and `.gray` in others.
    static let supporting = Color.secondary

    // MARK: - Type scale

    /// Screen-level heading inside a scroll view (not the navigation title).
    static let screenTitle = Font.title2.weight(.semibold)
    /// The label above a group of rows or controls.
    static let sectionHeader = Font.subheadline.weight(.semibold)
    /// A single number the screen exists to show — the preparedness score, a room count.
    static let metric = Font.system(.largeTitle, design: .rounded).weight(.bold)
    /// Body copy in a card.
    static let cardBody = Font.callout
    /// Captions, footnotes, banner text.
    static let detail = Font.caption
}

extension View {
    /// One consistent treatment for the label above a group, so section headers stop being
    /// five slightly different `.font(...).foregroundStyle(...)` pairs.
    func sectionHeaderStyle() -> some View {
        self.font(Theme.sectionHeader)
            .foregroundStyle(Theme.supporting)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}
