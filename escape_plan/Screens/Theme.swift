//  Theme.swift
//  Screens — the semantic colour and type scale for app chrome.
//
//  ## The Linear revamp (2026-09-25)
//
//  The app is **dark only** and draws from one Linear-style palette: a near-black canvas, two
//  raised greys, hairline borders, high-contrast neutral text and a single indigo accent used
//  sparingly — primary actions, selection, focus. Everything that used to be the deep safety
//  green (the old accent) is indigo now; "done / positive" gets its own `success` green so
//  state and action stop sharing a colour. The previous light/dark system-colour pairs and the
//  "no new colour" rule were retired on purpose (decisions.md, 2026-09-25); three guardrails
//  were kept and are asserted in `ThemeContrastTests`:
//
//  1. **Safety colours stay distinct and colour-blind-safe.** Cool hues are routes, warm hues
//     are hazard, everywhere. Route inks are the cobalt family the 3D model draws (lightened
//     for a dark canvas); `hazardInk` is the only warm ink allowed on chrome; exits are green.
//     Advisories use `caution` yellow, faults use `warning` red.
//  2. **Accessibility floors.** Text clears 4.5:1 on every surface it can land on, components
//     3:1, targets 44pt, and every size is a Dynamic Type style.
//  3. **Engineering constraints** — unchanged, and not about colour (CameraRigModel stays pure).
//
//  `AppearancePair` survives because the WCAG tests read raw components from it; with one
//  appearance, every pair is built with `both:`.

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

    /// `SRGB(hex: 0x5E6AD2)`.
    init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255,
                  g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// WCAG 2.2 relative luminance and contrast ratio, straight from the spec
/// (https://www.w3.org/TR/WCAG22/#dfn-relative-luminance, #dfn-contrast-ratio).
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

/// A colour plus its raw components, so a test can measure it without a trait collection.
/// The app is dark only, so both halves are always the same value (`both:`); the two-value
/// initialiser stays for the tests' own fixtures.
struct AppearancePair: Sendable {
    let light: SRGB
    let dark: SRGB

    init(light: UInt32, dark: UInt32) {
        self.light = SRGB(hex: light)
        self.dark = SRGB(hex: dark)
    }

    init(both hex: UInt32) {
        self.light = SRGB(hex: hex)
        self.dark = SRGB(hex: hex)
    }

    var color: Color { dark.color }
    var uiColor: UIColor { UIColor(red: dark.r, green: dark.g, blue: dark.b, alpha: 1) }
}

enum Theme {

    // MARK: - Surfaces, darkest first (every foreground below is audited against all four)

    /// The page. Near-black, very slightly cool.
    static let canvasComponents = AppearancePair(both: 0x08090A)
    /// Cards, rows, sheets.
    static let cardComponents = AppearancePair(both: 0x111214)
    /// Inset controls inside a card: secondary buttons, tracks, chips, text fields.
    static let raisedComponents = AppearancePair(both: 0x1A1B1E)
    /// A pressed or selected row, and the top of the raised stack.
    static let hoverComponents = AppearancePair(both: 0x232428)

    static let canvas = canvasComponents.color
    static let card = cardComponents.color
    static let raised = raisedComponents.color
    static let hover = hoverComponents.color

    /// Hairline borders. Decorative (the surfaces already differ), so no contrast target.
    static let border = AppearancePair(both: 0x232428).color
    /// A border that has to be seen: focused fields, the selected segment.
    static let borderStrong = AppearancePair(both: 0x34363C).color

    /// Legacy names, kept so the tests and the older screens resolve to the new surfaces.
    static let surface = canvasComponents
    static let surfaceSecondary = cardComponents
    static let surfaceTertiary = raisedComponents

    // MARK: - Text

    /// Headings and body.
    static let text = textComponents.color
    static let textComponents = AppearancePair(both: 0xF7F8F8)
    /// Supporting text — metadata, captions, secondary labels. Clears 4.5:1 on every surface.
    static let supporting = supportingComponents.color
    static let supportingComponents = AppearancePair(both: 0x9CA0A8)
    /// Placeholder and disabled text ONLY: it clears 3:1, not 4.5:1, so it never carries meaning
    /// a reader needs.
    static let tertiary = tertiaryComponents.color
    static let tertiaryComponents = AppearancePair(both: 0x6B6F76)

    // MARK: - Accent (indigo)

    /// Fills: primary buttons, selection, focus rings, the user's chat bubble. White text on it
    /// measures 4.70:1.
    static let accent = accentComponents.color
    static let accentComponents = AppearancePair(both: 0x5E6AD2)
    /// Accent-coloured text and glyphs on a dark surface ("Show details", links).
    static let accentText = accentTextComponents.color
    static let accentTextComponents = AppearancePair(both: 0x8B93F0)

    // MARK: - State

    /// Done, passing, connected. Separate from the accent so "tap this" and "this is fine" never
    /// share a colour.
    static let success = successComponents.color
    static let successComponents = AppearancePair(both: 0x4CB782)

    /// Something is wrong and the user should act: failed saves, invalid input, critical findings.
    static let warning = warningComponents.color
    static let warningComponents = AppearancePair(both: 0xEF6363)

    /// The fill behind a destructive control's WHITE label, e.g. a list row's Delete swipe action.
    /// `warning` carries white at only ~3.5:1; this darker red carries it at 5.06:1 (S11.21).
    static let destructiveFill = destructiveFillComponents.color
    static let destructiveFillComponents = AppearancePair(both: 0xC93A3A)

    /// Worth noticing, not broken: a low-confidence scan item, a caveat, "to do".
    static let caution = cautionComponents.color
    static let cautionComponents = AppearancePair(both: 0xE8B93C)

    // MARK: - Legend inks (the ONLY chrome allowed to show route / exit / hazard colour)
    //
    // They label the 3D systems, so they stay in the same hue families the renderer draws:
    // cobalt routes, green exits, ember hazard. The renderer's own values are tuned for a white
    // model under a key light; these are lightened for the dark canvas. Asserted as non-text
    // components (3:1) in `ThemeContrastTests`.

    /// ONLY for swatches and legends that label an actual PRIMARY escape route. Never for state.
    static let routeInk = routeInkComponents.color
    /// ONLY for swatches and legends that label the BACKUP route.
    static let routeSecondaryInk = routeSecondaryInkComponents.color
    /// ONLY for swatches and legends that label an actual exit.
    static let exitInk = exitInkComponents.color
    /// ONLY for swatches and legends that label the fire/hazard system.
    static let hazardInk = hazardInkComponents.color

    static let routeInkComponents = AppearancePair(both: 0x6FA8F5)
    /// Dimmer than the primary on purpose, so the primary reads as the stronger ink.
    static let routeSecondaryInkComponents = AppearancePair(both: 0x3F7FCF)
    static let exitInkComponents = AppearancePair(both: 0x3FBF74)
    static let hazardInkComponents = AppearancePair(both: 0xF2742B)

    /// The user's chat bubble: the accent itself.
    static let bubbleUser = accent
    static let bubbleUserComponents = accentComponents

    // MARK: - Type scale (all Dynamic Type styles)

    /// Large page heading inside a scroll view.
    static let largeTitle = Font.title2.weight(.semibold)
    /// Screen-level heading inside a scroll view (not the navigation title).
    static let screenTitle = Font.title3.weight(.semibold)
    /// Card titles, row titles.
    static let rowTitle = Font.subheadline.weight(.medium)
    /// The label above a group of rows or controls.
    static let sectionHeader = Font.footnote.weight(.medium)
    /// A single number the screen exists to show — the preparedness score, a room count.
    static let metric = Font.system(.largeTitle, design: .default).weight(.semibold)
    /// Body copy in a card.
    static let cardBody = Font.subheadline
    /// Captions, footnotes, banner text.
    static let detail = Font.caption

    // MARK: - Geometry

    static let radiusSmall: CGFloat = 6
    static let radius: CGFloat = 10
    static let radiusLarge: CGFloat = 14
    static let hairline: CGFloat = 1
}

extension View {
    /// The label above a group: small, medium weight, secondary ink. Sentence case, as Linear
    /// does — the old uppercase tracking read as a different, louder app.
    func sectionHeaderStyle() -> some View {
        self.font(Theme.sectionHeader)
            .foregroundStyle(Theme.supporting)
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
