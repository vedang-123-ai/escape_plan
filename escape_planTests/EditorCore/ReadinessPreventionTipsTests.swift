//  ReadinessPreventionTipsTests.swift — decode and selection logic for the Home tab's
//  "Prevent" section (S11.5). No tip may decode without a citation; no fourth peril may
//  silently appear; an unrecognised audience must not take down the whole array.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class ReadinessPreventionTipsTests: XCTestCase {

    private static let sampleJSON = #"""
    {
      "schema_version": "1.0",
      "description": "test fixture",
      "fields": {},
      "tips": [
        {
          "id": "fire-meeting-place",
          "peril": "fire",
          "topic": "escape-plan",
          "text": "Pick one meeting place outside.",
          "cite": "nfpa-escape-planning",
          "audience": "everyone"
        },
        {
          "id": "fire-renter-note",
          "peril": "fire",
          "topic": "escape-plan",
          "text": "Renters should still plan two ways out.",
          "cite": "usfa-escape-plans",
          "audience": "renters"
        },
        {
          "id": "earthquake-drop-cover-hold",
          "peril": "earthquake",
          "topic": "during-quake",
          "text": "Drop, cover and hold on.",
          "cite": "shakeout-guidance",
          "audience": "everyone"
        },
        {
          "id": "tornado-shelter",
          "peril": "tornado",
          "topic": "during-tornado",
          "text": "Go to the lowest floor, small interior room.",
          "cite": "noaa-tornado-shelter",
          "audience": "mobile-home"
        },
        {
          "id": "future-audience-tip",
          "peril": "fire",
          "topic": "escape-plan",
          "text": "A tip whose audience this build does not know about yet.",
          "cite": "nfpa-escape-planning",
          "audience": "assisted-living"
        }
      ]
    }
    """#

    private func decode() throws -> [PreventionTip] {
        try PreventionTips.decode(from: Data(Self.sampleJSON.utf8))
    }

    func testDecodesEveryTipWithItsCitation() throws {
        let tips = try decode()
        XCTAssertEqual(tips.count, 5)
        for tip in tips {
            XCTAssertFalse(tip.cite.isEmpty, "\(tip.id) decoded with no citation")
        }
    }

    func testUnknownAudienceFallsBackRatherThanFailingTheWholeDecode() throws {
        let tips = try decode()
        let unknown = try XCTUnwrap(tips.first { $0.id == "future-audience-tip" })
        XCTAssertEqual(unknown.audience, .other)
    }

    func testKnownAudiencesDecodeToTheirCase() throws {
        let tips = try decode()
        XCTAssertEqual(tips.first { $0.id == "fire-renter-note" }?.audience, .renters)
        XCTAssertEqual(tips.first { $0.id == "tornado-shelter" }?.audience, .mobileHome)
    }

    func testTipsForPerilFiltersToExactlyThatPeril() throws {
        let tips = try decode()
        let fire = PreventionTipsFilter.tips(tips, peril: .fire)
        XCTAssertEqual(fire.count, 3)
        XCTAssertTrue(fire.allSatisfy { $0.peril == .fire })
    }

    func testSpotlightPicksOneEverywherePeril() throws {
        let tips = try decode()
        let spotlight = PreventionTipsFilter.spotlight(tips)
        XCTAssertEqual(spotlight.count, 3, "one per locked peril: fire, earthquake, tornado")
        XCTAssertEqual(spotlight.map(\.peril).sorted(by: { $0.rawValue < $1.rawValue }),
                       [.earthquake, .fire, .tornado].sorted(by: { $0.rawValue < $1.rawValue }))
        // Fire's "everyone" tip is fire-meeting-place, not the renter-audience one, even
        // though the renter tip appears first in a differently-ordered array.
        XCTAssertEqual(spotlight.first { $0.peril == .fire }?.id, "fire-meeting-place")
    }

    func testSpotlightFallsBackWhenAPerilHasNoEveryoneTip() throws {
        let tips = try decode()
        // Tornado's only tip in the fixture is mobile-home audience, not "everyone".
        let spotlight = PreventionTipsFilter.spotlight(tips)
        XCTAssertEqual(spotlight.first { $0.peril == .tornado }?.id, "tornado-shelter")
    }

    func testSpotlightIsDeterministicAcrossRepeatedCalls() throws {
        let tips = try decode()
        let first = PreventionTipsFilter.spotlight(tips)
        let second = PreventionTipsFilter.spotlight(tips)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    /// The real bundled/corpus file — the shape this app actually ships, not just the inline
    /// fixture above. Guards against the model mirror drifting from the corpus's real fields.
    func testDecodesTheRealCorpusFile() throws {
        let url = Fixtures.repoRoot.appendingPathComponent("backend/corpus/prevention_tips.json")
        let data = try Data(contentsOf: url)
        let tips = try PreventionTips.decode(from: data)
        XCTAssertFalse(tips.isEmpty)
        for tip in tips {
            XCTAssertFalse(tip.cite.isEmpty, "\(tip.id) has no citation")
        }
        // Exactly the three locked perils — a fourth would fail to decode entirely, but this
        // also confirms the spotlight has something to show for every one of them.
        let spotlight = PreventionTipsFilter.spotlight(tips)
        XCTAssertEqual(Set(spotlight.map(\.peril)), Set(PreventionTip.Peril.allCases))
    }
}
