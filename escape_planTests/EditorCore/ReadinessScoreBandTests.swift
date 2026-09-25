//  ReadinessScoreBandTests.swift — one set of score bands for Home and Score (audit
//  2026-09-25: they used 85/60 and 80/50, so the same score could read two different ways).

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class ReadinessScoreBandTests: XCTestCase {

    func testBoundariesAreInclusiveAtTheFloor() {
        XCTAssertEqual(ScoreBand(score: 100), .wellPrepared)
        XCTAssertEqual(ScoreBand(score: 85), .wellPrepared)
        XCTAssertEqual(ScoreBand(score: 84), .someGaps)
        XCTAssertEqual(ScoreBand(score: 60), .someGaps)
        XCTAssertEqual(ScoreBand(score: 59), .needsWork)
        XCTAssertEqual(ScoreBand(score: 0), .needsWork)
    }

    /// docs/preparedness-score-weights.md: any open high-severity item caps the composite at
    /// 40, which "strictly falls into the Needs work band". A band floor moved above that
    /// promise would break it silently.
    func testTheHighSeverityCapAlwaysReadsNeedsWork() {
        XCTAssertEqual(ScoreBand(score: 40), .needsWork)
        XCTAssertEqual(ScoreBand(score: 40).title, "Needs work")
    }

    /// The fixture scores in the weights doc (73 / 70 / 66) are all mid-band; a demo that
    /// reads "Well prepared" on an unedited fixture would overclaim.
    func testTheFixtureScoresAreMidBand() {
        for score in [73, 70, 66] {
            XCTAssertEqual(ScoreBand(score: score), .someGaps, "score \(score)")
        }
    }

    func testOutOfRangeScoresStillBand() {
        XCTAssertEqual(ScoreBand(score: -5), .needsWork)
        XCTAssertEqual(ScoreBand(score: 140), .wellPrepared)
    }

    func testEveryBandHasDistinctWordsAndGlyph() {
        let bands = ScoreBand.allCases
        XCTAssertEqual(Set(bands.map(\.title)).count, bands.count)
        XCTAssertEqual(Set(bands.map(\.symbol)).count, bands.count)
    }
}
