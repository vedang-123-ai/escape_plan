import SceneKit
import UIKit

/// "White Model" palette — the visual overhaul of Aug 2026 (`DOLLHOUSE-REDESIGN-SPEC.md` §3.3,
/// tuned values locked in `swift-implementation-notes.md`).
///
/// The governing idea: ONE white material family for every wall, door, window, stair, slab and
/// piece of furniture. Form is read through shading — a soft key light, ambient occlusion in
/// the corners, and a bright cut top on every sliced wall — the way a white ball against a
/// bright sky still reads as a sphere because its underside is dark. Nothing here is
/// hand-tinted per element; the tones differ only by a few points of luminance so the family
/// reads as one material under one light.
///
/// The ONLY color in the scene is the escape-route system and the exit markers. That is the
/// deliberate divergence (spec §3.2): this is a life-safety app, so the route must be the
/// hottest thing on screen and everything else must get out of its way. When routes are hidden
/// (editor mode) the scene is fully monochrome.
///
/// Replaces the previous warm "diorama" palette, whose per-room accents, clay exterior walls and
/// saturated door/window panels put 10+ hues in one view and left the routes competing for
/// attention with the furniture.
enum DollhousePalette {

    // MARK: - Environment

    /// Studio cyc — neutral-warm light gray, a touch darker than the model so the white object
    /// reads bright against it.
    static let background = UIColor(hex: 0xE9E8E6)
    /// Bottom of the background gradient.
    static let backgroundLower = UIColor(hex: 0xE0DEDB)
    /// The "table" the house sits on.
    static let basePlate = UIColor(hex: 0xDFDDD9)
    /// Soft radial shadow under the whole model. Used at `contactShadowAlpha` or below.
    static let contactShadow = UIColor(hex: 0xB9B5AF)
    /// Kept low on purpose: the key light's shadow map already draws the shaped shadow, and this
    /// is only the soft ambient darkening under the model. Any stronger and the radial falloff
    /// reads as a smudge on the plate wherever the house doesn't actually sit.
    static let contactShadowAlpha: CGFloat = 0.18

    // MARK: - The white family (every structural surface)

    static let wallWhite = UIColor(hex: 0xF7F6F3)
    /// Top face of a cut wall — the BRIGHTEST surface in the scene. This is the single most
    /// important perceptual flip versus the old palette, which rimmed wall tops in a dark cap:
    /// a white architectural model reads its cut edge as the brightest face, not the darkest,
    /// and that one change is most of what makes the dollhouse look sliced rather than unfinished.
    static let wallTopCut = UIColor(hex: 0xFFFFFF)
    /// Room slabs — 2–3% darker than the walls so the plan reads without any tinting.
    static let floorWhite = UIColor(hex: 0xF1EFEA)
    /// Extruded slab side faces.
    static let slabEdge = UIColor(hex: 0xE8E5DF)
    /// Same white as the walls on purpose — shared material identity is the whole point.
    static let furnitureWhite = UIColor(hex: 0xF7F6F3)
    static let stairWhite = UIColor(hex: 0xF4F2EE)
    /// Door leaves sit proud of the wall and catch light, so they run a hair brighter…
    static let doorLeafWhite = UIColor(hex: 0xFAF9F7)
    /// …and jambs/frames are recessed, so they run a hair darker.
    static let frameWhite = UIColor(hex: 0xEFEDE8)
    /// Window panes are near-invisible: read by their frame and a specular kick, never by a
    /// blue tint. Used at `glassTransparency`.
    static let glassWhite = UIColor.white
    static let glassTransparency: CGFloat = 0.08

    // MARK: - Ghost treatment for inactive floors (spec §4)

    /// Inactive floors swap to a single flat unlit white so each wall contributes exactly ONE
    /// translucent layer. Lighting variation on a 12%-alpha surface is just noise, and stacking
    /// lit translucent boxes is what produced the old renderer's gray murk.
    static let ghostWhite = UIColor(hex: 0xF7F6F3)
    /// Floors ABOVE the active one curtain the view down through the open top, so they thin out
    /// more than floors below.
    static let ghostOpacityAbove: CGFloat = 0.12
    static let ghostOpacityBelow: CGFloat = 0.18
    /// Ghost slabs render heavier than ghost walls — the slab silhouette is what communicates a
    /// jagged footprint (a small basement under a wide ground floor).
    static let ghostSlabBoost: CGFloat = 2.0
    static let ghostSlabOpacityCap: CGFloat = 0.55
    /// 1px outline on ghost slab edges so stacked footprints stay legible.
    static let ghostEdge = UIColor(hex: 0x6B6862)
    static let ghostEdgeAlpha: CGFloat = 0.25

    // MARK: - The only color in the scene

    /// Hot safety orange. The most saturated thing in any frame, by design.
    static let routePrimary = UIColor(hex: 0xFF5A1F)
    /// The backup route is the SAME hue, lighter and dashed. The old cool-blue secondary is
    /// retired: against a monochrome model, two hot hues read as two unrelated systems, whereas
    /// light-orange-dashed reads as "backup of the same plan".
    static let routeSecondary = UIColor(hex: 0xFF9E6E)
    static let exitGreen = UIColor(hex: 0x16A34A)
    static let warningBadge = UIColor(hex: 0xDC2626)
    /// `no_viable_route` is worse than `no_secondary_egress`; its badge darkens to match.
    static let warningBadgeSevere = UIColor(hex: 0x991B1B)

    // MARK: - Lighting

    /// Key light: warm, from the upper left (azimuth 315°, elevation 50°).
    static let keyLight = UIColor(hex: 0xFFF6EA)
    /// Fill: cool-neutral, opposite side, so shadowed faces stay luminous.
    static let fillLight = UIColor(hex: 0xF0F2F5)
    /// Shadows are warm gray — never neutral black.
    static let shadowInk = UIColor(hex: 0x4A453E)

    // MARK: - In-scene UI

    /// Room labels: a quiet warm gray, not black.
    static let labelInk = UIColor(hex: 0x6B6862)
    /// Selection outline / highlight ring — the app accent (deep safety green), which stays out
    /// of the route orange's way.
    static let selectionTint = UIColor(hex: 0x0E8A3E)
}

extension UIColor {
    /// `UIColor(hex: 0xF7F6F3)` — the palette is specified in sRGB hex, so it's written that way.
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1.0)
    }

    /// Mix toward `other` by `amount` (0 = self, 1 = other).
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}
