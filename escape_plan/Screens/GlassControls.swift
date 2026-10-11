//  GlassControls.swift
//  escape_plan
//
//  The floating-control vocabulary for surfaces that sit ON the 3D model (UI craft pass,
//  Jul 2026). One availability fork lives here — Liquid Glass on iOS 26+, the classic blur
//  material below it — so every floating control reads the same on both OS versions and no
//  screen has to repeat the `#available` dance.
//
//  Why glass and not an opaque bar: the dollhouse is the content. Controls that sit over it
//  have to stay legible while letting the model show through, and they must not read as a
//  second opaque surface competing with the dock.

import SwiftUI

extension View {

    /// Capsule background for a floating control. `isSelected` tints it with the accent and
    /// adds an active stroke so the active floor does not rely on colour alone (SC 1.4.1).
    @ViewBuilder
    func glassPill(isSelected: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                isSelected ? .regular.tint(Color.accentColor.opacity(0.55)).interactive()
                           : .regular.interactive(),
                in: .capsule)
                .overlay(
                    isSelected
                        ? Capsule().strokeBorder(Theme.accentText, lineWidth: 1.5)
                        : nil
                )
        } else {
            self
                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.30))
                                       : AnyShapeStyle(.regularMaterial),
                            in: Capsule())
                // Bright top edge: light catching the material's rim, or prominent stroke when selected.
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Theme.accentText : .white.opacity(0.22),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
                )
        }
    }

    /// Rounded-rect variant for wider floating strips (the immersive explode slider).
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 22) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
        }
    }

    /// Groups adjacent glass elements so iOS 26 can blend them as one material instead of
    /// stacking separate panes. No-op below 26, where each pill is its own blur.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 8) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

/// Floating chip button: press feedback is instant and critically damped (no overshoot on a
/// control that carries no momentum). Used for the floor picker and the icon actions that
/// sit over the dollhouse.
struct GlassChipButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    /// Icon-only chips get equal padding so they come out circular rather than lozenge.
    var isCompact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            // Selected chips used the raw accent as TEXT (4.45:1 on white). `accentText` is
            // the same hue tuned to clear 4.5:1 in both appearances.
            .foregroundStyle(isSelected ? Theme.accentText : Color.primary)
            .padding(.horizontal, isCompact ? 11 : 15)
            .padding(.vertical, 9)
            .glassPill(isSelected: isSelected)
            // Reduce Motion: the press still registers — it just changes opacity in place
            // instead of scaling, so nothing moves under the finger.
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? .linear(duration: 0.08)
                                    : .spring(response: 0.3, dampingFraction: 1.0),
                       value: configuration.isPressed)
            // Same click as every other button in the app, on press-down.
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.press() }
            }
            // SC 2.5.8 & Apple HIG: Enlarge hit target to at least 44×44 pt with contentShape(Rectangle())
            // while preserving the visual chip size and shape.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            // Non-colour cue is the active stroke in glassPill; VoiceOver gets the .isSelected
            // trait, which it already speaks as "Selected" (a value too would say it twice).
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
