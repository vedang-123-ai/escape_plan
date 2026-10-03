//  Haptics.swift
//  escape_plan — S4.4 polish; vocabulary widened 2026-09-07 (haptics on every interaction)
//
//  One tiny funnel for haptic feedback so every screen speaks the same physical language.
//  Simulator calls are no-ops, so this costs nothing in tests.
//
//      press      a control was pressed (buttons, rows, tiles, chips)        soft impact
//      selection  a choice moved between peers (tabs, segments, toggles)      selection
//      tick       a small state change landed (routes arrived, item done)    light impact
//      begin      something started (tour, fire drill, refresh)               medium impact
//      hold       a press-and-hold registered                                heavy impact
//      swipe      a swipe-revealed action fired                              rigid impact
//      success / warning / error                                            notifications
//
//  Buttons get `press` from their styles (`DSPressStyle`, `HapticPlainButtonStyle`,
//  `GlassChipButtonStyle`, `.hapticTap()` for system styles), so screens only call the rest.

import UIKit

enum Haptics {
    /// A control was pressed. Soft, so it reads as a click rather than an event.
    static func press() {
        impact(.soft)
    }

    /// A choice changed among peers: tab, segment, toggle, floor chip, picker row.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A small state change landed (routes arrived, checklist toggled).
    static func tick() {
        impact(.light)
    }

    /// Something began (camera tour, a fire simulation starting, pull-to-refresh).
    static func begin() {
        impact(.medium)
    }

    /// A press-and-hold registered (context menu, long-press shortcut).
    static func hold() {
        impact(.heavy)
    }

    /// A swipe-revealed action fired (row actions in lists).
    static func swipe() {
        impact(.rigid, intensity: 0.8)
    }

    /// A milestone worth celebrating (a task ticked, plan complete).
    static func success() {
        notify(.success)
    }

    /// Something went wrong that the user should feel (request failed).
    static func warning() {
        notify(.warning)
    }

    /// An action was rejected outright (invalid edit, blocked delete).
    static func error() {
        notify(.error)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle,
                               intensity: CGFloat = 1) {
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    private static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(kind)
    }
}

/// A generator kept warm for a rapid run of notches — the score gauge sweeping up. A fresh
/// generator per notch would miss most of them at 20 notches a second; this one is prepared
/// before the sweep and re-prepared after every notch.
@MainActor
final class HapticSweep {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    init() {
        generator.prepare()
    }

    /// One notch passed. `progress` (0…1) ramps the intensity, so the sweep feels like it fills.
    func tick(progress: Double) {
        generator.impactOccurred(intensity: 0.35 + 0.65 * max(0, min(1, progress)))
        generator.prepare()
    }

    /// The sweep landed: a firm stop, plus the success flourish for a strong score.
    func finish(celebrate: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if celebrate {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
