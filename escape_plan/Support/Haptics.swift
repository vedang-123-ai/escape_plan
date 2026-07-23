//  Haptics.swift
//  escape_plan — S4.4 polish
//
//  One tiny funnel for haptic feedback so every screen speaks the same physical language:
//  light tick for steps, medium for starting something, success for a milestone. Simulator
//  calls are no-ops, so this costs nothing in tests.

import UIKit

enum Haptics {
    /// A small state change landed (routes arrived, checklist toggled).
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Something began (camera tour, drill step flight).
    static func begin() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// A milestone worth celebrating (drill practiced, plan complete).
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Something went wrong that the user should feel (request failed).
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
