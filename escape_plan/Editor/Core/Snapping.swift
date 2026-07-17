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

struct SnapSettings: Equatable, Sendable {
    var gridEnabled: Bool
    /// Grid pitch in meters. 10cm is the playbook default.
    var gridSizeM: Double
    var axisEnabled: Bool
    /// How close a coordinate must be to an anchor's to lock onto it.
    var axisToleranceM: Double
    var wallSnapEnabled: Bool
    /// Capture radius for another room's vertices and walls.
    var wallSnapRadiusM: Double

    init(gridEnabled: Bool = true, gridSizeM: Double = 0.1,
                axisEnabled: Bool = true, axisToleranceM: Double = 0.05,
                wallSnapEnabled: Bool = true, wallSnapRadiusM: Double = 0.25) {
        self.gridEnabled = gridEnabled
        self.gridSizeM = gridSizeM
        self.axisEnabled = axisEnabled
        self.axisToleranceM = axisToleranceM
        self.wallSnapEnabled = wallSnapEnabled
        self.wallSnapRadiusM = wallSnapRadiusM
    }

    static let `default` = SnapSettings()
    /// Every snap off — raw coordinates through. Used by tests that assert exact geometry.
    static let disabled = SnapSettings(gridEnabled: false, axisEnabled: false,
                                              wallSnapEnabled: false)
}

/// What the snapper had to work with. Built by the store from the active floor, excluding the
/// geometry being dragged (you never snap to yourself).
struct SnapContext: Equatable, Sendable {
    /// Corners of other rooms on the active floor.
    var vertices: [Point]
    /// Walls of other rooms on the active floor, as endpoint pairs.
    var segments: [[Point]]
    /// Points whose x/y the dragged point should prefer to line up with — normally the dragged
    /// vertex's own two polygon neighbours, which is what keeps a wall axis-aligned.
    var axisAnchors: [Point]

    init(vertices: [Point] = [], segments: [[Point]] = [],
                axisAnchors: [Point] = []) {
        self.vertices = vertices
        self.segments = segments
        self.axisAnchors = axisAnchors
    }

    static let empty = SnapContext()
}

struct SnapResult: Equatable, Sendable {
    enum Kind: String, Sendable {
        case none, grid, axis, wall, vertex
    }

    var point: Point
    var kind: Kind

    init(_ point: Point, _ kind: Kind) {
        self.point = point
        self.kind = kind
    }
}

enum SnapEngine {

    static func snap(_ p: Point, context: SnapContext,
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
    static func snapTranslation(_ delta: Point, settings: SnapSettings) -> Point {
        guard settings.gridEnabled, settings.gridSizeM > Geometry.epsilon else { return delta }
        return Point(roundToGrid(delta.x, settings.gridSizeM),
                       roundToGrid(delta.y, settings.gridSizeM))
    }

    // MARK: - Helpers

    static func roundToGrid(_ value: Double, _ size: Double) -> Double {
        guard size > Geometry.epsilon else { return value }
        return (value / size).rounded() * size
    }

    static func nearestVertex(_ p: Point, _ candidates: [Point],
                              within radius: Double) -> Point? {
        var best: Point?
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

    static func nearestWallPoint(_ p: Point, _ segments: [[Point]],
                                 within radius: Double) -> Point? {
        var best: Point?
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
