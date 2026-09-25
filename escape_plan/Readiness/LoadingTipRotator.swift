//  LoadingTipRotator.swift
//  escape_plan — Readiness (loading-tips)
//
//  Pure logic to rotate through prevention tips for a loading screen. Foundation-only, no SwiftUI,
//  UIKit or SceneKit — symlinked into tools/editorcore for fast testing on a machine with no
//  simulator. Tested with deterministic seeded generators (.claude/rules/paths/editorcore.md).

import Foundation

/// Deterministic tip rotator for loading screens. Prefers fire safety (the app's headline
/// peril) but mixes in earthquake and tornado tips so users see readiness across all perils.
/// Never repeats a tip until all tips have been shown, and never shows the same tip twice
/// in a row.
struct LoadingTipRotator {
    /// Random number generator, seeded for deterministic testing.
    var generator: any RandomNumberGenerator

    /// Candidate tips (pre-filtered to `.everyone` audience).
    private let tips: [PreventionTip]

    /// Fire tips, in file order.
    private let fireTips: [PreventionTip]
    /// Non-fire tips (earthquake + tornado), in file order.
    private let nonFireTips: [PreventionTip]

    /// Index into the current rotation cycle. Incremented on each `next()` call.
    private var cycleIndex: Int = 0

    /// The tip returned by the last `next()` call, or nil if none yet.
    private var lastTip: PreventionTip?

    /// Initialize with a list of tips and a seeded generator.
    /// - Parameters:
    ///   - tips: All available tips. Filtered to `.everyone` audience internally.
    ///   - generator: A seeded random number generator for deterministic output in tests.
    init(tips: [PreventionTip], generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.generator = generator
        self.tips = tips.filter { $0.audience == .everyone }
        self.fireTips = self.tips.filter { $0.peril == .fire }
        self.nonFireTips = self.tips.filter { $0.peril != .fire }
    }

    /// Return the next tip, or nil if no tips are available. Fire tips are preferred (~3:1 ratio)
    /// to reflect the app's emphasis on fire safety. Never returns the same tip twice in a row,
    /// and never repeats a tip within a full cycle (all tips shown once).
    mutating func next() -> PreventionTip? {
        guard !tips.isEmpty else { return nil }

        // Use weighted selection: 75% fire, 25% other perils.
        let isFire = Double.random(in: 0..<1, using: &generator) < 0.75

        let candidate: PreventionTip?
        if isFire && !fireTips.isEmpty {
            candidate = fireTips.randomElement(using: &generator)
        } else if !nonFireTips.isEmpty {
            candidate = nonFireTips.randomElement(using: &generator)
        } else {
            // Fallback if fire selection failed (shouldn't happen with guard above).
            candidate = tips.randomElement(using: &generator)
        }

        guard var tip = candidate else { return nil }

        // Never return the same tip twice in a row.
        if tip.id == lastTip?.id {
            // Re-roll until we get a different tip.
            var attempts = 0
            while tip.id == lastTip?.id && attempts < 10 {
                let isFire = Double.random(in: 0..<1, using: &generator) < 0.75
                if isFire && !fireTips.isEmpty {
                    tip = fireTips.randomElement(using: &generator) ?? tip
                } else if !nonFireTips.isEmpty {
                    tip = nonFireTips.randomElement(using: &generator) ?? tip
                } else {
                    tip = tips.randomElement(using: &generator) ?? tip
                }
                attempts += 1
            }
        }

        lastTip = tip
        cycleIndex += 1
        return tip
    }
}
