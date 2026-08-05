//  PlanInk.swift
//  escape_plan — Export module
//
//  The greyscale encoding table for the printed escape plan.
//
//  HARD CONSTRAINT: this artifact ends up taped to a refrigerator, printed on somebody's
//  black-and-white laser printer, and read in a hurry. So NOTHING here may be distinguished
//  by hue. Every distinction is carried by a channel that survives desaturation:
//
//    * stroke weight   — primary route is heavy, backup is light
//    * dash pattern    — primary is solid, backup is dashed
//    * glyph shape     — a door is an arc, a window is a double line, an exit is a triangle
//    * ink darkness    — every ink is ≤ 0.5 grey, i.e. genuinely dark on white paper
//
//  Colours are declared as a single grey component on purpose: there is no colour to lose,
//  so a greyscale printer prints exactly what the screen preview showed. `PlanInkTests`
//  asserts these invariants and rasterises real strokes through `PlanInk.stroke` into a
//  DeviceGray bitmap to prove primary and secondary stay tellable apart.

import CoreGraphics
import Foundation

/// One pen: how dark, how heavy, and whether it is broken.
struct InkStyle: Equatable {
    /// 0 = black, 1 = white. Kept ≤ 0.5 for anything that must read as ink.
    var gray: CGFloat
    var lineWidth: CGFloat
    /// Empty = solid.
    var dash: [CGFloat]

    var isSolid: Bool { dash.isEmpty }

    init(gray: CGFloat, lineWidth: CGFloat, dash: [CGFloat] = []) {
        self.gray = gray
        self.lineWidth = lineWidth
        self.dash = dash
    }

    func apply(to ctx: CGContext) {
        ctx.setStrokeColor(gray: gray, alpha: 1)
        ctx.setLineWidth(lineWidth)
        if dash.isEmpty {
            ctx.setLineDash(phase: 0, lengths: [])
        } else {
            ctx.setLineDash(phase: 0, lengths: dash)
        }
    }
}

enum PlanInk {

    // MARK: - Routes

    /// The route you take. Solid and heavy — the single most important mark on the page.
    static let primaryRoute = InkStyle(gray: 0.0, lineWidth: 3.4)
    /// The way out when the primary is blocked. Dashed and lighter, never a different hue.
    static let secondaryRoute = InkStyle(gray: 0.30, lineWidth: 2.0, dash: [7, 5])

    static func route(_ kind: RouteKind) -> InkStyle {
        kind == .primary ? primaryRoute : secondaryRoute
    }

    // MARK: - Structure

    static let exteriorWall = InkStyle(gray: 0.0, lineWidth: 3.0)
    static let interiorWall = InkStyle(gray: 0.12, lineWidth: 1.4)
    static let doorGlyph = InkStyle(gray: 0.20, lineWidth: 1.0)
    static let windowGlyph = InkStyle(gray: 0.20, lineWidth: 1.2)
    static let stairTread = InkStyle(gray: 0.35, lineWidth: 0.8)
    static let stairOutline = InkStyle(gray: 0.25, lineWidth: 1.0)
    static let objectOutline = InkStyle(gray: 0.50, lineWidth: 0.8, dash: [2.5, 2.5])
    static let marker = InkStyle(gray: 0.0, lineWidth: 1.2)
    static let hairline = InkStyle(gray: 0.45, lineWidth: 0.6)
    static let boxRule = InkStyle(gray: 0.0, lineWidth: 1.2)

    /// Room floor fill. Light enough that black route ink and room labels stay high-contrast
    /// on top of it even after a photocopier flattens everything.
    static let roomFillGray: CGFloat = 0.92
    static let markerFillGray: CGFloat = 1.0

    /// Every ink that has to survive a black-and-white printer. `PlanInkTests` walks this.
    static let allInks: [(name: String, style: InkStyle)] = [
        ("primary route", primaryRoute),
        ("secondary route", secondaryRoute),
        ("exterior wall", exteriorWall),
        ("interior wall", interiorWall),
        ("door glyph", doorGlyph),
        ("window glyph", windowGlyph),
        ("stair tread", stairTread),
        ("stair outline", stairOutline),
        ("object outline", objectOutline),
        ("marker", marker),
        ("box rule", boxRule),
    ]

    // MARK: - Stroking

    /// Strokes a polyline in `style`. THE path every line on the plan goes through, so a test
    /// that rasterises this is testing what actually prints.
    static func stroke(_ points: [CGPoint], style: InkStyle, in ctx: CGContext) {
        guard points.count >= 2 else { return }
        ctx.saveGState()
        style.apply(to: ctx)
        ctx.setLineCap(style.isSolid ? .round : .butt)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: points[0])
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
