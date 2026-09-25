//  LoadingTipRotatorTests.swift
//  Runs in both the app test target and tools/editorcore (`swift test`, no simulator).

import XCTest
#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class LoadingTipRotatorTests: XCTestCase {

    private func tip(_ id: String, _ peril: PreventionTip.Peril = .fire,
                     _ audience: PreventionTip.Audience = .everyone) -> PreventionTip {
        PreventionTip(id: id, peril: peril, topic: "t", text: "Text \(id)", cite: "src-\(id)", audience: audience)
    }

    private func mixed(fire: Int, other: Int) -> [PreventionTip] {
        (0..<fire).map { tip("f\($0)") }
            + (0..<other).map { tip("o\($0)", $0.isMultiple(of: 2) ? .earthquake : .tornado) }
    }

    /// The real corpus file, read from the source tree so the package build needs no bundle.
    /// Walks up because `#filePath` differs per build: the app sees escape_planTests/EditorCore,
    /// the package sees the symlink under tools/editorcore/Tests.
    private func realTips() throws -> [PreventionTip] {
        let relative = "escape_plan/Resources/prevention_tips.json"
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try PreventionTips.decode(from: Data(contentsOf: candidate))
            }
            dir.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    func testEachCycleShowsEveryTipExactlyOnce() {
        let tips = mixed(fire: 9, other: 4)
        var rotator = LoadingTipRotator(tips: tips, generator: SeededRNG(seed: 7))
        for cycle in 0..<5 {
            let ids = (0..<tips.count).compactMap { _ in rotator.next()?.id }
            XCTAssertEqual(Set(ids), Set(tips.map(\.id)), "cycle \(cycle) missed or repeated a tip")
            XCTAssertEqual(ids.count, tips.count)
        }
    }

    func testNeverTheSameTipTwiceInARowAcrossCycleBoundaries() {
        for seed in UInt64(1)...50 {
            var rotator = LoadingTipRotator(tips: mixed(fire: 2, other: 1), generator: SeededRNG(seed: seed))
            var last: String?
            for _ in 0..<30 {
                let id = rotator.next()?.id
                XCTAssertNotEqual(id, last, "seed \(seed) repeated \(id ?? "nil")")
                last = id
            }
        }
    }

    func testFireIsFrontLoadedButOtherPerilsStillAppear() {
        // Equal counts, so any fire majority early in a cycle comes from the weighting alone.
        var early = (fire: 0, other: 0)
        for seed in UInt64(1)...200 {
            var rotator = LoadingTipRotator(tips: mixed(fire: 10, other: 10), generator: SeededRNG(seed: seed))
            for _ in 0..<5 {
                if rotator.next()?.peril == .fire { early.fire += 1 } else { early.other += 1 }
            }
        }
        XCTAssertGreaterThan(early.fire, early.other * 2, "first draws should favour fire ~3:1")
        XCTAssertGreaterThan(early.other, 0, "earthquake and tornado must still appear early")
    }

    func testOnlyEveryoneAudienceTipsAreShown() {
        let tips = [tip("a"), tip("r", .fire, .renters), tip("c", .fire, .california), tip("b", .tornado)]
        var rotator = LoadingTipRotator(tips: tips, generator: SeededRNG(seed: 3))
        XCTAssertEqual(rotator.cycleLength, 2)
        let ids = Set((0..<10).compactMap { _ in rotator.next()?.id })
        XCTAssertEqual(ids, ["a", "b"])
    }

    func testNoTipsMeansNil() {
        var rotator = LoadingTipRotator(tips: [tip("r", .fire, .renters)], generator: SeededRNG(seed: 1))
        XCTAssertEqual(rotator.cycleLength, 0)
        XCTAssertNil(rotator.next())
    }

    func testSingleTipRepeatsRatherThanStalling() {
        var rotator = LoadingTipRotator(tips: [tip("only")], generator: SeededRNG(seed: 1))
        XCTAssertEqual(rotator.next()?.id, "only")
        XCTAssertEqual(rotator.next()?.id, "only")
    }

    func testRealCorpusTipsRotateVerbatimWithTheirCitations() throws {
        let all = try realTips()
        let everyone = all.filter { $0.audience == .everyone }
        XCTAssertGreaterThan(everyone.count, 10, "the loading screen needs a real pool of general tips")
        XCTAssertTrue(everyone.contains { $0.peril == .fire })

        var rotator = LoadingTipRotator(tips: all, generator: SeededRNG(seed: 11))
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        for _ in 0..<(everyone.count * 2) {
            let shown = try XCTUnwrap(rotator.next())
            XCTAssertEqual(shown, byID[shown.id], "a tip must be shown exactly as the corpus wrote it")
            XCTAssertFalse(shown.cite.isEmpty)
        }
    }
}

/// SplitMix64: small, seedable, and good enough that different seeds give different orders.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
