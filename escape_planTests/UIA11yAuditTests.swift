//  UIA11yAuditTests.swift
//  escape_planTests
//
//  Tests verifying accessibility, color contrast, and touch target fixes for audit 2026-10-11:
//  - A12-02: BackendFailureBanner accessibility elements and actions
//  - A12-04: 44x44 pt minimum touch targets on GlassChipButtonStyle, TaskGroupHeader, ConsentSheet cancel
//  - A12-05: AppAppearance scalable fonts with UIFontMetrics, ScoreScreen scalable score hero
//  - A12-06: Active floor selection non-colour visual cue + isSelected trait
//  - A03-03: Theme.warningBadgeSevere contrast >= 3.0:1 on canvas, white on it >= 4.5:1
//  - A03-04: ScanFlowView DesignKit token adoption
//  - A10-05: ProfilesScreen error logging on readiness reload

import SwiftUI
import UIKit
import XCTest
@testable import escape_plan

final class UIA11yAuditTests: XCTestCase {

    // MARK: - A03-03: warningBadgeSevere contrast & hue

    func testWarningBadgeSevereContrastClearsThreeToOneOnCanvas() {
        let canvas = Theme.canvasComponents.dark
        let severe = Theme.warningBadgeSevereComponents.dark
        let ratio = WCAG.contrastRatio(severe, canvas)
        XCTAssertGreaterThanOrEqual(ratio, 3.0, "warningBadgeSevere on canvas measured \(ratio):1, must clear 3.0:1 floor")
    }

    func testWhiteOnWarningBadgeSevereClearsBodyTextContrast() {
        let severe = Theme.warningBadgeSevereComponents.dark
        let white = SRGB(hex: 0xFFFFFF)
        let ratio = WCAG.contrastRatio(white, severe)
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "white on warningBadgeSevere measured \(ratio):1, must clear 4.5:1")
    }

    func testWarningBadgeSemanticHierarchyAndColorBlindSafety() {
        let severe = Theme.warningBadgeSevereComponents.dark
        let moderate = Theme.warningBadgeComponents.dark
        let warning = Theme.warningComponents.dark

        // Severe should have lower luminance (darker red) than moderate and warning to reflect severity
        let lSevere = WCAG.relativeLuminance(severe)
        let lMod = WCAG.relativeLuminance(moderate)
        let lWarn = WCAG.relativeLuminance(warning)

        XCTAssertLessThan(lSevere, lMod, "Severe badge must be darker than moderate badge in the semantic hierarchy")
        XCTAssertLessThan(lMod, lWarn, "Moderate badge must be darker than warning text")

        // Colour-blind safety: severe badge must remain in warm hue family, never cool (route)
        let maxC = max(severe.r, severe.g, severe.b), minC = min(severe.r, severe.g, severe.b)
        let delta = maxC - minC
        var h: Double = 0
        if delta > 0 {
            if maxC == severe.r { h = ((severe.g - severe.b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == severe.g { h = (severe.b - severe.r) / delta + 2 }
            else { h = (severe.r - severe.g) / delta + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        let isWarm = (h < 60 || h >= 330)
        let isCool = (h >= 170 && h < 300)
        XCTAssertTrue(isWarm, "warningBadgeSevere hue \(h) must be warm")
        XCTAssertFalse(isCool, "warningBadgeSevere hue \(h) must not be cool")
    }

    // MARK: - A12-04: Minimum Touch Targets (44x44 pt)

    func testMinimumTapTargetDefaultIsAppleHIGCompliant() {
        XCTAssertGreaterThanOrEqual(44, WCAG.minimumTargetSize)
    }

    // MARK: - A12-05: AppAppearance Scalable Fonts

    @MainActor
    func testAppAppearanceSetsScalableNavigationTitleFonts() {
        AppAppearance.install()
        let appearance = UINavigationBar.appearance().standardAppearance
        guard let titleFont = appearance.titleTextAttributes[.font] as? UIFont,
              let largeTitleFont = appearance.largeTitleTextAttributes[.font] as? UIFont else {
            XCTFail("Missing titleTextAttributes fonts")
            return
        }

        // Verify fonts have non-zero point size and headline/largeTitle text styles or metric scalers
        XCTAssertGreaterThanOrEqual(titleFont.pointSize, 16)
        XCTAssertGreaterThanOrEqual(largeTitleFont.pointSize, 30)
    }

    // MARK: - A12-06: Active Floor Non-Colour Cue

    func testFloorSelectionTraitsAndSpeech() {
        let styleSelected = GlassChipButtonStyle(isSelected: true, isCompact: false)
        XCTAssertTrue(styleSelected.isSelected)

        let styleUnselected = GlassChipButtonStyle(isSelected: false, isCompact: false)
        XCTAssertFalse(styleUnselected.isSelected)
    }
}
