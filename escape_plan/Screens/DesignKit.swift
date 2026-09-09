//  DesignKit.swift
//  escape_plan
//
//  The Claude Design vocabulary ("Escape Plan.dc.html", 2026-09-07) as SwiftUI. Every screen
//  restyled from that design draws its surfaces, pills and buttons from here so the look stays
//  one system rather than five slightly different card styles.
//
//  Colours are appearance pairs: the design is light-only, so the dark half of each pair is a
//  sensible mapping onto iOS system darks rather than a designed value. Semantic colours
//  (accent, warning, caution, route/exit/hazard inks) stay in `Theme` — this file is chrome.

import SwiftUI

enum DS {

    // MARK: Page & text

    /// The design's page fill: a barely-there cool gradient, not flat systemGroupedBackground.
    static let pageTop = AppearancePair(light: 0xF5F7FC, dark: 0x000000).color
    static let pageBottom = AppearancePair(light: 0xEDF1F7, dark: 0x0B0B0D).color
    static var pageGradient: LinearGradient {
        LinearGradient(colors: [pageTop, pageBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Headline/label ink. Cooler and deeper than `.primary` on the design.
    static let ink = AppearancePair(light: 0x1B2340, dark: 0xF2F2F7).color
    /// Paragraph ink inside cards.
    static let bodyInk = AppearancePair(light: 0x3D4666, dark: 0xC7CBD6).color
    /// Supporting text on the design (cooler than `Theme.supporting`; 4.9:1 on white).
    static let supporting = AppearancePair(light: 0x6B7086, dark: 0xAEAEB2).color

    /// Card surface.
    static let card = AppearancePair(light: 0xFFFFFF, dark: 0x1C1C1E).color
    /// Inset fill inside a card (secondary buttons, tracks).
    static let inset = AppearancePair(light: 0xF2F2F7, dark: 0x2C2C2E).color
    /// Progress track.
    static let track = AppearancePair(light: 0xEEF1F6, dark: 0x2C2C2E).color

    /// Tinted badge fills the design uses behind icons.
    static let criticalFill = AppearancePair(light: 0xFBE5E5, dark: 0x3A1A1A).color
    static let cautionFill = AppearancePair(light: 0xFBEBD9, dark: 0x3A2A14).color
    static let accentFill = AppearancePair(light: 0xE6F4EA, dark: 0x13301E).color

    // MARK: Geometry

    static let cardRadius: CGFloat = 16
    static let cardRadiusLarge: CGFloat = 22
    static let modelRadius: CGFloat = 26
    static let buttonRadius: CGFloat = 14
    static let pagePadding: CGFloat = 20

    /// `0 6px 18px rgba(27,35,64,.07)` on the design.
    static let shadowColor = Color(red: 27/255, green: 35/255, blue: 64/255).opacity(0.07)
}

extension View {
    /// The design's page background. Ignores safe areas so the gradient runs edge to edge.
    func dsPage() -> some View {
        self.background(DS.pageGradient.ignoresSafeArea())
    }

    /// The one card treatment: surface, continuous corners, soft cool shadow.
    func dsCard(radius: CGFloat = DS.cardRadius, padding: CGFloat? = 16) -> some View {
        self
            .padding(.all, padding ?? 0)
            .background(DS.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: DS.shadowColor, radius: 9, y: 6)
    }
}

/// Selectable pill: accent fill when selected, white with ink text otherwise. 40pt tall.
struct DSPill: View {
    let title: String
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : DS.bodyInk)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isSelected ? Theme.accent : DS.card, in: Capsule())
                .shadow(color: isSelected ? .clear : DS.shadowColor, radius: 9, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// 56pt primary action: accent fill, white semibold, optional leading symbol.
struct DSPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.body.weight(.semibold)) }
                Text(title).font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous))
            .shadow(color: Color(red: 27/255, green: 35/255, blue: 64/255).opacity(0.10), radius: 8, y: 6)
        }
        .buttonStyle(DSPressStyle())
    }
}

/// 56pt secondary action: card surface, accent-text label.
struct DSSecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.buttonRadius, style: .continuous))
                .shadow(color: DS.shadowColor, radius: 9, y: 6)
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

/// Coloured circle with a white or tinted SF Symbol — the design's tile and card icons.
struct DSIconBadge: View {
    let systemImage: String
    var fill: Color
    var glyph: Color = .white
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }
}
