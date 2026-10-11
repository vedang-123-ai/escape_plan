//  PlanProjection.swift
//  escape_plan — Export module
//
//  Metres → page points, for the printed 2D floor plan.
//
//  Pure CoreGraphics maths, no drawing: it exists as its own type so the scale bar, the
//  drawing code, and the tests all agree on one transform instead of three.
//
//  Frame: the schema's floor-local plan frame is (x, y) in metres. On paper we map
//  **x → page x (right), y → page y (up on the drawing, decreasing UIKit y)** with a single uniform scale.
//  UIKit's page origin is top-left, so mapping plan +y to decreasing page y ensures
//  that plan +y ("North") appears at the top of the printed page, matching the 3D
//  viewport where `DollhouseGeometry` maps plan +y to scene −z (top-down view looking down −z).
//
//  One projection is built for the WHOLE home (not per floor) so every page shares a scale
//  and floors line up sheet-to-sheet — which matters for a jagged stack where an upper floor
//  is offset from the ground floor.

import CoreGraphics
import Foundation

struct PlanProjection {
    /// Page points per metre.
    let scale: CGFloat
    /// Page point that plan-space (0, 0) maps to.
    let origin: CGPoint

    /// Fits `bounds` inside `rect`, centred, preserving aspect ratio.
    /// A degenerate/empty bounds still produces a usable (if arbitrary) transform rather than
    /// NaN — a blank plan area is recoverable, a NaN CGContext is not.
    init(bounds: DollhouseGeometry.PlanBounds, in rect: CGRect) {
        let width = max(bounds.width, 0.001)
        let depth = max(bounds.depth, 0.001)
        let fitted = min(rect.width / width, rect.height / depth)
        let scale = fitted.isFinite && fitted > 0 ? fitted : 1
        self.scale = scale

        let drawnWidth = CGFloat(width) * scale
        let drawnHeight = CGFloat(depth) * scale
        let left = rect.minX + (rect.width - drawnWidth) / 2
        let top = rect.minY + (rect.height - drawnHeight) / 2
        self.origin = CGPoint(x: left - CGFloat(bounds.isEmpty ? 0 : bounds.minX) * scale,
                              y: top + CGFloat(bounds.isEmpty ? 0 : bounds.maxY) * scale)
    }

    func point(_ p: Point) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(p.x) * scale,
                y: origin.y - CGFloat(p.y) * scale)
    }

    func point(x: Double, y: Double) -> CGPoint {
        point(Point(x: x, y: y))
    }

    /// A distance in metres, in page points.
    func length(_ metres: Double) -> CGFloat { CGFloat(metres) * scale }

    /// The longest "nice" bar length in metres that still fits `maxPoints` — 1, 2, 5, 10, 20…
    /// Returns nil when even 1 m would overflow, so the caller can omit the bar rather than
    /// print a scale bar that lies.
    func scaleBarMetres(fitting maxPoints: CGFloat) -> Double? {
        let candidates: [Double] = [20, 10, 5, 2, 1]
        for metres in candidates where length(metres) <= maxPoints {
            return metres
        }
        return nil
    }
}
