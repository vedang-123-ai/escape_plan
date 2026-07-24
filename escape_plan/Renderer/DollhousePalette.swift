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

    /// Warm paper backdrop — reads as a diorama table, not a void.
    static let background = UIColor(red: 0.957, green: 0.937, blue: 0.902, alpha: 1.0)
    /// Slab top: pale warm oak.
    static let slab = UIColor(red: 0.914, green: 0.875, blue: 0.812, alpha: 1.0)
    /// Interior partitions: light warm plaster.
    static let wall = UIColor(red: 0.851, green: 0.816, blue: 0.769, alpha: 1.0)
    /// Exterior shell: deeper clay tone, clearly the "outside" of the model.
    static let exteriorWall = UIColor(red: 0.639, green: 0.557, blue: 0.494, alpha: 1.0)
    static let stairs = UIColor(red: 0.706, green: 0.627, blue: 0.545, alpha: 1.0)
    static let label = UIColor(red: 0.216, green: 0.192, blue: 0.161, alpha: 1.0)

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
