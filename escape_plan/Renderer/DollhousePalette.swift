import SceneKit
import UIKit

/// Soft neutral base with room-type accents. Kept in one place so the editor (S2.x) and the route
/// overlay (S2.3) can key off the same colors instead of inventing a second palette.
enum DollhousePalette {

    static let background = UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
    static let slab = UIColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1.0)
    static let wall = UIColor(red: 0.76, green: 0.78, blue: 0.82, alpha: 1.0)
    static let stairs = UIColor(red: 0.66, green: 0.68, blue: 0.73, alpha: 1.0)
    static let label = UIColor(red: 0.18, green: 0.20, blue: 0.24, alpha: 1.0)

    /// How much of the wall you can see through. Low enough to read the room layout from outside,
    /// high enough that walls still read as surfaces rather than haze.
    static let wallOpacity: CGFloat = 0.28

    static func accent(for type: RoomType) -> UIColor {
        switch type {
        case .bedroom: return UIColor(red: 0.42, green: 0.55, blue: 0.82, alpha: 1.0)
        case .living:  return UIColor(red: 0.40, green: 0.69, blue: 0.60, alpha: 1.0)
        case .kitchen: return UIColor(red: 0.88, green: 0.66, blue: 0.35, alpha: 1.0)
        case .hall:    return UIColor(red: 0.62, green: 0.63, blue: 0.68, alpha: 1.0)
        case .bath:    return UIColor(red: 0.45, green: 0.72, blue: 0.80, alpha: 1.0)
        case .garage:  return UIColor(red: 0.58, green: 0.53, blue: 0.62, alpha: 1.0)
        case .other:   return UIColor(red: 0.70, green: 0.70, blue: 0.72, alpha: 1.0)
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

    static let routePrimary = UIColor(red: 0.95, green: 0.45, blue: 0.15, alpha: 1.0)
    static let routeSecondary = UIColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1.0)
    static let exitGlow = UIColor(red: 0.20, green: 0.85, blue: 0.45, alpha: 1.0)
    static let warningBadge = UIColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1.0)
    /// `no_viable_route` is worse than `no_secondary_egress`; its badge darkens to match.
    static let warningBadgeSevere = UIColor(red: 0.62, green: 0.15, blue: 0.13, alpha: 1.0)

    /// Exits read differently from interior openings on purpose — an exit is the thing the whole
    /// app is about, and a judge should be able to find them without a legend.
    static func opening(kind: OpeningKind, isExit: Bool) -> UIColor {
        switch (kind, isExit) {
        case (.door, true):   return UIColor(red: 0.16, green: 0.68, blue: 0.38, alpha: 1.0)
        case (.door, false):  return UIColor(red: 0.85, green: 0.52, blue: 0.25, alpha: 1.0)
        case (.window, true): return UIColor(red: 0.28, green: 0.72, blue: 0.85, alpha: 1.0)
        case (.window, false):return UIColor(red: 0.55, green: 0.75, blue: 0.85, alpha: 1.0)
        }
    }
}
