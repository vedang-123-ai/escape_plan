//  FloorPlanDrawing.swift
//  escape_plan — Export module
//
//  Draws one floor as a top-down 2D plan with Core Graphics, straight from the schema
//  polygons.
//
//  WHY NOT A SCREENSHOT OF THE 3D SCENE: a SceneKit snapshot is a raster of a perspective
//  view with translucency, soft shading and a hot orange route — everything that survives
//  worst on a black-and-white laser printer. Redrawing the plan from the model gives vector
//  output at any print resolution, a deterministic result a test can assert on (no GPU, no
//  frame timing, no device-dependent rasteriser), and full control of the greyscale
//  encoding in `PlanInk`.
//
//  Geometry conventions are borrowed from `DollhouseGeometry` rather than re-derived: the
//  same wall dedup + cutout maths, the same parametric opening placement, the same centroid.
//  If the renderer's idea of where a door sits changes, this drawing changes with it.

import CoreGraphics
import Foundation
import UIKit

enum FloorPlanDrawing {

    /// Everything one floor page needs to draw its plan.
    struct Input {
        var home: HomeModel
        var floor: Floor
        /// Engine-computed routes, or nil when none are available offline. Nil draws the
        /// geometry and nothing else — a route is never inferred here.
        var plan: RoutePlan?
        /// Draw furniture footprints (helps people recognise the room; pure decoration).
        var includeObjects: Bool = true
    }

    /// Draws the floor into `rect`, returning the projection used (so the caller can print a
    /// scale bar that matches).
    @discardableResult
    static func draw(_ input: Input, in rect: CGRect, context ctx: CGContext) -> PlanProjection {
        // Inset so exit triangles and route markers on the outer wall stay inside the frame.
        let projection = PlanProjection(bounds: DollhouseGeometry.bounds(of: input.home),
                                        in: rect.insetBy(dx: 22, dy: 22))

        ctx.saveGState()
        ctx.addRect(rect)
        ctx.clip()

        drawRooms(input.floor, projection: projection, context: ctx)
        if input.includeObjects {
            drawObjects(input.floor, projection: projection, context: ctx)
        }
        drawStairs(input, projection: projection, context: ctx)
        drawWalls(input.floor, projection: projection, context: ctx)
        drawOpenings(input.floor, projection: projection, context: ctx)
        if let plan = input.plan {
            drawRoutes(plan, floorID: input.floor.id, projection: projection, context: ctx)
        }
        // Labels go on last, over a white pad: a room name struck through by a route line is
        // the one thing on this drawing nobody can recover from, and a 2 mm break in a line
        // costs nothing.
        drawRoomLabels(input.floor, projection: projection, context: ctx)

        ctx.restoreGState()
        return projection
    }

    // MARK: - Rooms

    private static func drawRooms(_ floor: Floor, projection: PlanProjection, context ctx: CGContext) {
        for room in floor.rooms {
            guard room.polygon.count >= 3 else { continue }
            let path = CGMutablePath()
            path.addLines(between: room.polygon.map(projection.point))
            path.closeSubpath()
            ctx.saveGState()
            ctx.setFillColor(gray: PlanInk.roomFillGray, alpha: 1)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    private static func drawRoomLabels(_ floor: Floor, projection: PlanProjection, context ctx: CGContext) {
        for room in floor.rooms where room.polygon.count >= 3 {
            let centre = projection.point(DollhouseGeometry.centroid(room.polygon))
            PDFText.draw(room.name.uppercased(),
                         centredAt: centre,
                         font: .systemFont(ofSize: 7.5, weight: .semibold),
                         gray: 0.1,
                         background: 1,
                         context: ctx)
        }
    }

    // MARK: - Walls

    /// Walls come from `DollhouseGeometry.walls(for:)`, so shared partitions are deduped and
    /// every opening is already a hole in its host wall. The hole is drawn as a real gap —
    /// which is what makes the door and window glyphs sit in a break in the line, exactly as
    /// on an architectural plan.
    private static func drawWalls(_ floor: Floor, projection: PlanProjection, context ctx: CGContext) {
        for spec in DollhouseGeometry.walls(for: floor) {
            let style = spec.isExterior ? PlanInk.exteriorWall : PlanInk.interiorWall
            for (t0, t1) in solidSpans(of: spec) {
                let a = lerp(spec.a, spec.b, t0 / spec.length)
                let b = lerp(spec.a, spec.b, t1 / spec.length)
                PlanInk.stroke([projection.point(a), projection.point(b)], style: style, in: ctx)
            }
        }
    }

    /// The stretches of wall that are actually wall, i.e. the complement of its cutouts.
    static func solidSpans(of spec: DollhouseGeometry.WallSpec) -> [(Double, Double)] {
        let holes = spec.cutouts
            .map { (max(0, $0.centerAlong - $0.width / 2), min(spec.length, $0.centerAlong + $0.width / 2)) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }

        var spans: [(Double, Double)] = []
        var cursor = 0.0
        for hole in holes {
            if hole.0 > cursor { spans.append((cursor, hole.0)) }
            cursor = max(cursor, hole.1)
        }
        if cursor < spec.length { spans.append((cursor, spec.length)) }
        return spans.filter { $0.1 - $0.0 > 1e-6 }
    }

    // MARK: - Openings

    /// Where an opening sits on the page, with the wall's direction and the direction that
    /// points into its host room.
    struct OpeningFrame {
        var centre: CGPoint
        /// Unit vector along the wall.
        var along: CGPoint
        /// Unit normal pointing into the host room.
        var inward: CGPoint
        /// Half the opening's clear width, in page points.
        var halfWidth: CGFloat
    }

    static func frame(for opening: Opening,
                      on floor: Floor,
                      projection: PlanProjection) -> OpeningFrame? {
        guard let placement = DollhouseGeometry.placement(for: opening, on: floor),
              let room = floor.rooms.first(where: { $0.id == opening.wall_segment.room_id }),
              let edge = DollhouseGeometry.edge(room.polygon, opening.wall_segment.edge_index)
        else { return nil }

        let a = projection.point(edge.a)
        let b = projection.point(edge.b)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0.0001 else { return nil }
        let along = CGPoint(x: dx / len, y: dy / len)
        var normal = CGPoint(x: -along.y, y: along.x)

        let centre = projection.point(placement.center)
        let centroid = projection.point(DollhouseGeometry.centroid(room.polygon))
        let toRoom = CGPoint(x: centroid.x - centre.x, y: centroid.y - centre.y)
        if toRoom.x * normal.x + toRoom.y * normal.y < 0 {
            normal = CGPoint(x: -normal.x, y: -normal.y)
        }

        return OpeningFrame(centre: centre,
                            along: along,
                            inward: normal,
                            halfWidth: max(projection.length(placement.width) / 2, 2))
    }

    private static func drawOpenings(_ floor: Floor, projection: PlanProjection, context ctx: CGContext) {
        for opening in floor.openings {
            guard let frame = frame(for: opening, on: floor, projection: projection) else { continue }
            switch opening.kind {
            case .door: drawDoorGlyph(frame, context: ctx)
            case .window: drawWindowGlyph(frame, context: ctx)
            }
            if opening.isExit {
                drawExitMarker(frame, context: ctx)
            }
        }
    }

    /// A door: jamb ticks plus a leaf and its quarter-circle swing arc. Shape, not colour —
    /// this reads as a door on a photocopy.
    static func drawDoorGlyph(_ frame: OpeningFrame, context ctx: CGContext) {
        let jambA = add(frame.centre, scale(frame.along, -frame.halfWidth))
        let jambB = add(frame.centre, scale(frame.along, frame.halfWidth))
        drawJambTicks(frame, context: ctx)

        let radius = frame.halfWidth * 2
        let tip = add(jambA, scale(frame.inward, radius))
        PlanInk.stroke([jambA, tip], style: PlanInk.doorGlyph, in: ctx)

        ctx.saveGState()
        PlanInk.doorGlyph.apply(to: ctx)
        let start = atan2(tip.y - jambA.y, tip.x - jambA.x)
        let end = atan2(jambB.y - jambA.y, jambB.x - jambA.x)
        var delta = end - start
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        ctx.beginPath()
        ctx.addArc(center: jambA, radius: radius, startAngle: start, endAngle: end,
                   clockwise: delta < 0)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A window: a double line across the gap. Deliberately nothing like the door's arc.
    static func drawWindowGlyph(_ frame: OpeningFrame, context ctx: CGContext) {
        drawJambTicks(frame, context: ctx)
        for offset in [CGFloat(-1.7), 1.7] {
            let shift = scale(frame.inward, offset)
            let a = add(add(frame.centre, scale(frame.along, -frame.halfWidth)), shift)
            let b = add(add(frame.centre, scale(frame.along, frame.halfWidth)), shift)
            PlanInk.stroke([a, b], style: PlanInk.windowGlyph, in: ctx)
        }
    }

    static func drawJambTicks(_ frame: OpeningFrame, context ctx: CGContext) {
        for side in [CGFloat(-1), 1] {
            let base = add(frame.centre, scale(frame.along, side * frame.halfWidth))
            let a = add(base, scale(frame.inward, 3))
            let b = add(base, scale(frame.inward, -3))
            PlanInk.stroke([a, b], style: PlanInk.doorGlyph, in: ctx)
        }
    }

    /// A solid triangle pointing out of the building, plus the word EXIT. An opening whose
    /// `room_ids` contain the reserved `EXTERIOR` id is a way out — the schema's own rule.
    static func drawExitMarker(_ frame: OpeningFrame, label: Bool = true, context ctx: CGContext) {
        let outward = scale(frame.inward, -1)
        let base = add(frame.centre, scale(outward, 3.5))
        let apex = add(frame.centre, scale(outward, 11))
        let left = add(base, scale(frame.along, -4.5))
        let right = add(base, scale(frame.along, 4.5))

        ctx.saveGState()
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.beginPath()
        ctx.move(to: apex)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()

        guard label else { return }
        PDFText.draw("EXIT",
                     centredAt: add(frame.centre, scale(outward, 18)),
                     font: .systemFont(ofSize: 6.5, weight: .heavy),
                     gray: 0,
                     background: 1,
                     context: ctx)
    }

    // MARK: - Stairs

    private static func drawStairs(_ input: Input, projection: PlanProjection, context ctx: CGContext) {
        let onThisFloor = input.home.stairs.filter {
            $0.from.floor_id == input.floor.id || $0.to.floor_id == input.floor.id
        }
        for stair in onThisFloor where stair.footprint.count >= 3 {
            let points = stair.footprint.map(projection.point)
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()

            // Treads: parallel lines clipped to the footprint. Cheap, and unmistakably
            // "stairs" in any monochrome plan vocabulary.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let box = path.boundingBoxOfPath
            let long = longestEdgeDirection(points)
            let across = CGPoint(x: -long.y, y: long.x)
            let span = (box.width + box.height)
            let centre = CGPoint(x: box.midX, y: box.midY)
            var offset = -span / 2
            while offset <= span / 2 {
                let anchor = add(centre, scale(long, offset))
                let a = add(anchor, scale(across, -span))
                let b = add(anchor, scale(across, span))
                PlanInk.stroke([a, b], style: PlanInk.stairTread, in: ctx)
                offset += 5
            }
            ctx.restoreGState()

            ctx.saveGState()
            PlanInk.stairOutline.apply(to: ctx)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()

            PDFText.draw("STAIRS",
                         centredAt: CGPoint(x: box.midX, y: box.midY),
                         font: .systemFont(ofSize: 6, weight: .bold),
                         gray: 0,
                         background: 1,
                         context: ctx)
        }
    }

    private static func longestEdgeDirection(_ points: [CGPoint]) -> CGPoint {
        var best = CGPoint(x: 1, y: 0)
        var bestLength: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len = (dx * dx + dy * dy).squareRoot()
            if len > bestLength, len > 0.0001 {
                bestLength = len
                best = CGPoint(x: dx / len, y: dy / len)
            }
        }
        return best
    }

    // MARK: - Objects

    private static func drawObjects(_ floor: Floor, projection: PlanProjection, context ctx: CGContext) {
        for object in floor.objects {
            guard object.size_m.count >= 2 else { continue }
            let corners = objectCorners(object).map(projection.point)
            guard corners.count == 4 else { continue }
            PlanInk.stroke(corners + [corners[0]], style: PlanInk.objectOutline, in: ctx)
        }
    }

    /// The four plan-space corners of a rotated box. `rotation_deg` is CCW about the centre
    /// in the floor-local frame, per the schema.
    static func objectCorners(_ object: FloorObject) -> [Point] {
        let halfW = object.size_m[0] / 2
        let halfD = object.size_m[1] / 2
        let theta = object.rotation_deg * .pi / 180
        let c = cos(theta)
        let s = sin(theta)
        return [(-halfW, -halfD), (halfW, -halfD), (halfW, halfD), (-halfW, halfD)].map { dx, dy in
            Point(x: object.center.x + dx * c - dy * s,
                  y: object.center.y + dx * s + dy * c)
        }
    }

    // MARK: - Routes

    private static func drawRoutes(_ plan: RoutePlan,
                                   floorID: String,
                                   projection: PlanProjection,
                                   context ctx: CGContext) {
        // Backup routes first so the heavy primary line always sits on top where they overlap.
        var placedMarkers: [CGPoint] = []
        for kind in [RouteKind.secondary, .primary] {
            for room in plan.rooms {
                let route: Route? = kind == .primary ? room.primary : room.secondary
                guard let route else { continue }
                for run in floorRuns(of: route, floorID: floorID) where run.count >= 2 {
                    PlanInk.stroke(run.map { projection.point(x: $0.x, y: $0.y) },
                                   style: PlanInk.route(kind), in: ctx)
                }
            }
        }
        for kind in [RouteKind.secondary, .primary] {
            for room in plan.rooms {
                let route: Route? = kind == .primary ? room.primary : room.secondary
                guard let route else { continue }
                drawRouteMarkers(route, kind: kind, roomID: room.room_id, floorID: floorID,
                                 projection: projection, placed: &placedMarkers, context: ctx)
            }
        }
    }

    /// Splits a route into maximal runs of consecutive waypoints on one floor — the same
    /// split `RouteGeometry` makes for the 3D overlay, for the same reason: a floor crossing
    /// is a jump, not a line to draw.
    static func floorRuns(of route: Route, floorID: String) -> [[Waypoint]] {
        var runs: [[Waypoint]] = []
        var current: [Waypoint] = []
        for waypoint in route.waypoints {
            if waypoint.floor_id == floorID {
                current.append(waypoint)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    private static func drawRouteMarkers(_ route: Route,
                                         kind: RouteKind,
                                         roomID: String,
                                         floorID: String,
                                         projection: PlanProjection,
                                         placed: inout [CGPoint],
                                         context ctx: CGContext) {
        if kind == .primary,
           let start = RouteNarration.startWaypoint(of: route), start.floor_id == floorID {
            let p = projection.point(x: start.x, y: start.y)
            ctx.saveGState()
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            ctx.restoreGState()
        }

        for step in RouteNarration.stepAnchors(for: route, startingIn: roomID)
        where step.waypoint.floor_id == floorID {
            let anchor = projection.point(x: step.waypoint.x, y: step.waypoint.y)
            let centre = nudged(anchor, avoiding: placed)
            placed.append(centre)
            drawStepMarker(number: step.number, kind: kind, at: centre, context: ctx)
        }
    }

    /// Deterministic de-clutter: routes from different rooms converge on the same front door,
    /// so their markers would stack. Shift by a fixed spiral until clear — same input, same
    /// output, which is what keeps the PDF reproducible.
    private static func nudged(_ point: CGPoint, avoiding placed: [CGPoint]) -> CGPoint {
        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: 9, y: -9), CGPoint(x: -9, y: -9),
            CGPoint(x: 9, y: 9), CGPoint(x: -9, y: 9), CGPoint(x: 0, y: -15),
            CGPoint(x: 0, y: 15), CGPoint(x: 16, y: 0), CGPoint(x: -16, y: 0),
        ]
        for offset in offsets {
            let candidate = add(point, offset)
            let clash = placed.contains { hypot($0.x - candidate.x, $0.y - candidate.y) < 9 }
            if !clash { return candidate }
        }
        return point
    }

    /// Circle = primary, square = backup. A third non-colour channel, so even a marker that
    /// has drifted away from its line still says which route it belongs to.
    static func drawStepMarker(number: Int, kind: RouteKind, at centre: CGPoint, context ctx: CGContext) {
        let radius: CGFloat = 6.5
        let box = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.setFillColor(gray: PlanInk.markerFillGray, alpha: 1)
        PlanInk.marker.apply(to: ctx)
        if kind == .primary {
            ctx.fillEllipse(in: box)
            ctx.strokeEllipse(in: box)
        } else {
            ctx.fill(box)
            ctx.stroke(box)
        }
        ctx.restoreGState()

        PDFText.draw("\(number)",
                     centredAt: centre,
                     font: .systemFont(ofSize: 7, weight: .bold),
                     gray: 0,
                     context: ctx)
    }

    // MARK: - Scale bar

    /// A printed scale bar in metres — the HomeModel is in metres and the paper is not, so
    /// without this the drawing has no dimension at all.
    static func drawScaleBar(_ projection: PlanProjection, at origin: CGPoint, maxWidth: CGFloat,
                             context ctx: CGContext) {
        guard let metres = projection.scaleBarMetres(fitting: maxWidth) else { return }
        let width = projection.length(metres)
        let y = origin.y

        PlanInk.stroke([CGPoint(x: origin.x, y: y), CGPoint(x: origin.x + width, y: y)],
                       style: PlanInk.boxRule, in: ctx)
        for x in [origin.x, origin.x + width / 2, origin.x + width] {
            PlanInk.stroke([CGPoint(x: x, y: y - 3), CGPoint(x: x, y: y + 3)],
                           style: PlanInk.boxRule, in: ctx)
        }
        PDFText.draw("0",
                     at: CGPoint(x: origin.x, y: y + 5),
                     font: .systemFont(ofSize: 6.5, weight: .regular),
                     gray: 0.1, context: ctx)
        PDFText.draw(formattedMetres(metres),
                     at: CGPoint(x: origin.x + width + 3, y: y - 4),
                     font: .systemFont(ofSize: 7, weight: .semibold),
                     gray: 0.1, context: ctx)
    }

    static func formattedMetres(_ metres: Double) -> String {
        metres == metres.rounded() ? "\(Int(metres)) m" : String(format: "%.1f m", metres)
    }

    // MARK: - Small vector helpers

    private static func lerp(_ a: Point, _ b: Point, _ t: Double) -> Point {
        Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x + b.x, y: a.y + b.y)
    }

    private static func scale(_ a: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: a.x * k, y: a.y * k)
    }
}
