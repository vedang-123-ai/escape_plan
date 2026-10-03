//  ThemeContrastTests.swift
//  escape_planTests
//
//  WCAG 2.2 AA contrast gate for the chrome palette, rewritten for the Linear dark-only revamp
//  (2026-09-25). The app has ONE appearance now: every `AppearancePair` in `Theme.swift` is built
//  with `both:`, and every foreground is measured against all four real surfaces it can land on —
//  canvas #08090A, card #111214, raised #1A1B1E, hover #232428 — against the target its role
//  demands:
//
//    SC 1.4.3 Contrast (Minimum) — 4.5:1 for text (every token here is used at caption size)
//    SC 1.4.11 Non-text Contrast — 3:1 for inks, fills and state indicators
//
//  `Theme.tertiary` is placeholder/disabled-only, so it is held to 3:1, not 4.5:1.
//
//  The earlier version of this file encoded the light/dark system-colour rules (the retired
//  route orange, the "chrome ink must equal the renderer colour" bridge, iOS's secondaryLabel on
//  white). Those rules were retired with the revamp (docs/decisions.md, 2026-09-25); what is kept
//  is the safety-colour guardrail: routes are cool, hazard is warm, exits are green — asserted by
//  hue family below, since the chrome inks are deliberately lightened for the dark canvas and can
//  no longer be byte-equal to the renderer's.
//
//  The maths lives in `Theme.swift` (`WCAG.relativeLuminance` / `WCAG.contrastRatio`) so the app
//  and the test can never disagree about what a ratio is.

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

    // MARK: - Helpers

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

    /// The four dark surfaces, darkest first. Every foreground can land on any of them.
    private let surfaces: [(String, SRGB)] = [
        ("canvas #08090A", Theme.canvasComponents.dark),
        ("card #111214", Theme.cardComponents.dark),
        ("raised #1A1B1E", Theme.raisedComponents.dark),
        ("hover #232428", Theme.hoverComponents.dark),
    ]

    private func assertOnEverySurface(_ pair: AppearancePair, named name: String,
                                      atLeast target: Double,
                                      file: StaticString = #filePath, line: UInt = #line) {
        for (surfaceName, surface) in surfaces {
            assertContrast(pair.dark, on: surface, atLeast: target,
                           "\(name) on \(surfaceName)", file: file, line: line)
        }
    }

    /// HSL hue in degrees, 0..<360. Grey (no chroma) reads as 0, which no test below relies on.
    private func hue(_ c: SRGB) -> Double {
        let maxC = max(c.r, c.g, c.b), minC = min(c.r, c.g, c.b)
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        var h: Double
        if maxC == c.r { h = ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maxC == c.g { h = (c.b - c.r) / delta + 2 }
        else { h = (c.r - c.g) / delta + 4 }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    /// The hue families the safety guardrail talks about. Bounds are generous on purpose: they
    /// are there to catch a route drawn in orange, not to police a shade of blue.
    private func isWarm(_ c: SRGB) -> Bool { let h = hue(c); return h < 60 || h >= 330 }
    private func isCool(_ c: SRGB) -> Bool { let h = hue(c); return h >= 170 && h < 300 }
    private func isBlue(_ c: SRGB) -> Bool { let h = hue(c); return h >= 190 && h < 260 }
    private func isGreen(_ c: SRGB) -> Bool { let h = hue(c); return h >= 90 && h < 170 }

    /// `SRGB` from a `UIColor`, so hue checks compare the REAL renderer values rather than a hex
    /// literal retyped into the test.
    private func srgb(_ color: UIColor) -> SRGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SRGB(r: Double(r), g: Double(g), b: Double(b))
    }

    // MARK: - One appearance

    /// Dark only: a pair whose halves differ would mean some screen still has a light value.
    func testEveryTokenIsSingleAppearance() {
        let pairs: [(String, AppearancePair)] = [
            ("canvas", Theme.canvasComponents), ("card", Theme.cardComponents),
            ("raised", Theme.raisedComponents), ("hover", Theme.hoverComponents),
            ("text", Theme.textComponents), ("supporting", Theme.supportingComponents),
            ("tertiary", Theme.tertiaryComponents), ("accent", Theme.accentComponents),
            ("accentText", Theme.accentTextComponents), ("success", Theme.successComponents),
            ("warning", Theme.warningComponents), ("caution", Theme.cautionComponents),
            ("routeInk", Theme.routeInkComponents),
            ("routeSecondaryInk", Theme.routeSecondaryInkComponents),
            ("exitInk", Theme.exitInkComponents), ("hazardInk", Theme.hazardInkComponents),
        ]
        for (name, pair) in pairs {
            XCTAssertEqual(pair.light, pair.dark, "Theme.\(name) has two appearances")
        }
    }

    // MARK: - Text (SC 1.4.3, 4.5:1 on every surface)

    func testEveryTextTokenClearsAAOnEverySurface() {
        let text: [(String, AppearancePair)] = [
            ("Theme.text", Theme.textComponents),
            ("Theme.supporting", Theme.supportingComponents),
            ("Theme.accentText", Theme.accentTextComponents),
            // State colours are also drawn as text: band captions, "−5 points", warnings.
            ("Theme.success", Theme.successComponents),
            ("Theme.warning", Theme.warningComponents),
            ("Theme.caution", Theme.cautionComponents),
        ]
        for (name, pair) in text {
            assertOnEverySurface(pair, named: name, atLeast: WCAG.Target.bodyText)
        }
    }

    /// Placeholder and disabled text only — it never carries meaning a reader needs, so the
    /// component floor is its bar, and it must still clear that.
    func testTertiaryIsPlaceholderGradeOnly() {
        assertOnEverySurface(Theme.tertiaryComponents, named: "Theme.tertiary",
                             atLeast: WCAG.Target.component)
    }

    // MARK: - Text on a coloured fill

    /// The primary button and the user's chat bubble draw white text on the accent. It used to
    /// fail (the old dark-mode accent measured 2.71:1); indigo #5E6AD2 carries it at 4.70:1.
    func testWhiteOnTheAccentClearsAA() {
        assertContrast(SRGB(hex: 0xFFFFFF), on: Theme.accentComponents.dark,
                       atLeast: WCAG.Target.bodyText, "white on Theme.accent")
        assertContrast(SRGB(hex: 0xFFFFFF), on: Theme.bubbleUserComponents.dark,
                       atLeast: WCAG.Target.bodyText, "white on Theme.bubbleUser")
        // The Delete swipe action in "Your homes" (S11.21): iOS 17/18 draw its label white on the tint.
        assertContrast(SRGB(hex: 0xFFFFFF), on: Theme.destructiveFillComponents.dark,
                       atLeast: WCAG.Target.bodyText, "white on Theme.destructiveFill")
    }

    // MARK: - Inks and state indicators (SC 1.4.11, 3:1 on every surface)

    func testEveryInkAndStateColourClearsNonTextContrastOnEverySurface() {
        let components: [(String, AppearancePair)] = [
            ("Theme.accent", Theme.accentComponents),
            ("Theme.success", Theme.successComponents),
            ("Theme.warning", Theme.warningComponents),
            ("Theme.caution", Theme.cautionComponents),
            ("Theme.routeInk", Theme.routeInkComponents),
            ("Theme.routeSecondaryInk", Theme.routeSecondaryInkComponents),
            ("Theme.exitInk", Theme.exitInkComponents),
            ("Theme.hazardInk", Theme.hazardInkComponents),
        ]
        for (name, pair) in components {
            assertOnEverySurface(pair, named: name, atLeast: WCAG.Target.component)
        }
    }

    /// The score bands (`Readiness/ScoreBand.swift`) colour the gauge, the pill and the band
    /// caption. As fills they need 3:1; as the caption they need 4.5:1 — on every surface.
    func testScoreBandColoursClearTextContrast() {
        for band in ScoreBand.allCases {
            let pair: AppearancePair
            switch band {
            case .wellPrepared: pair = Theme.successComponents
            case .someGaps: pair = Theme.cautionComponents
            case .needsWork: pair = Theme.warningComponents
            }
            assertOnEverySurface(pair, named: "band \(band.title)", atLeast: WCAG.Target.bodyText)
        }
    }

    // MARK: - Safety colours: cool = routes, warm = hazard, green = exits

    /// The chrome inks are lightened versions of the renderer's colours (tuned for a white model
    /// under a key light), so they can no longer be byte-equal. They must stay in the same hue
    /// family, or a legend would explain the 3D in colours it does not use.
    func testLegendInksStayInTheRendererHueFamilies() {
        XCTAssertTrue(isBlue(Theme.routeInkComponents.dark), "routeInk hue \(hue(Theme.routeInkComponents.dark))")
        XCTAssertTrue(isBlue(Theme.routeSecondaryInkComponents.dark),
                      "routeSecondaryInk hue \(hue(Theme.routeSecondaryInkComponents.dark))")
        XCTAssertTrue(isBlue(srgb(DollhousePalette.routePrimary)), "renderer routePrimary")
        XCTAssertTrue(isBlue(srgb(DollhousePalette.routeSecondary)), "renderer routeSecondary")

        XCTAssertTrue(isGreen(Theme.exitInkComponents.dark), "exitInk hue \(hue(Theme.exitInkComponents.dark))")
        XCTAssertTrue(isGreen(srgb(DollhousePalette.exitGreen)), "renderer exitGreen")

        XCTAssertTrue(isWarm(Theme.hazardInkComponents.dark), "hazardInk hue \(hue(Theme.hazardInkComponents.dark))")
        XCTAssertTrue(isWarm(srgb(DollhousePalette.hazardCore)), "renderer hazardCore")
    }

    /// The colour-blind-safe split the whole palette rests on: no route is ever drawn warm (the
    /// retired route orange is the precedent), and hazard is never drawn cool.
    func testNoRouteInkIsWarmAndHazardIsNotCool() {
        for (name, pair) in [("routeInk", Theme.routeInkComponents),
                             ("routeSecondaryInk", Theme.routeSecondaryInkComponents)] {
            XCTAssertFalse(isWarm(pair.dark), "\(name) is in the warm (hazard) family")
            XCTAssertTrue(isCool(pair.dark), "\(name) left the cool family")
        }
        XCTAssertFalse(isCool(Theme.hazardInkComponents.dark), "hazardInk is in the cool (route) family")
        XCTAssertFalse(isWarm(Theme.exitInkComponents.dark), "exitInk reads as hazard")
    }

    /// The primary must stay the stronger ink, or a legend showing both swatches inverts its own
    /// hierarchy.
    func testPrimaryRouteInkOutranksTheBackup() {
        for (surfaceName, surface) in surfaces {
            let primary = WCAG.contrastRatio(Theme.routeInkComponents.dark, surface)
            let backup = WCAG.contrastRatio(Theme.routeSecondaryInkComponents.dark, surface)
            XCTAssertGreaterThan(primary, backup,
                                 String(format: "%@: primary %.2f:1 vs backup %.2f:1",
                                        surfaceName, primary, backup))
        }
    }

    // MARK: - Target size (SC 2.5.8)

    func testMinimumTapTargetClearsTheStandard() {
        // `View.minimumTapTarget()` defaults to Apple's 44pt, which subsumes WCAG's 24pt floor.
        XCTAssertGreaterThanOrEqual(44, WCAG.minimumTargetSize)
    }
}
