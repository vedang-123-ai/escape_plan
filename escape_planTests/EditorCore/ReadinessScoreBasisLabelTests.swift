//  ReadinessScoreBasisLabelTests.swift — the code-quantified / guidance-based label (S11.2's
//  ScoreBreakdown.basis), rendered honestly on the per-peril score (S11.5).

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class ReadinessScoreBasisLabelTests: XCTestCase {

    func testFireIsCodeQuantified() {
        let basis = ["fire": "code_quantified", "earthquake": "guidance_based",
                     "severe_weather": "guidance_based"]
        XCTAssertEqual(ScoreBasisLabel.label(for: "fire", basis: basis), "Code-quantified")
    }

    func testEarthquakeAndSevereWeatherAreGuidanceBased() {
        let basis = ["fire": "code_quantified", "earthquake": "guidance_based",
                     "severe_weather": "guidance_based"]
        XCTAssertEqual(ScoreBasisLabel.label(for: "earthquake", basis: basis), "Guidance-based")
        XCTAssertEqual(ScoreBasisLabel.label(for: "severe_weather", basis: basis), "Guidance-based")
    }

    func testNilBasisDictionaryProducesNoLabel() {
        // A server predating S11.2 omits `basis` entirely — must show nothing, never guess.
        XCTAssertNil(ScoreBasisLabel.label(for: "fire", basis: nil))
    }

    func testMissingPerilKeyProducesNoLabel() {
        XCTAssertNil(ScoreBasisLabel.label(for: "severe_weather", basis: ["fire": "code_quantified"]))
    }

    func testUnrecognisedValueProducesNoLabelRatherThanInventingATier() {
        XCTAssertNil(ScoreBasisLabel.label(for: "fire", basis: ["fire": "some_future_tier"]))
    }

    func testNeverBlursTheTwoTiersIntoEachOther() {
        // The one invariant this whole file exists to hold: fire must never read as
        // guidance-based, and earthquake/tornado must never read as code-quantified.
        let basis = ["fire": "code_quantified", "earthquake": "guidance_based"]
        XCTAssertNotEqual(ScoreBasisLabel.label(for: "fire", basis: basis),
                          ScoreBasisLabel.label(for: "earthquake", basis: basis))
    }
}
