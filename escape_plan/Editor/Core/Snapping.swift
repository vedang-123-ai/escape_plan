//  Snapping.swift — pure snapping logic for editor drags.
//
//  Snapping is what makes hand-authoring a home in under 5 minutes possible: users don't align
//  rooms, the snapper does. Kept pure and separately testable so "why did it jump there?" is
//  always answerable without a device.
//
//  Priority order (first match wins, strongest constraint first):
//    1. vertex snap   — land exactly on another room's corner
//    2. wall snap     — land on another room's wall (this is how rooms "connect" cleanly)
//    3. axis snap     — align to an anchor's x or y (keeps walls straight)
//    4. grid snap     — fall back to the 10cm grid
//  Axis snap composes with grid: an axis-locked coordinate is preserved, the free one is
//  gridded, so aligning to a neighbour never fights the grid.

import Foundation

public struct SnapSettings: Equatable, Sendable {
    public var gridEnabled: Bool
    /// Grid pitch in meters. 10cm is the playbook default.
    public var gridSizeM: Double
    public var axisEnabled: Bool
    /// How close a coordinate must be to an anchor's to lock onto it.
    public var axisToleranceM: Double
    public var wallSnapEnabled: Bool
    /// Capture radius for another room's vertices and walls.
    public var wallSnapRadiusM: Double

    public init(gridEnabled: Bool = true, gridSizeM: Double = 0.1,
                axisEnabled: Bool = true, axisToleranceM: Double = 0.05,
                wallSnapEnabled: Bool = true, wallSnapRadiusM: Double = 0.25) {
        self.gridEnabled = gridEnabled
        self.gridSizeM = gridSizeM
        self.axisEnabled = axisEnabled
        self.axisToleranceM = axisToleranceM
        self.wallSnapEnabled = wallSnapEnabled
        self.wallSnapRadiusM = wallSnapRadiusM
    }

    public static let `default` = SnapSettings()
    /// Every snap off — raw coordinates through. Used by tests that assert exact geometry.
    public static let disabled = SnapSettings(gridEnabled: false, axisEnabled: false,
                                              wallSnapEnabled: false)
}

/// What the snapper had to work with. Built by the store from the active floor, excluding the
/// geometry being dragged (you never snap to yourself).
public struct SnapContext: Equatable, Sendable {
    /// Corners of other rooms on the active floor.
    public var vertices: [Point2D]
    /// Walls of other rooms on the active floor, as endpoint pairs.
    public var segments: [[Point2D]]
    /// Points whose x/y the dragged point should prefer to line up with — normally the dragged
    /// vertex's own two polygon neighbours, which is what keeps a wall axis-aligned.
    public var axisAnchors: [Point2D]

    public init(vertices: [Point2D] = [], segments: [[Point2D]] = [],
                axisAnchors: [Point2D] = []) {
        self.vertices = vertices
        self.segments = segments
        self.axisAnchors = axisAnchors
    }

    public static let empty = SnapContext()
}

public struct SnapResult: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case none, grid, axis, wall, vertex
    }

    public var point: Point2D
    public var kind: Kind

    public init(_ point: Point2D, _ kind: Kind) {
        self.point = point
        self.kind = kind
    }
}

public enum SnapEngine {

    public static func snap(_ p: Point2D, context: SnapContext,
                            settings: SnapSettings) -> SnapResult {
        if settings.wallSnapEnabled {
            if let v = nearestVertex(p, context.vertices, within: settings.wallSnapRadiusM) {
                return SnapResult(v, .vertex)
            }
            if let w = nearestWallPoint(p, context.segments, within: settings.wallSnapRadiusM) {
                return SnapResult(w, .wall)
            }
        }

        var point = p
        var lockedX = false
        var lockedY = false

        if settings.axisEnabled {
            if let ax = nearestCoordinate(p.x, context.axisAnchors.map(\.x),
                                          within: settings.axisToleranceM) {
                point.x = ax
                lockedX = true
            }
            if let ay = nearestCoordinate(p.y, context.axisAnchors.map(\.y),
                                          within: settings.axisToleranceM) {
                point.y = ay
                lockedY = true
            }
        }

        if settings.gridEnabled && settings.gridSizeM > Geometry.epsilon {
            // An axis lock outranks the grid on the locked coordinate only.
            if !lockedX { point.x = roundToGrid(point.x, settings.gridSizeM) }
            if !lockedY { point.y = roundToGrid(point.y, settings.gridSizeM) }
            if !lockedX && !lockedY { return SnapResult(point, .grid) }
        }

        if lockedX || lockedY { return SnapResult(point, .axis) }
        return SnapResult(point, settings.gridEnabled ? .grid : .none)
    }

    /// Snapping a translation (dragging a wall or a whole room): snap the *delta* so the shape
    /// keeps its exact proportions instead of each vertex drifting to its own grid cell.
    public static func snapTranslation(_ delta: Point2D, settings: SnapSettings) -> Point2D {
        guard settings.gridEnabled, settings.gridSizeM > Geometry.epsilon else { return delta }
        return Point2D(roundToGrid(delta.x, settings.gridSizeM),
                       roundToGrid(delta.y, settings.gridSizeM))
    }

    // MARK: - Helpers

    public static func roundToGrid(_ value: Double, _ size: Double) -> Double {
        guard size > Geometry.epsilon else { return value }
        return (value / size).rounded() * size
    }

    static func nearestVertex(_ p: Point2D, _ candidates: [Point2D],
                              within radius: Double) -> Point2D? {
        var best: Point2D?
        var bestD = radius
        for c in candidates {
            let d = Geometry.distance(p, c)
            if d <= bestD {
                bestD = d
                best = c
            }
        }
        return best
    }

    static func nearestWallPoint(_ p: Point2D, _ segments: [[Point2D]],
                                 within radius: Double) -> Point2D? {
        var best: Point2D?
        var bestD = radius
        for seg in segments where seg.count == 2 {
            let hit = Geometry.closestPointOnSegment(p, seg[0], seg[1]).point
            let d = Geometry.distance(p, hit)
            if d <= bestD {
                bestD = d
                best = hit
            }
        }
        return best
    }

    static func nearestCoordinate(_ value: Double, _ candidates: [Double],
                                  within tolerance: Double) -> Double? {
        var best: Double?
        var bestD = tolerance
        for c in candidates {
            let d = abs(value - c)
            if d <= bestD {
                bestD = d
                best = c
            }
        }
        return best
    }
}
