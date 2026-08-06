//  Theme.swift
//  Screens — the semantic colour and type scale for app chrome.
//
//  The 3D model has exactly one rule about colour: **cool hues are routes, warm hues are
//  hazard.** Chrome has to hold the same line, because a user who sees route-blue in a legend
//  and hazard-orange in a banner must be able to trust that those two colours mean two
//  different things everywhere in the app.
//
//  History worth keeping, because the comments used to lie about it: routes were originally
//  safety orange (#FF5A1F), back when the route was the only colour in the frame. The
//  fire-origin hazard visualization put a second coloured system on screen, and orange route
//  plus red/orange hazard is the textbook deuteranopia collision — so `DollhousePalette`
//  re-keyed routes to cool (#123FB0 / #4180D4) and reserved warm for hazard. This file did not
//  follow, and `routeInkComponents` sat on the retired orange for a while: every legend
//  claiming to show "the route colour" showed a colour no route used. Fixed below.
//
//  So: **chrome contains no hazard warm except `hazardInk`, and no route cool except the two
//  route inks.** Those exist only for legends literally labelling a route, an exit or the
//  hazard. Advisories use a dark amber that cannot be mistaken for either system; genuine
//  faults use the palette's warning red; positive states use the app accent, the deep safety
//  green.
//
//  ## Accessibility pass (lane D1)
//
//  The single-value chrome colours could not survive dark mode. `DollhousePalette.warningBadge`
//  (#DC2626) reads at 3.52:1 on iOS's dark grouped-row background and the old caution amber
//  (#B45309) at 3.39:1 — both well under the 4.5:1 WCAG 2.2 AA floor for the caption-sized text
//  they were actually used for. So the chrome colours are now **appearance-aware pairs**: a
//  light value tuned against #FFFFFF / #F2F2F7 and a dark value tuned against #000000 /
//  #1C1C1E / #2C2C2E, each verified by `ThemeContrastTests`.
//
//  The renderer keeps its own single-value badge colours (they sit on the dollhouse, not on a
//  system background, and are non-text). Chrome no longer literally bridges
//  `DollhousePalette` — it stays in the same hue family so the badge and the banner still read
//  as one idea, but the exact value is chosen for legibility on a text background. That
//  deliberate un-bridging is the one thing here worth a decisions.md line.

import SwiftUI

// MARK: - WCAG contrast maths

/// sRGB triple in 0…1, appearance-independent. Exists so contrast can be computed and
/// asserted in a unit test without a running UI or a trait collection.
struct SRGB: Equatable, Sendable {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// `SRGB(hex: 0xB45309)`.
    init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255,
                  g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// WCAG 2.2 relative luminance and contrast ratio, straight from the spec
/// (https://www.w3.org/TR/WCAG22/#dfn-relative-luminance, #dfn-contrast-ratio).
///
/// Deliberately pure and dependency-free so `escape_planTests/ThemeContrastTests` can assert
/// the real `Theme` values rather than a comment claiming they're fine.
enum WCAG {

    /// Minimum ratios the project holds itself to.
    enum Target {
        /// Body text, and any text below 18pt (or below 14pt bold). SC 1.4.3.
        static let bodyText = 4.5
        /// Large text: ≥18pt, or ≥14pt bold. SC 1.4.3.
        static let largeText = 3.0
        /// Non-text UI components and state indicators. SC 1.4.11.
        static let component = 3.0
    }

    /// Minimum target size in points for an interactive control. SC 2.5.8.
    static let minimumTargetSize: CGFloat = 24

    static func relativeLuminance(_ color: SRGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    static func contrastRatio(_ a: SRGB, _ b: SRGB) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// A colour that has a separately-tuned value per appearance, plus the raw components so a
/// test can check both without instantiating a trait collection.
struct AppearancePair: Sendable {
    let light: SRGB
    let dark: SRGB

    init(light: UInt32, dark: UInt32) {
        self.light = SRGB(hex: light)
        self.dark = SRGB(hex: dark)
    }

    /// Single-value colour that is legible in both appearances (used where one value genuinely
    /// clears both, e.g. the chat bubble fill).
    init(both hex: UInt32) {
        self.light = SRGB(hex: hex)
        self.dark = SRGB(hex: hex)
    }

    var color: Color {
        Color(UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        })
    }
}

enum Theme {

    // MARK: - Surfaces (the backgrounds every foreground below is audited against)

    /// `UIColor.systemBackground` — the fill of a grouped List row, and the page fill.
    static let surface = AppearancePair(light: 0xFFFFFF, dark: 0x000000)
    /// `UIColor.secondarySystemBackground` — grouped page fill in light, card/row fill in dark.
    static let surfaceSecondary = AppearancePair(light: 0xF2F2F7, dark: 0x1C1C1E)
    /// `UIColor.tertiarySystemBackground` — the citation chips in the assistant.
    static let surfaceTertiary = AppearancePair(light: 0xFFFFFF, dark: 0x2C2C2E)

    // MARK: - Semantic colours

    /// Positive, selected, actionable. Same deep green as `AccentColor` and the 3D selection
    /// ring, so "the app's colour" means one thing everywhere.
    ///
    /// This is the **fill/tint** accent — a non-text component, held to 3:1 (it measures
    /// 4.45:1 light on white, 7.75:1 dark on black). For accent-coloured *text* use
    /// `accentText`, which is darkened/lightened to clear 4.5:1; `AccentColor` itself is an
    /// asset catalogue entry the renderer also reads, so it isn't retuned here.
    static let accent = Color.accentColor

    /// The measured components of `AccentColor.colorset`, so the contrast test audits the real
    /// asset rather than a guess.
    static let accentComponents = AppearancePair(light: 0x0E8A3E, dark: 0x22B45C)

    /// Accent-coloured **text** ("Connected", "3 rooms captured"). Same hue as `accent`, pushed
    /// darker in light mode / lighter in dark mode so caption-sized text clears 4.5:1.
    static let accentText = AppearancePair(light: 0x0B7233, dark: 0x34D07A).color
    static let accentTextComponents = AppearancePair(light: 0x0B7233, dark: 0x34D07A)

    /// Something is wrong and the user should act: failed saves, invalid input, backend faults.
    /// Same red family as `DollhousePalette.warningBadge`, retuned per appearance for text.
    static let warning = AppearancePair(light: 0xC81E1E, dark: 0xF87171).color
    static let warningComponents = AppearancePair(light: 0xC81E1E, dark: 0xF87171)

    /// Worth noticing, not broken: a low-confidence scan item, a rejected edit, a caveat.
    ///
    /// Deliberately amber rather than SwiftUI's `.orange` (~#FF9500). At a glance the
    /// difference from a route (a cool blue line) and from the hazard ink is obvious — this is
    /// an amber ink for "worth noticing", not a system colour. The dark value is lighter
    /// (#F59E0B) because the light value reads at 3.39:1 on a dark row and fails AA.
    static let caution = AppearancePair(light: 0x9A4A08, dark: 0xF59E0B).color
    static let cautionComponents = AppearancePair(light: 0x9A4A08, dark: 0xF59E0B)

    // MARK: - Legend inks (the ONLY chrome allowed to show route / exit / hazard colour)
    //
    // These four mirror the 3D systems in `DollhousePalette` so a legend swatch and the thing
    // it labels read as the same idea. They are NOT the same hex values, and that is
    // deliberate: the renderer's colours are tuned against the white model under a key light,
    // these are tuned against iOS system backgrounds in both appearances. Two of them cannot
    // be bridged directly at all —
    //
    //   * `DollhousePalette.routePrimary` (#123FB0) measures **2.36:1 on black**, so it cannot
    //     be the dark-appearance value; the dark half is a lightened cobalt.
    //   * `DollhousePalette.hazardCore` (#F97316) measures **2.80:1 on white**, so it must
    //     never be used as a light-mode legend swatch or text; `hazardInk` is a darker ember
    //     that clears the bar in both appearances.
    //
    // Every pair below is asserted in `ThemeContrastTests` against the real surfaces.

    /// ONLY for swatches and legends that label an actual PRIMARY escape route. Never for state.
    /// Light half is `DollhousePalette.routePrimary` verbatim (8.88:1 on white).
    static let routeInk = routeInkComponents.color
    /// ONLY for swatches and legends that label the BACKUP route. Light half is
    /// `DollhousePalette.routeSecondary` verbatim (3.99:1 on white).
    static let routeSecondaryInk = routeSecondaryInkComponents.color
    /// ONLY for swatches and legends that label an actual exit.
    static let exitInk = exitInkComponents.color
    /// ONLY for swatches and legends that label the fire/hazard system.
    static let hazardInk = hazardInkComponents.color

    /// The measured components of the legend inks, audited as non-text components (3:1).
    static let routeInkComponents = AppearancePair(light: 0x123FB0, dark: 0x6FA8F5)
    /// Dimmer than `routeInkComponents.dark` on purpose, so the primary reads as the stronger
    /// ink in dark mode exactly as it does in light mode (8.88 vs 3.99 on white).
    static let routeSecondaryInkComponents = AppearancePair(light: 0x4180D4, dark: 0x4E97E8)
    /// Light half is `DollhousePalette.exitGreen` verbatim; the dark half is lightened because
    /// the (now darkened) 3D green measures 2.74:1 on #2C2C2E.
    static let exitInkComponents = AppearancePair(light: 0x0F8140, dark: 0x35B265)
    /// One value for both appearances: 5.18:1 on white and 4.06:1 on black. (It measures
    /// 2.69:1 on tertiarySystemBackground-dark #2C2C2E — the assistant's citation chips — so a
    /// hazard swatch does not belong there. Nothing places one there today.)
    static let hazardInkComponents = AppearancePair(both: 0xC2410C)

    /// Quiet supporting text. Named so screens stop reaching for `.secondary` in some places
    /// and `.gray` in others.
    ///
    /// No longer `Color.secondary`: iOS's `secondaryLabel` resolves to ~#8A8A8E on white, i.e.
    /// **3.44:1** — it fails AA for the caption-sized text every screen here uses it for. These
    /// values are the nearest neutral greys that clear 4.5:1 on both surfaces.
    static let supporting = AppearancePair(light: 0x6B6B70, dark: 0xAEAEB2).color
    static let supportingComponents = AppearancePair(light: 0x6B6B70, dark: 0xAEAEB2)

    /// The user's chat bubble fill. One value for both appearances: white-on-fill measures
    /// 5.04:1 (body text) while the fill itself clears 3:1 against both page backgrounds, so
    /// the bubble is distinguishable *and* its text is legible without an appearance fork.
    /// `Color.accentColor` was neither — white on the dark-mode accent was **2.71:1**.
    static let bubbleUser = AppearancePair(both: 0x1A7F45).color
    static let bubbleUserComponents = AppearancePair(both: 0x1A7F45)

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
            .accessibilityAddTraits(.isHeader)
    }

    /// Guarantees WCAG 2.2 SC 2.5.8 Target Size (Minimum) — 24×24pt — for controls whose
    /// natural size is just a glyph or a caption. Uses 44pt (Apple's HIG minimum, which
    /// subsumes 24) and makes the whole area tappable rather than only the drawn pixels.
    func minimumTapTarget(_ side: CGFloat = 44) -> some View {
        self.frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
    }
}
