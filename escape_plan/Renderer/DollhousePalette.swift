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

    /// Studio cyc. Since the Linear revamp (2026-09-25) the app is dark only, so the white model
    /// floats on a near-black stage matching `Theme.canvas`: the bright object against a dark
    /// ground is the strongest figure/ground split available, and the routes on its white floors
    /// keep every luminance contract `RouteEncodingTests` holds.
    static let background = UIColor(hex: 0x0E0F11)
    /// Bottom of the background gradient.
    static let backgroundLower = UIColor(hex: 0x08090A)
    /// The light the ambient fill is tinted from. It used to be derived from `background`; a
    /// dark stage must not darken the model, so it is its own (the pre-revamp cyc) value.
    static let ambientTint = UIColor(hex: 0xE9E8E6)
    /// The "table" the house sits on: one step up from the stage, so the model has a ground.
    static let basePlate = UIColor(hex: 0x1A1B1E)
    /// Soft radial shadow under the whole model. Used at `contactShadowAlpha` or below.
    static let contactShadow = UIColor(hex: 0x000000)
    /// Kept low on purpose: the key light's shadow map already draws the shaped shadow, and this
    /// is only the soft ambient darkening under the model. Any stronger and the radial falloff
    /// reads as a smudge on the plate wherever the house doesn't actually sit.
    static let contactShadowAlpha: CGFloat = 0.35

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

    // COOL HUES ARE RESERVED FOR ROUTES. WARM HUES ARE RESERVED FOR HAZARD.
    //
    // Until the fire-origin hazard visualization landed, the route was the only color in the
    // frame and its hue could be chosen purely for attention — hence the old safety orange.
    // A second colored system changes the problem: orange route + red hazard is precisely the
    // pair a deuteranope cannot separate, and "route" versus "the thing that will kill you"
    // is the single distinction this app cannot afford to blur.
    //
    // So the two systems are split across the color wheel's safest axis. Blue-vs-orange is the
    // one pairing that survives deuteranopia, protanopia AND tritanopia, because it separates
    // on the blue-yellow channel rather than the red-green one. Routes took the cool side
    // (they are the calm instruction), hazard took the warm side (it is the alarm).
    //
    // Hue is still only the first layer. `RouteOverlay` also encodes primary-versus-secondary
    // as solid-versus-dashed geometry and numbers the stops, so the whole system survives with
    // color removed entirely — which is also what makes the printable black-and-white plan
    // legible. The luminance separations below are asserted with real numbers in
    // `RouteEncodingTests`; don't retune a value here without rerunning that suite.

    /// Deep cobalt — the primary escape route. Relative luminance 0.0682, which is 8.22:1
    /// against `wallWhite`: the strongest ink in the scene, so the route still dominates a
    /// white model without borrowing the alarm color.
    static let routePrimary = UIColor(hex: 0x123FB0)
    /// The backup route: the SAME cool hue, deliberately lighter (relative luminance 0.2132 —
    /// a 2.23:1 step above the primary, 53 of 255 gray levels apart when printed) and drawn as
    /// real dashed geometry. Same hue family means "backup of the same plan"; the luminance
    /// step plus the dashes mean it still reads as the backup in grayscale.
    static let routeSecondary = UIColor(hex: 0x4180D4)

    /// Exit pads and chevrons. **Darkened from #16A34A in the accessibility pass**, and the
    /// reason is a measurement rather than a preference:
    ///
    ///   #16A34A sits at relative luminance 0.2686 and `hazardCore` at 0.3246 — a gap of
    ///   **0.056**, i.e. a **1.18:1** contrast ratio between them. Green-versus-orange is
    ///   exactly the pair deuteranopia collapses, and with the luminance channel carrying
    ///   almost nothing there was no second cue left. The moment the fire simulation runs,
    ///   both are on screen at once: the thing that saves you and the thing that kills you,
    ///   rendered as the same colour.
    ///
    ///   #0F8140 sits at 0.1617 — a **0.163** gap from `hazardCore` (2.9× wider) at
    ///   **1.77:1**, while keeping a **0.094** gap from `routePrimary` (0.0682), which clears
    ///   the palette's own 0.08 luminance-gap floor. It measures 4.59:1 against `wallWhite`
    ///   (up from 3.05:1), so the pad also reads better on the white model than it did.
    ///
    /// Hue is still not allowed to be the only cue: `ExitMarkerFixture` draws the pad with a
    /// white rim and a white outward-pointing chevron knocked into it (4.96:1 *inside* the
    /// marker), so an exit is identifiable with colour removed entirely. `A11yHouseSceneTests`
    /// holds both the numbers and the presence of the non-colour cue.
    static let exitGreen = UIColor(hex: 0x0F8140)

    // MARK: - Reserved warm family: hazard (owned by the fire-origin lane, not by RouteOverlay)

    /// Fire-origin fill — the identity color of the hazard system, and the third member of the
    /// luminance contract with `routePrimary` / `routeSecondary` (0.3246; the three sit at
    /// gray 74 / 127 / 154 when printed). Anything that must read as "hazard" at a glance
    /// uses this.
    static let hazardCore = UIColor(hex: 0xF97316)
    /// Deep ember, for the hazard's own outline/ink. Deliberately EXCLUDED from the three-way
    /// luminance contract: at 0.1123 it sits 0.044 from `routePrimary`, so it is only ever
    /// legible as the edge of a `hazardCore` mass it is touching. Never use it as a standalone
    /// line — a lone dark-red line and a lone dark-blue line are one protanopia away from
    /// identical.
    static let hazardEdge = UIColor(hex: 0xB91C1C)
    /// Light warm wash for smoke/falloff gradients, used at low alpha. Not an ink.
    static let hazardHalo = UIColor(hex: 0xFDBA74)
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
    /// Selection outline / highlight ring — the app accent (indigo, since the 2026-09-25 revamp).
    /// It only ever appears as an outline on a selected object in the editor, where no route is
    /// drawn, so its closeness to the route blues never puts the two on screen together.
    static let selectionTint = UIColor(hex: 0x5E6AD2)
    /// The walking person in drills and playback: the pre-revamp safety green, kept because an
    /// indigo figure walking a cobalt route would blur into it.
    static let personTint = UIColor(hex: 0x0E8A3E)
}

extension UIColor {
    /// `UIColor(hex: 0xF7F6F3)` — the palette is specified in sRGB hex, so it's written that way.
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1.0)
    }

    /// WCAG 2.2 relative luminance (the sRGB channels linearized, then weighted 0.2126 /
    /// 0.7152 / 0.0722). This is the number that decides whether two colors are still
    /// different once color itself is gone — a grayscale print, a monochrome accessibility
    /// filter, or a dichromat looking at two hues that collapse onto each other.
    var relativeLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio, 1.0 (identical) … 21.0 (black on white).
    func contrastRatio(to other: UIColor) -> CGFloat {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// What a black-and-white printer makes of this color: the neutral gray with the same
    /// relative luminance, as an 8-bit channel value. Two route colors that land on the same
    /// gray level are the same line on paper, whatever their hues were.
    var printedGrayLevel: Int {
        let l = relativeLuminance
        let c = l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055
        return Int((c * 255).rounded())
    }

    /// The color as it survives desaturation — same luminance, no hue. Handy for previewing
    /// the printable plan without a printer.
    var luminanceGray: UIColor {
        let c = CGFloat(printedGrayLevel) / 255
        return UIColor(red: c, green: c, blue: c, alpha: 1)
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
