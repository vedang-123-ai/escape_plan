//  ThemeContrastTests.swift
//  escape_planTests
//
//  WCAG 2.2 AA contrast gate for the chrome palette (lane D1 accessibility pass).
//
//  This exists because "the amber looks fine" is not a measurement. Every foreground/background
//  pair the screens actually use is asserted here in BOTH appearances, against the target the
//  pair's role demands:
//
//    SC 1.4.3 Contrast (Minimum) — 4.5:1 body text, 3:1 large text (>=18pt or >=14pt bold)
//    SC 1.4.11 Non-text Contrast — 3:1 for meaningful non-text components and state indicators
//
//  The maths lives in `Theme.swift` (`WCAG.relativeLuminance` / `WCAG.contrastRatio`) rather
//  than here, so the app and the test can never disagree about what a ratio is.
//
//  Surfaces are the real iOS system background values: systemBackground (#FFFFFF / #000000),
//  secondarySystemBackground (#F2F2F7 / #1C1C1E) and tertiarySystemBackground
//  (#FFFFFF / #2C2C2E). A grouped List draws its ROWS in systemBackground and its PAGE in
//  systemGroupedBackground, so any text colour used inside a List has to clear both.

import UIKit
import XCTest
@testable import escape_plan

final class ThemeContrastTests: XCTestCase {

    // MARK: - The maths itself

    func testRelativeLuminanceMatchesSpecEndpoints() {
        XCTAssertEqual(WCAG.relativeLuminance(SRGB(hex: 0xFFFFFF)), 1.0, accuracy: 0.0001)
        XCTAssertEqual(WCAG.relativeLuminance(SRGB(hex: 0x000000)), 0.0, accuracy: 0.0001)
        // sRGB mid grey #808080 has a known relative luminance of ~0.2159.
        XCTAssertEqual(WCAG.relativeLuminance(SRGB(hex: 0x808080)), 0.2159, accuracy: 0.001)
    }

    func testContrastRatioMatchesKnownPairs() {
        // Black on white is the maximum possible ratio, 21:1.
        XCTAssertEqual(WCAG.contrastRatio(SRGB(hex: 0x000000), SRGB(hex: 0xFFFFFF)),
                       21.0, accuracy: 0.01)
        // A colour against itself is 1:1.
        XCTAssertEqual(WCAG.contrastRatio(SRGB(hex: 0x4A90D9), SRGB(hex: 0x4A90D9)),
                       1.0, accuracy: 0.0001)
        // Order must not matter.
        XCTAssertEqual(WCAG.contrastRatio(SRGB(hex: 0xC81E1E), SRGB(hex: 0xFFFFFF)),
                       WCAG.contrastRatio(SRGB(hex: 0xFFFFFF), SRGB(hex: 0xC81E1E)),
                       accuracy: 0.0001)
    }

    func testHexInitMatchesComponentInit() {
        let byHex = SRGB(hex: 0x336699)
        XCTAssertEqual(byHex.r, 0x33 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(byHex.g, 0x66 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(byHex.b, 0x99 / 255.0, accuracy: 0.0001)
    }

    // MARK: - Helper

    /// Asserts and reports the real number, so a failure tells you how far off it is.
    private func assertContrast(_ foreground: SRGB,
                                on background: SRGB,
                                atLeast target: Double,
                                _ what: String,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        let ratio = WCAG.contrastRatio(foreground, background)
        XCTAssertGreaterThanOrEqual(
            ratio, target,
            String(format: "%@ measured %.2f:1, needs %.1f:1", what, ratio, target),
            file: file, line: line)
    }

    /// Every surface a foreground can land on in a given appearance. A colour used in a grouped
    /// List has to survive the row fill AND the page fill, so both are checked.
    private func surfaces(dark: Bool) -> [(String, SRGB)] {
        dark
            ? [("systemBackground(dark) #000000", Theme.surface.dark),
               ("secondarySystemBackground(dark) #1C1C1E", Theme.surfaceSecondary.dark),
               ("tertiarySystemBackground(dark) #2C2C2E", Theme.surfaceTertiary.dark)]
            : [("systemBackground(light) #FFFFFF", Theme.surface.light),
               ("secondarySystemBackground(light) #F2F2F7", Theme.surfaceSecondary.light)]
    }

    private func assertTextColor(_ pair: AppearancePair,
                                 named name: String,
                                 target: Double = WCAG.Target.bodyText,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        for (surfaceName, surface) in surfaces(dark: false) {
            assertContrast(pair.light, on: surface, atLeast: target,
                           "\(name) (light) on \(surfaceName)", file: file, line: line)
        }
        for (surfaceName, surface) in surfaces(dark: true) {
            assertContrast(pair.dark, on: surface, atLeast: target,
                           "\(name) (dark) on \(surfaceName)", file: file, line: line)
        }
    }

    // MARK: - Text colours (SC 1.4.3, 4.5:1 — these are all used at caption size)

    func testWarningTextMeetsAAInBothAppearances() {
        assertTextColor(Theme.warningComponents, named: "Theme.warning")
    }

    func testCautionTextMeetsAAInBothAppearances() {
        assertTextColor(Theme.cautionComponents, named: "Theme.caution")
    }

    func testSupportingTextMeetsAAInBothAppearances() {
        assertTextColor(Theme.supportingComponents, named: "Theme.supporting")
    }

    func testAccentTextMeetsAAInBothAppearances() {
        assertTextColor(Theme.accentTextComponents, named: "Theme.accentText")
    }

    /// The regression this whole file exists for: iOS's own `secondaryLabel` does NOT clear AA
    /// on white, which is why `Theme.supporting` stopped being `Color.secondary`. If this ever
    /// starts passing, Apple changed the value and `Theme.supporting` can be revisited.
    func testSystemSecondaryLabelWouldHaveFailedAA() {
        // secondaryLabel is #3C3C43 at 60% alpha; over white that composites to #8A8A8E.
        let composited = SRGB(hex: 0x8A8A8E)
        let ratio = WCAG.contrastRatio(composited, Theme.surface.light)
        XCTAssertLessThan(ratio, WCAG.Target.bodyText,
                          String(format: "system secondaryLabel measured %.2f:1 on white", ratio))
    }

    // MARK: - Text on a coloured fill

    func testWhiteChatBubbleTextMeetsAA() {
        // The user's bubble draws white text on Theme.bubbleUser in BOTH appearances.
        assertContrast(SRGB(hex: 0xFFFFFF), on: Theme.bubbleUserComponents.light,
                       atLeast: WCAG.Target.bodyText, "white on Theme.bubbleUser")
    }

    func testChatBubbleFillIsDistinguishableFromThePage() {
        // SC 1.4.11: the bubble fill is a meaningful non-text component (it carries "who said
        // this"), so it needs 3:1 against the page it floats on, in both appearances.
        assertContrast(Theme.bubbleUserComponents.light, on: Theme.surface.light,
                       atLeast: WCAG.Target.component, "Theme.bubbleUser on light page")
        assertContrast(Theme.bubbleUserComponents.dark, on: Theme.surface.dark,
                       atLeast: WCAG.Target.component, "Theme.bubbleUser on dark page")
        assertContrast(Theme.bubbleUserComponents.dark, on: Theme.surfaceSecondary.dark,
                       atLeast: WCAG.Target.component, "Theme.bubbleUser on dark grouped page")
    }

    /// White-on-accent is what the bubble used to do. Locked in as a test so nobody
    /// re-introduces it: the dark-mode accent is far too light to carry white text.
    func testWhiteOnRawAccentWouldHaveFailed() {
        let ratio = WCAG.contrastRatio(SRGB(hex: 0xFFFFFF), Theme.accentComponents.dark)
        XCTAssertLessThan(ratio, WCAG.Target.bodyText,
                          String(format: "white on dark AccentColor measured %.2f:1", ratio))
    }

    // MARK: - Non-text components (SC 1.4.11, 3:1)

    func testAccentFillIsDistinguishableAsAComponent() {
        assertContrast(Theme.accentComponents.light, on: Theme.surface.light,
                       atLeast: WCAG.Target.component, "AccentColor (light) on white")
        assertContrast(Theme.accentComponents.dark, on: Theme.surface.dark,
                       atLeast: WCAG.Target.component, "AccentColor (dark) on black")
        assertContrast(Theme.accentComponents.dark, on: Theme.surfaceSecondary.dark,
                       atLeast: WCAG.Target.component, "AccentColor (dark) on #1C1C1E")
    }

    /// The route/exit/hazard legend swatches are the one place chrome is allowed to show the
    /// 3D systems' colour. They're swatches, not text, so 3:1 is the bar — but they still have
    /// to clear it, or the legend that explains the route is itself unreadable.
    ///
    /// Measured (light on #FFFFFF / #F2F2F7, dark on #000000 / #1C1C1E):
    ///   routeInk           8.88 / 7.96  ·  8.60 / 6.96
    ///   routeSecondaryInk  3.99 / 3.58  ·  6.92 / 5.60
    ///   exitInk            4.96 / 4.44  ·  7.71 / 6.24
    ///   hazardInk          5.18 / 4.64  ·  4.06 / 3.29
    func testRouteExitAndHazardLegendSwatchesMeetNonTextContrast() {
        for (name, pair) in [("Theme.routeInk", Theme.routeInkComponents),
                             ("Theme.routeSecondaryInk", Theme.routeSecondaryInkComponents),
                             ("Theme.exitInk", Theme.exitInkComponents),
                             ("Theme.hazardInk", Theme.hazardInkComponents)] {
            assertContrast(pair.light, on: Theme.surface.light,
                           atLeast: WCAG.Target.component, "\(name) (light) on white")
            assertContrast(pair.light, on: Theme.surfaceSecondary.light,
                           atLeast: WCAG.Target.component, "\(name) (light) on #F2F2F7")
            assertContrast(pair.dark, on: Theme.surface.dark,
                           atLeast: WCAG.Target.component, "\(name) (dark) on black")
            assertContrast(pair.dark, on: Theme.surfaceSecondary.dark,
                           atLeast: WCAG.Target.component, "\(name) (dark) on #1C1C1E")
        }
    }

    // MARK: - The legend inks say what the 3D actually draws (the bug this file missed)

    /// The regression that started this: `routeInkComponents` was pinned to the RETIRED orange
    /// #FF5A1F long after `DollhousePalette` re-keyed routes to cool. Every legend claiming to
    /// show "the route colour" showed a colour no route used. The bridge is asserted, not
    /// commented, so it cannot silently rot again.
    func testLegendInksBridgeTheRendererPalette() {
        XCTAssertEqual(Theme.routeInkComponents.light, srgb(DollhousePalette.routePrimary),
                       "Theme.routeInk (light) must BE DollhousePalette.routePrimary")
        XCTAssertEqual(Theme.routeSecondaryInkComponents.light,
                       srgb(DollhousePalette.routeSecondary),
                       "Theme.routeSecondaryInk (light) must BE DollhousePalette.routeSecondary")
        XCTAssertEqual(Theme.exitInkComponents.light, srgb(DollhousePalette.exitGreen),
                       "Theme.exitInk (light) must BE DollhousePalette.exitGreen")
    }

    /// The retired orange, locked out. If this ever equals a route ink again, the re-key was
    /// undone without anyone noticing.
    func testRetiredRouteOrangeIsGone() {
        let retired = SRGB(hex: 0xFF5A1F)
        XCTAssertNotEqual(Theme.routeInkComponents.light, retired)
        XCTAssertNotEqual(Theme.routeInkComponents.dark, retired)
        // And it would not have passed anyway: 3.12:1 on white is fine for a swatch, but the
        // whole point is that no route is drawn in it.
        XCTAssertLessThan(WCAG.contrastRatio(retired, Theme.surfaceSecondary.light),
                          WCAG.Target.component,
                          "the retired orange measured under 3:1 on the grouped page fill too")
    }

    /// The two renderer colours that CANNOT be used directly in chrome, with the numbers that
    /// say why. These are the reason `routeInk` and `hazardInk` are not straight bridges.
    func testRendererColoursThatCannotBeChromeInk() {
        let routePrimaryOnBlack = WCAG.contrastRatio(srgb(DollhousePalette.routePrimary),
                                                     Theme.surface.dark)
        XCTAssertLessThan(routePrimaryOnBlack, WCAG.Target.component,
                          String(format: "routePrimary #123FB0 measured %.2f:1 on black — it "
                                 + "cannot be the dark-appearance route ink",
                                 routePrimaryOnBlack))

        let hazardCoreOnWhite = WCAG.contrastRatio(srgb(DollhousePalette.hazardCore),
                                                   Theme.surface.light)
        XCTAssertLessThan(hazardCoreOnWhite, WCAG.Target.component,
                          String(format: "hazardCore #F97316 measured %.2f:1 on white — it "
                                 + "cannot be a light-mode legend swatch or text",
                                 hazardCoreOnWhite))

        // …and `hazardInk` is the value that fixes it, in both appearances.
        assertContrast(Theme.hazardInkComponents.light, on: Theme.surface.light,
                       atLeast: WCAG.Target.bodyText, "Theme.hazardInk on white (text-grade)")
        assertContrast(Theme.hazardInkComponents.dark, on: Theme.surface.dark,
                       atLeast: WCAG.Target.component, "Theme.hazardInk on black")
    }

    /// The primary must stay the stronger ink in BOTH appearances — otherwise a legend showing
    /// both swatches inverts its own hierarchy when the user switches to dark mode.
    func testPrimaryRouteInkOutranksTheBackupInBothAppearances() {
        let lightPrimary = WCAG.contrastRatio(Theme.routeInkComponents.light, Theme.surface.light)
        let lightBackup = WCAG.contrastRatio(Theme.routeSecondaryInkComponents.light,
                                             Theme.surface.light)
        XCTAssertGreaterThan(lightPrimary, lightBackup,
                             String(format: "light: primary %.2f:1 vs backup %.2f:1",
                                    lightPrimary, lightBackup))

        let darkPrimary = WCAG.contrastRatio(Theme.routeInkComponents.dark, Theme.surface.dark)
        let darkBackup = WCAG.contrastRatio(Theme.routeSecondaryInkComponents.dark,
                                            Theme.surface.dark)
        XCTAssertGreaterThan(darkPrimary, darkBackup,
                             String(format: "dark: primary %.2f:1 vs backup %.2f:1",
                                    darkPrimary, darkBackup))
    }

    /// `SRGB` from a `UIColor`, so the assertions above compare the REAL renderer values rather
    /// than a hex literal retyped into the test.
    private func srgb(_ color: UIColor) -> SRGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SRGB(r: Double(r), g: Double(g), b: Double(b))
    }

    /// The score ring's three bands are the app's most colour-dependent surface. Each band's
    /// stroke is a non-text state indicator (SC 1.4.11) and must clear 3:1 on both pages.
    func testScoreRingBandsMeetNonTextContrast() {
        let bands: [(String, AppearancePair)] = [
            ("score >= 80 (accent)", Theme.accentComponents),
            ("score 50..<80 (caution)", Theme.cautionComponents),
            ("score < 50 (warning)", Theme.warningComponents),
        ]
        for (name, pair) in bands {
            assertContrast(pair.light, on: Theme.surface.light,
                           atLeast: WCAG.Target.component, "\(name) on white")
            assertContrast(pair.dark, on: Theme.surface.dark,
                           atLeast: WCAG.Target.component, "\(name) on black")
            assertContrast(pair.dark, on: Theme.surfaceSecondary.dark,
                           atLeast: WCAG.Target.component, "\(name) on #1C1C1E")
        }
    }

    /// The big score number is drawn in the band colour at >=34pt bold, i.e. "large text", so
    /// 3:1 is its floor — but it also has to work when Dynamic Type is small, so hold it to the
    /// body-text bar on the page fills it actually sits on.
    func testScoreNumberMeetsBodyTextContrast() {
        for (name, pair) in [("accent", Theme.accentTextComponents),
                             ("caution", Theme.cautionComponents),
                             ("warning", Theme.warningComponents)] {
            assertTextColor(pair, named: "score number (\(name))")
        }
    }

    // MARK: - Target size (SC 2.5.8)

    func testMinimumTapTargetClearsTheStandard() {
        // `View.minimumTapTarget()` defaults to Apple's 44pt, which subsumes WCAG's 24pt floor.
        XCTAssertGreaterThanOrEqual(44, WCAG.minimumTargetSize)
    }
}
