#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

import XCTest

final class LoadingTipRotatorTests: XCTestCase {

    func testNoRepeatUntilExhausted() {
        let tips = [
            PreventionTip(id: "tip1", peril: .fire, topic: "t", text: "Fire 1", cite: "s1", audience: .everyone),
            PreventionTip(id: "tip2", peril: .fire, topic: "t", text: "Fire 2", cite: "s2", audience: .everyone),
            PreventionTip(id: "tip3", peril: .fire, topic: "t", text: "Fire 3", cite: "s3", audience: .everyone),
        ]

        var rng = SeededRNG()
        var rotator = LoadingTipRotator(tips: tips, generator: rng)

        var seen: [String] = []
        for _ in 0..<10 {
            if let tip = rotator.next() {
                seen.append(tip.id)
            }
        }

        // In the first 3 calls, each tip should appear exactly once.
        let firstCycle = Array(seen.prefix(3))
        XCTAssertEqual(Set(firstCycle).count, 3, "Should see all three tips in first cycle")
    }

    func testNeverSameTipTwiceInRow() {
        let tips = [
            PreventionTip(id: "tip1", peril: .fire, topic: "t", text: "Fire 1", cite: "s1", audience: .everyone),
            PreventionTip(id: "tip2", peril: .fire, topic: "t", text: "Fire 2", cite: "s2", audience: .everyone),
            PreventionTip(id: "tip3", peril: .fire, topic: "t", text: "Fire 3", cite: "s3", audience: .everyone),
        ]

        var rng = SeededRNG()
        var rotator = LoadingTipRotator(tips: tips, generator: rng)

        var lastID: String?
        for _ in 0..<20 {
            if let tip = rotator.next() {
                if let last = lastID {
                    XCTAssertNotEqual(tip.id, last, "Should not repeat the same tip twice in a row")
                }
                lastID = tip.id
            }
        }
    }

    func testFirePreference() {
        // Fire tips outnumber other perils, and with weight 75%, fire should dominate the output.
        let fireTips = (0..<20).map { i in
            PreventionTip(id: "fire-\(i)", peril: .fire, topic: "t", text: "Fire", cite: "s", audience: .everyone)
        }
        let earthquakeTips = (0..<3).map { i in
            PreventionTip(id: "eq-\(i)", peril: .earthquake, topic: "t", text: "EQ", cite: "s", audience: .everyone)
        }
        let tornadoTips = (0..<3).map { i in
            PreventionTip(id: "tornado-\(i)", peril: .tornado, topic: "t", text: "Tornado", cite: "s", audience: .everyone)
        }
        let allTips = fireTips + earthquakeTips + tornadoTips

        var rng = SeededRNG()
        var rotator = LoadingTipRotator(tips: allTips, generator: rng)

        var fireCounts = 0
        var otherCounts = 0
        for _ in 0..<100 {
            if let tip = rotator.next() {
                if tip.peril == .fire {
                    fireCounts += 1
                } else {
                    otherCounts += 1
                }
            }
        }

        // With 75% fire preference, expect roughly 75 fire and 25 other (±10 is reasonable given RNG variance).
        XCTAssertGreaterThan(fireCounts, 60, "Fire should dominate with ~75% preference")
        XCTAssertLessThan(otherCounts, 40, "Non-fire tips should be minority with ~75% fire preference")
    }

    func testEveryoneAudienceFilter() {
        let tips = [
            PreventionTip(id: "everyone-tip", peril: .fire, topic: "t", text: "For all", cite: "s1", audience: .everyone),
            PreventionTip(id: "renter-tip", peril: .fire, topic: "t", text: "For renters", cite: "s2", audience: .renters),
            PreventionTip(id: "ca-tip", peril: .fire, topic: "t", text: "California", cite: "s3", audience: .california),
        ]

        var rng = SeededRNG()
        var rotator = LoadingTipRotator(tips: tips, generator: rng)

        // Only .everyone should be returned.
        for _ in 0..<5 {
            if let tip = rotator.next() {
                XCTAssertEqual(tip.audience, .everyone, "Should only return .everyone tips")
            }
        }
    }

    func testEmptyInputReturnsNil() {
        var rng = SeededRNG()
        var rotator = LoadingTipRotator(tips: [], generator: rng)

        let tip = rotator.next()
        XCTAssertNil(tip, "Empty tips should return nil")
    }

    func testEveryTipHasNonEmptyCite() {
        let tips = [
            PreventionTip(id: "tip1", peril: .fire, topic: "t", text: "Fire 1", cite: "source-1", audience: .everyone),
            PreventionTip(id: "tip2", peril: .earthquake, topic: "t", text: "EQ 1", cite: "source-2", audience: .everyone),
            PreventionTip(id: "tip3", peril: .tornado, topic: "t", text: "Tornado 1", cite: "source-3", audience: .everyone),
        ]

        var rng = SeededRNG()
        var rotator = LoadingTipRotator(tips: tips, generator: rng)

        for _ in 0..<10 {
            if let tip = rotator.next() {
                XCTAssertFalse(tip.cite.isEmpty, "Every returned tip must have a non-empty cite")
            }
        }
    }

    func testBundledTipsLoad() throws {
        guard let url = Bundle(for: type(of: self)).url(forResource: "prevention_tips", withExtension: "json"),
              let data = try Data(contentsOf: url) as Data?,
              let tips = try? PreventionTips.decode(from: data) else {
            XCTSkip("prevention_tips.json not found in test bundle")
            return
        }

        XCTAssertGreaterThan(tips.count, 0, "Should have loaded some tips")

        // Filter to .everyone tips.
        let everyoneTips = tips.filter { $0.audience == .everyone }
        XCTAssertGreaterThan(everyoneTips.count, 0, "Should have at least some .everyone tips")

        var rng = SeededRNG()
        var rotator = LoadingTipRotator(tips: tips, generator: rng)

        // Should be able to rotate through real tips without crash.
        for _ in 0..<5 {
            let tip = rotator.next()
            if let tip = tip {
                XCTAssertEqual(tip.audience, .everyone, "Should only return .everyone tips")
                XCTAssertFalse(tip.cite.isEmpty, "Real tips must have citations")
            }
        }
    }
}

// MARK: - Seeded RNG for deterministic testing

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64 = 0x4d595df4d0037a4d // Fixed seed for reproducibility

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
