//  LoadingTipRotator.swift
//  escape_plan — Readiness (loading-tips)
//
//  Picks which cited prevention tip a loading screen shows next. Foundation-only: this folder
//  is symlinked into tools/editorcore, so the ordering rules run under `swift test` with no
//  simulator (.claude/rules/paths/editorcore.md). The SwiftUI side is
//  Screens/Components/LoadingTipView.swift.

import Foundation

/// A shuffle bag over the `.everyone` tips.
///
/// Every cycle shows each tip exactly once, in an order that front-loads fire (the app's
/// headline peril): while both kinds remain in the bag, the next draw is fire with
/// probability `fireWeight`. A new cycle never opens on the tip the last one closed with.
///
/// Tip text is shown verbatim and always with its `cite` — this type only chooses the order.
struct LoadingTipRotator {
    /// Chance the next draw is a fire tip while both fire and non-fire tips remain.
    static let fireWeight = 0.75

    private let fireTips: [PreventionTip]
    private let otherTips: [PreventionTip]
    private var generator: any RandomNumberGenerator
    private var bag: [PreventionTip] = []
    private var lastID: String?

    init(tips: [PreventionTip], generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        let everyone = tips.filter { $0.audience == .everyone }
        fireTips = everyone.filter { $0.peril == .fire }
        otherTips = everyone.filter { $0.peril != .fire }
        self.generator = generator
    }

    /// Tips per cycle; `next()` returns nil forever when this is 0.
    var cycleLength: Int { fireTips.count + otherTips.count }

    mutating func next() -> PreventionTip? {
        guard cycleLength > 0 else { return nil }
        if bag.isEmpty { refill() }
        let tip = bag.removeFirst()
        lastID = tip.id
        return tip
    }

    private mutating func refill() {
        var fire = fireTips.shuffled(using: &generator)
        var other = otherTips.shuffled(using: &generator)
        var order: [PreventionTip] = []
        order.reserveCapacity(cycleLength)
        while !fire.isEmpty || !other.isEmpty {
            let takeFire: Bool
            if fire.isEmpty {
                takeFire = false
            } else if other.isEmpty {
                takeFire = true
            } else {
                takeFire = Double.random(in: 0..<1, using: &generator) < Self.fireWeight
            }
            order.append(takeFire ? fire.removeFirst() : other.removeFirst())
        }
        if order.count > 1, order[0].id == lastID {
            order.swapAt(0, 1)
        }
        bag = order
    }
}
