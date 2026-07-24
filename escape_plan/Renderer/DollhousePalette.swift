import SceneKit
import UIKit

/// Warm "architectural model" palette: cream paper backdrop, wood-toned slabs, calm room
/// accents. Kept in one place so the editor (S2.x) and the route overlay (S2.3) key off the
/// same colors instead of inventing a second palette.
///
/// S4.4 rework: the dollhouse used to read as CAD gray, and the route tubes — the whole point
/// of the app — were dimmed to invisibility behind stacked translucent walls. The palette now
/// distinguishes exterior from interior walls, warms every structural tone, and pushes the
/// route colors hot enough to read from across the room.
enum DollhousePalette {

    /// Dark stage, not a cream page (2026-07-24). The cream backdrop was chosen when the
    /// renderer was viewed on its own; inside the shipped app it butts against black chrome
    /// on all four sides and reads as a hole cut in the UI. Going dark makes the model a lit
    /// object on a stage — and, more usefully, gives the hot orange route the contrast it was
    /// designed for. Floor plates stay pale (below), so the house still glows.
    static let background = UIColor(red: 0.055, green: 0.055, blue: 0.067, alpha: 1.0)
    /// Slightly lifted stage tone used for the backdrop gradient's horizon.
    static let backgroundHorizon = UIColor(red: 0.129, green: 0.125, blue: 0.145, alpha: 1.0)
    /// Slab top: pale warm oak. Deliberately still light — the plates are the "paper" the
    /// plan is drawn on, and dark labels have to stay readable on them.
    static let slab = UIColor(red: 0.914, green: 0.875, blue: 0.812, alpha: 1.0)
    /// Interior partitions: light warm plaster.
    static let wall = UIColor(red: 0.851, green: 0.816, blue: 0.769, alpha: 1.0)
    /// Exterior shell: deeper clay tone, clearly the "outside" of the model.
    static let exteriorWall = UIColor(red: 0.639, green: 0.557, blue: 0.494, alpha: 1.0)
    static let stairs = UIColor(red: 0.706, green: 0.627, blue: 0.545, alpha: 1.0)
    static let label = UIColor(red: 0.216, green: 0.192, blue: 0.161, alpha: 1.0)

    /// Room labels ride a billboarded plate instead of floating as bare glyphs: a label that
    /// crosses a pale slab, a translucent wall and the dark stage in one orbit has no single
    /// text color that stays legible. The plate gives it a constant background to sit on.
    static let labelText = UIColor(red: 0.965, green: 0.957, blue: 0.937, alpha: 1.0)
    static let labelPlate = UIColor(red: 0.086, green: 0.082, blue: 0.098, alpha: 0.82)

    /// Vertical stage gradient for `scene.background.contents` — darker at the top so the
    /// eye settles on the model rather than the void above it.
    static func stageBackdrop(size: CGSize = CGSize(width: 8, height: 512)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [background.cgColor, backgroundHorizon.cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0.0, 1.0]
            ) else {
                background.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                return
            }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    /// Interior walls stay airy so the floor plan (and the routes on it) read from outside…
    static let wallOpacity: CGFloat = 0.18
    /// …while the exterior shell keeps enough body that the house reads as a solid object.
    static let exteriorWallOpacity: CGFloat = 0.34

    /// How far a room slab leans toward its accent (0 = pure slab). Was 0.28 effective —
    /// too washed out for the rooms to have identities.
    static let roomAccentStrength: CGFloat = 0.52

    static func accent(for type: RoomType) -> UIColor {
        switch type {
        case .bedroom: return UIColor(red: 0.475, green: 0.576, blue: 0.816, alpha: 1.0)
        case .living:  return UIColor(red: 0.522, green: 0.729, blue: 0.545, alpha: 1.0)
        case .kitchen: return UIColor(red: 0.918, green: 0.694, blue: 0.376, alpha: 1.0)
        case .hall:    return UIColor(red: 0.780, green: 0.729, blue: 0.643, alpha: 1.0)
        case .bath:    return UIColor(red: 0.494, green: 0.741, blue: 0.780, alpha: 1.0)
        case .garage:  return UIColor(red: 0.647, green: 0.588, blue: 0.671, alpha: 1.0)
        case .other:   return UIColor(red: 0.753, green: 0.722, blue: 0.671, alpha: 1.0)
        }
    }

    // S2.3 route overlay. Primary is the hottest color in the scene on purpose — the escape
    // path is the thing the eye must find first. Secondary is cool and dashed so the two
    // never read as interchangeable.
    /// Object prisms (v1.1): muted per-category tints so furniture reads as context, never
    /// competing with routes or warnings.
    static func object(category: ObjectCategory) -> UIColor {
        switch category {
        case .bed: return UIColor(red: 0.62, green: 0.70, blue: 0.82, alpha: 1.0)
        case .sofa: return UIColor(red: 0.64, green: 0.74, blue: 0.68, alpha: 1.0)
        case .table: return UIColor(red: 0.78, green: 0.72, blue: 0.62, alpha: 1.0)
        case .wardrobe: return UIColor(red: 0.72, green: 0.66, blue: 0.76, alpha: 1.0)
        case .appliance: return UIColor(red: 0.68, green: 0.72, blue: 0.76, alpha: 1.0)
        case .storage: return UIColor(red: 0.76, green: 0.70, blue: 0.66, alpha: 1.0)
        case .other: return UIColor(red: 0.72, green: 0.72, blue: 0.72, alpha: 1.0)
        }
    }

    static let routePrimary = UIColor(red: 1.0, green: 0.420, blue: 0.102, alpha: 1.0)
    static let routeSecondary = UIColor(red: 0.302, green: 0.537, blue: 0.870, alpha: 1.0)
    static let exitGlow = UIColor(red: 0.180, green: 0.820, blue: 0.443, alpha: 1.0)
    static let warningBadge = UIColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1.0)
    /// `no_viable_route` is worse than `no_secondary_egress`; its badge darkens to match.
    static let warningBadgeSevere = UIColor(red: 0.62, green: 0.15, blue: 0.13, alpha: 1.0)

    /// Exits read differently from interior openings on purpose — an exit is the thing the whole
    /// app is about, and a judge should be able to find them without a legend.
    static func opening(kind: OpeningKind, isExit: Bool) -> UIColor {
        switch (kind, isExit) {
        case (.door, true):   return UIColor(red: 0.129, green: 0.694, blue: 0.365, alpha: 1.0)
        case (.door, false):  return UIColor(red: 0.729, green: 0.478, blue: 0.286, alpha: 1.0)
        case (.window, true): return UIColor(red: 0.239, green: 0.718, blue: 0.831, alpha: 1.0)
        case (.window, false):return UIColor(red: 0.588, green: 0.749, blue: 0.827, alpha: 1.0)
        }
    }
}
