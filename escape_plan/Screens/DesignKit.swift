//  DesignKit.swift
//  escape_plan
//
//  The shared component vocabulary — cards, pills, buttons, icon tiles — in the Linear-style
//  dark revamp (2026-09-25). Every screen draws its surfaces from here so the look stays one
//  system. Colours are aliases onto `Theme`, the single palette.
//

import SwiftUI

enum DS {

    // MARK: Page & text — aliases onto `Theme`, so every screen built on DS follows the revamp.

    static let pageTop = Theme.canvas
    static let pageBottom = Theme.canvas
    static var pageGradient: LinearGradient {
        LinearGradient(colors: [pageTop, pageBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Headline/label ink.
    static let ink = Theme.text
    /// Paragraph ink inside cards: the same neutral as `ink`, one step quieter.
    static let bodyInk = AppearancePair(both: 0xD0D3D8).color
    static let supporting = Theme.supporting

    /// Card surface.
    static let card = Theme.card
    /// Inset fill inside a card (secondary buttons, tracks).
    static let inset = Theme.raised
    /// Progress track.
    static let track = Theme.raised
    static let border = Theme.border

    /// Tinted fills behind icons and status pills: the state colour at low opacity, so the
    /// glyph on top stays the full-strength ink.
    static let criticalFill = Theme.warning.opacity(0.14)
    static let cautionFill = Theme.caution.opacity(0.14)
    static let accentFill = Theme.accent.opacity(0.18)
    static let successFill = Theme.success.opacity(0.14)

    // MARK: Geometry

    static let cardRadius: CGFloat = Theme.radiusLarge
    static let cardRadiusLarge: CGFloat = Theme.radiusLarge
    static let modelRadius: CGFloat = 16
    static let buttonRadius: CGFloat = Theme.radius
    static let pagePadding: CGFloat = 16

    /// Linear draws no drop shadows on dark: depth is surface steps plus a hairline.
    static let shadowColor = Color.clear
}

extension View {
    /// The page background, edge to edge.
    func dsPage() -> some View {
        self.background(Theme.canvas.ignoresSafeArea())
    }

    /// The one card treatment: card surface, continuous corners, a hairline border.
    func dsCard(radius: CGFloat = DS.cardRadius, padding: CGFloat? = 16) -> some View {
        self
            .padding(.all, padding ?? 0)
            .background(DS.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: Theme.hairline))
    }
}

/// Selectable pill: raised with a strong border when selected, quiet otherwise. 44pt target.
struct DSPill: View {
    let title: String
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Theme.text : Theme.supporting)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(isSelected ? Theme.hover : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Theme.borderStrong : Theme.border,
                                                lineWidth: Theme.hairline))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// 48pt primary action: indigo fill, white semibold, optional leading symbol.
struct DSPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.subheadline.weight(.semibold)) }
                Text(title).font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous))
        }
        .buttonStyle(DSPressStyle())
    }
}

/// 48pt secondary action: raised surface, hairline, primary text.
struct DSSecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: Theme.hairline))
        }
        .buttonStyle(DSPressStyle())
    }
}

/// Press feedback shared by the design's buttons: a slight sink, critically damped.
struct DSPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 1.0), value: configuration.isPressed)
            // The click lands on press-down, with the visual squash — not on release.
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.press() }
            }
    }
}

/// `.plain` plus the press click and a faint dim: for rows, tiles and custom controls that
/// draw their own chrome. Use it wherever `.buttonStyle(.plain)` used to be.
struct HapticPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.linear(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.press() }
            }
    }
}

/// Press click for buttons that keep a system style (`.bordered`, toolbar items, menus can't
/// take a custom `ButtonStyle` without losing their look). A simultaneous tap gesture, so the
/// button's own action still fires; silent while the button is disabled.
private struct HapticTapModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded {
            if isEnabled { Haptics.press() }
        })
    }
}

extension View {
    func hapticTap() -> some View { modifier(HapticTapModifier()) }
}

/// A small rounded-square icon tile. With no `glyph`, the tile is `fill` at low opacity and the
/// symbol is `fill` itself (the Linear treatment); with a `glyph`, `fill` is used as given.
struct DSIconBadge: View {
    let systemImage: String
    var fill: Color
    var glyph: Color? = nil
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(glyph ?? fill)
            .frame(width: size, height: size)
            .background(glyph == nil ? fill.opacity(0.14) : fill,
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A status pill: a dot and a short label in a state colour ("Done", "To do", "Critical").
struct DSStatusPill: View {
    let text: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: Theme.hairline))
    }
}
