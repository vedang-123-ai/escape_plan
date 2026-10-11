//  EscapePlanPDF.swift
//  escape_plan — Export module
//
//  The printable escape plan: one page per floor (plus continuation pages only when a
//  household's step lists genuinely overflow), rendered with `UIGraphicsPDFRenderer`.
//
//  This is the artifact that ends up taped to a refrigerator. Two consequences drive every
//  decision in here:
//
//  1. IT MUST SURVIVE A BLACK-AND-WHITE PRINTER. Nothing is distinguished by hue — see
//     `PlanInk`. Primary route: solid, heavy. Backup: dashed, lighter. Doors are arcs,
//     windows are double lines, exits are filled triangles. Every page carries a legend.
//  2. IT MUST NOT LIE. Routes are only ever drawn and described from a `RoutePlan` the
//     deterministic engine produced. With no plan available (offline, never fetched), the
//     geometry still prints and the page says so in plain words instead of showing an empty
//     sheet or an invented line.
//
//  The meeting point is user free text, not a schema field — see `MeetingPointStore`.

import CoreGraphics
import Foundation
import UIKit

// `EscapePlanDocument` — the input to everything below — now lives in its own Foundation-only
// file so the snapshot extractor can be tested outside the simulator. See EscapePlanDocument.swift.

enum EscapePlanPDF {

    /// The rendered document plus the structure a test (or a caller) can assert on without
    /// re-parsing the PDF.
    struct Output {
        var data: Data
        var pageCount: Int
        /// First page index (0-based) for each floor id, in print order.
        var firstPageIndexByFloorID: [String: Int]
        /// Floor ids in the order they were printed (bottom-to-top by level).
        var floorOrder: [String]
    }

    // MARK: - Page geometry (US Letter portrait, the paper this gets printed on)

    static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 36

    private static let headerRect = CGRect(x: margin, y: 34, width: 540, height: 44)
    private static let meetingRect = CGRect(x: margin, y: 84, width: 540, height: 44)
    /// The plan drawing. Internal so tests can measure ink inside exactly this band.
    static let planRect = CGRect(x: margin, y: 134, width: 540, height: 258)
    private static let legendRect = CGRect(x: margin, y: 398, width: 540, height: 54)
    private static let summaryRect = CGRect(x: margin, y: 460, width: 540, height: 294)
    /// Continuation pages give the whole body over to the overflowing text. Reaching one
    /// means a household's step lists genuinely did not fit — the floor still got its own
    /// plan page first.
    private static let continuationSummaryRect = CGRect(x: margin, y: 134, width: 540, height: 620)
    private static let footerY: CGFloat = 762

    /// Two columns: the step lists are short lines, and a 540-point measure would waste half
    /// the sheet and push every household onto a continuation page.
    private static let summaryColumns = 2
    private static let columnGutter: CGFloat = 18

    // MARK: - Rendering

    static func render(_ document: EscapePlanDocument) -> Output {
        let pages = paginate(document)
        let bounds = CGRect(origin: .zero, size: pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(document.home.name) escape plan",
            kCGPDFContextCreator as String: "Escape Plan",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        let data = renderer.pdfData { rendererContext in
            for (index, page) in pages.enumerated() {
                rendererContext.beginPage()
                draw(page: page,
                     pageNumber: index + 1,
                     of: pages.count,
                     document: document,
                     context: rendererContext.cgContext)
            }
        }

        var firstPage: [String: Int] = [:]
        for (index, page) in pages.enumerated() where !page.isContinuation {
            if firstPage[page.floor.id] == nil { firstPage[page.floor.id] = index }
        }
        return Output(data: data,
                      pageCount: pages.count,
                      firstPageIndexByFloorID: firstPage,
                      floorOrder: document.home.floorsByLevel.map(\.id))
    }

    /// Renders the printable document asynchronously off the main actor to avoid freezing the UI.
    /// `UIGraphicsPDFRenderer` and CoreText drawing are thread-safe and do not touch UIKit views.
    nonisolated static func renderAsync(_ document: EscapePlanDocument) async -> Output {
        await Task.detached(priority: .userInitiated) {
            render(document)
        }.value
    }

    // MARK: - Pagination

    private struct Page {
        var floor: Floor
        var isContinuation: Bool
        var blocks: [Block]
    }

    /// One measurable run of text in the summary column.
    struct Block {
        var text: String
        var font: UIFont
        var gray: CGFloat
        var indent: CGFloat = 0
        var spacingBefore: CGFloat = 0
        var rule: Bool = false
        /// Never leave this block stranded at the foot of a column with its first line of
        /// content in the next one — a person's name orphaned away from their own steps is
        /// exactly the kind of thing nobody notices until it is printed and on a wall.
        var keepWithNext: Bool = false
    }

    private static func paginate(_ document: EscapePlanDocument) -> [Page] {
        let floors = document.home.floorsByLevel
        guard !floors.isEmpty else {
            // A home with no floors still deserves a sheet that explains itself.
            let placeholder = Floor(id: "-", level: 0, name: "No floors yet", height_m: 0, rooms: [])
            return [Page(floor: placeholder, isContinuation: false, blocks: [
                Block(text: "This home has no floors yet. Build or scan it in the app, then export again.",
                      font: .systemFont(ofSize: 10), gray: 0.2)
            ])]
        }

        var pages: [Page] = []
        for floor in floors {
            var remaining = document.isResponderSnapshot
                ? responderSnapshotBlocks(for: floor, document: document)
                : summaryBlocks(for: floor, document: document)
            var isContinuation = false
            repeat {
                let rect = isContinuation ? continuationSummaryRect : summaryRect
                // Paginated by the SAME layout function that draws, so a page can never be
                // measured one way and rendered another.
                let (placed, overflow) = layout(remaining, in: rect)
                pages.append(Page(floor: floor, isContinuation: isContinuation,
                                  blocks: Array(remaining.prefix(placed.count))))
                remaining = overflow
                isContinuation = true
            } while !remaining.isEmpty
        }
        return pages
    }

    /// Flows blocks down column 1, then column 2. Returns what fitted (with its frame) and
    /// what did not. Always places at least one block, so an over-tall block cannot spin the
    /// pagination loop forever.
    private static func layout(_ blocks: [Block], in rect: CGRect)
        -> (placed: [(block: Block, frame: CGRect)], overflow: [Block]) {
        let columnWidth = (rect.width - columnGutter * CGFloat(summaryColumns - 1))
            / CGFloat(summaryColumns)
        var placed: [(block: Block, frame: CGRect)] = []
        var queue = blocks
        var column = 0
        var y = rect.minY
        var atColumnTop = true

        while let block = queue.first, column < summaryColumns {
            let x = rect.minX + CGFloat(column) * (columnWidth + columnGutter)
            let width = columnWidth - block.indent
            let height = PDFText.height(block.text, width: width, font: block.font)
            var required = height
            if block.keepWithNext, queue.count > 1 {
                let next = queue[1]
                required += next.spacingBefore
                    + PDFText.height(next.text, width: columnWidth - next.indent, font: next.font)
            }
            let top = y + (atColumnTop ? 0 : block.spacingBefore)
            if !atColumnTop, top + required > rect.maxY {
                column += 1
                y = rect.minY
                atColumnTop = true
                continue
            }
            placed.append((block, CGRect(x: x + block.indent, y: top, width: width, height: height)))
            y = top + height + 1.5
            atColumnTop = false
            queue.removeFirst()
        }
        return (placed, queue)
    }

    // MARK: - Summary content
    
    private static func responderSnapshotBlocks(for floor: Floor, document: EscapePlanDocument) -> [Block] {
        let home = document.home
        var blocks: [Block] = []
        
        blocks.append(sectionTitle("FIRST RESPONDER SUMMARY — \(floor.name.uppercased())"))
        blocks.append(Block(
            text: "This is an automatically generated offline snapshot. Names are excluded by design.",
            font: .italicSystemFont(ofSize: 9), gray: 0.15, spacingBefore: 2))
        // Fixed, on every responder-snapshot page — never conditional on whether the home
        // happens to be stale right now. Same wording as the JSON (ResponderSnapshotJSON),
        // so the paper and the file can never disagree.
        blocks.append(Block(
            text: ResponderSnapshotJSON.fixedStalenessNote,
            font: .italicSystemFont(ofSize: 9), gray: 0.15, spacingBefore: 2))
        blocks.append(Block(
            text: ResponderSnapshotJSON.fixedTacticalDisclaimer,
            font: .italicSystemFont(ofSize: 9), gray: 0.15, spacingBefore: 2))

        // document.generatedAt, not Date(): the JSON's isStale is computed from this same
        // stamped time (ResponderSnapshotExtractor), so the printed page and the file can
        // never disagree about a document rendered later than it was stamped.
        var isStale = true
        if let lastScanned = home.meta.last_scanned {
            isStale = document.generatedAt.timeIntervalSince(lastScanned) > ResponderSnapshotExtractor.staleWindow
        }

        if isStale {
            blocks.append(Block(
                text: "WARNING: Home scan is missing or over 30 days old. Layout and occupant data may be inaccurate.",
                font: .systemFont(ofSize: 10, weight: .heavy), gray: 0, spacingBefore: 6))
        }
            
        // Vulnerable occupants on this floor
        var vulnerableCounts: [String: Int] = [:]
        for profile in home.profiles {
            if profile.tags.contains(.mobility_limited) || profile.tags.contains(.vision_impaired) {
                if let located = home.locateRoom(profile.bedroom_room_id), located.floorId == floor.id {
                    vulnerableCounts[located.room.name] = (vulnerableCounts[located.room.name] ?? 0) + 1
                }
            }
        }
        
        if !vulnerableCounts.isEmpty {
            blocks.append(Block(text: "Occupants Needing Assistance:", font: .systemFont(ofSize: 10.5, weight: .bold), gray: 0, spacingBefore: 8, keepWithNext: true))
            for (roomName, count) in vulnerableCounts.sorted(by: { $0.key < $1.key }) {
                blocks.append(Block(text: "• \(count) occupant(s) — \(roomName)", font: .systemFont(ofSize: 10), gray: 0.1, indent: 6, spacingBefore: 2))
            }
        }
        
        // Safety points (shutoffs) on this floor
        if !floor.safety_points.isEmpty {
            blocks.append(Block(text: "Utility Shutoffs & Points of Interest:", font: .systemFont(ofSize: 10.5, weight: .bold), gray: 0, spacingBefore: 8, keepWithNext: true))
            for pt in floor.safety_points.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
                let title = pt.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
                blocks.append(Block(text: "• \(title)", font: .systemFont(ofSize: 10), gray: 0.1, indent: 6, spacingBefore: 2))
            }
        }
        
        // Hazards on this floor
        var hazards: [String] = []
        if let plan = document.plan {
            for roomPlan in plan.rooms where roomPlan.floor_id == floor.id {
                for finding in roomPlan.findings where finding.kind == .no_viable_route || finding.kind == .no_viable_safe_room {
                    hazards.append("\(finding.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized): \(roomPlan.room_name)")
                }
            }
        }
        
        if !hazards.isEmpty {
            blocks.append(Block(text: "Identified Hazards:", font: .systemFont(ofSize: 10.5, weight: .bold), gray: 0, spacingBefore: 8, keepWithNext: true))
            for hazard in hazards {
                blocks.append(Block(text: "• \(hazard)", font: .systemFont(ofSize: 10), gray: 0.1, indent: 6, spacingBefore: 2))
            }
        }
        
        // Only append the global info on the first printed floor (level == 0 usually, or just the first in array)
        if floor.id == home.floorsByLevel.first?.id {
            blocks.append(sectionTitle("HOME OVERVIEW"))
            if let score = document.scoreResponse?.score {
                blocks.append(Block(text: "Composite Readiness Score: \(score)/100", font: .systemFont(ofSize: 10), gray: 0.1, spacingBefore: 4))
            }
            var safeRoomName: String? = nil
            if let srItem = document.scoreResponse?.checklist.first(where: { $0.category == .safe_room }) {
                if let component = srItem.component, let located = home.locateRoom(component) {
                    safeRoomName = located.room.name
                } else {
                    safeRoomName = srItem.title
                }
            }
            if let name = safeRoomName {
                blocks.append(Block(text: "Computed Storm Safe Room: \(name)", font: .systemFont(ofSize: 10), gray: 0.1, spacingBefore: 2))
            }

            let hazardSummary = SnapshotHazardSummary.summarize(checklist: document.scoreResponse?.checklist ?? [])
            if !hazardSummary.isEmpty {
                blocks.append(Block(text: "Hazard Summary (engine findings, whole home):", font: .systemFont(ofSize: 10.5, weight: .bold), gray: 0, spacingBefore: 8, keepWithNext: true))
                for entry in hazardSummary {
                    let citation = entry.citation.map { " [cite: \($0)]" } ?? ""
                    blocks.append(Block(
                        text: "• \(entry.category).\(entry.ruleID): \(entry.count)\(citation)",
                        font: .systemFont(ofSize: 10), gray: 0.1, indent: 6, spacingBefore: 2))
                }
            }

            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            let asOfText = home.meta.last_scanned.map { "As of (last scan): \(df.string(from: $0))" }
                ?? "As of: no scan on record"
            blocks.append(Block(text: asOfText, font: .systemFont(ofSize: 9), gray: 0.2, spacingBefore: 4))
            blocks.append(Block(text: "Generated At: \(df.string(from: document.generatedAt))", font: .systemFont(ofSize: 9), gray: 0.2, spacingBefore: 2))
        }
        
        return blocks
    }

    private static func summaryBlocks(for floor: Floor, document: EscapePlanDocument) -> [Block] {
        let home = document.home
        var blocks: [Block] = []

        if !document.hasRoutes {
            blocks.append(Block(
                text: "ESCAPE ROUTES ARE NOT ON THIS PRINTOUT",
                font: .systemFont(ofSize: 9, weight: .heavy), gray: 0, spacingBefore: 2))
            blocks.append(Block(
                text: "This home's routes are computed by the Escape Plan routing engine, and no "
                    + "computed routes were saved on this device. The floor plan above is real and "
                    + "complete; the routes are simply absent rather than guessed. Open this home in "
                    + "the app while connected, then export again.",
                font: .systemFont(ofSize: 9), gray: 0.15, spacingBefore: 3))
        }

        let peopleHere = home.profiles.filter {
            home.locateRoom($0.bedroom_room_id)?.floorId == floor.id
        }
        let roomPlans = document.plan?.rooms.filter { $0.floor_id == floor.id } ?? []

        if !peopleHere.isEmpty {
            blocks.append(sectionTitle("WHO SLEEPS ON THIS FLOOR, AND HOW THEY GET OUT"))
            for profile in peopleHere {
                blocks.append(Block(text: RouteNarration.profileLine(profile, in: home),
                                    font: .systemFont(ofSize: 10.5, weight: .bold),
                                    gray: 0, spacingBefore: 6, keepWithNext: true))
                guard let roomPlan = document.plan?.rooms.first(where: {
                    $0.room_id == profile.bedroom_room_id
                }) else {
                    if document.hasRoutes {
                        blocks.append(Block(
                            text: "The routing engine returned no plan for this room.",
                            font: .systemFont(ofSize: 9), gray: 0.2, indent: 12, spacingBefore: 2))
                    }
                    continue
                }
                blocks.append(contentsOf: routeBlocks(for: roomPlan, document: document))
            }
        } else if !roomPlans.isEmpty {
            blocks.append(sectionTitle("ROUTES BY ROOM ON THIS FLOOR"))
            for roomPlan in roomPlans {
                let line: String
                if let primary = roomPlan.primary {
                    line = "\(roomPlan.room_name): \(RouteNarration.summaryLine(for: primary))"
                } else {
                    line = "\(roomPlan.room_name): no route was computed."
                }
                blocks.append(Block(text: "• " + line, font: .systemFont(ofSize: 9),
                                    gray: 0.1, indent: 6, spacingBefore: 2))
            }
            if !home.profiles.isEmpty {
                blocks.append(Block(text: "Nobody's bedroom is on this floor.",
                                    font: .italicSystemFont(ofSize: 8.5), gray: 0.35, spacingBefore: 4))
            }
        }

        // The engine's own warnings, printed verbatim. Never suppressed to make a page tidy.
        let findings = roomPlans.flatMap(\.findings)
        if !findings.isEmpty {
            blocks.append(sectionTitle("WHAT THE ROUTING ENGINE FLAGGED"))
            for finding in findings {
                blocks.append(Block(text: "! " + RouteNarration.findingSentence(finding, in: home),
                                    font: .systemFont(ofSize: 9, weight: .medium),
                                    gray: 0.05, indent: 6, spacingBefore: 2))
            }
        }
        return blocks
    }

    private static func routeBlocks(for roomPlan: RoomRoutePlan,
                                    document: EscapePlanDocument) -> [Block] {
        var blocks: [Block] = []
        for kind in [RouteKind.primary, .secondary] {
            guard let narrative = RouteNarration.narrate(room: roomPlan,
                                                         in: document.home,
                                                         kind: kind,
                                                         meetingPoint: document.meetingPoint)
            else {
                if kind == .secondary {
                    blocks.append(Block(
                        text: "Backup route: none was computed for this room.",
                        font: .systemFont(ofSize: 8.5, weight: .semibold),
                        gray: 0.25, indent: 12, spacingBefore: 3))
                }
                continue
            }
            blocks.append(Block(
                text: "\(kind.displayName) (\(kind.strokeDescription) on the plan) — \(narrative.summary)",
                font: .systemFont(ofSize: 8.5, weight: .semibold),
                gray: 0.25, indent: 12, spacingBefore: 3))
            for step in narrative.steps {
                blocks.append(Block(text: step.numbered, font: .systemFont(ofSize: 9),
                                    gray: 0, indent: 22, spacingBefore: 1))
            }
            for note in narrative.notes {
                blocks.append(Block(text: note, font: .italicSystemFont(ofSize: 8.5),
                                    gray: 0.3, indent: 22, spacingBefore: 1))
            }
        }
        return blocks
    }

    private static func sectionTitle(_ text: String) -> Block {
        Block(text: text, font: .systemFont(ofSize: 8, weight: .heavy),
              gray: 0.35, spacingBefore: 10, rule: true, keepWithNext: true)
    }

    // MARK: - Page drawing

    private static func draw(page: Page,
                             pageNumber: Int,
                             of total: Int,
                             document: EscapePlanDocument,
                             context ctx: CGContext) {
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(origin: .zero, size: pageSize))

        drawHeader(page: page, document: document, context: ctx)
        drawMeetingPoint(document.meetingPoint, in: meetingRect, context: ctx)

        let summaryArea: CGRect
        if page.isContinuation {
            summaryArea = continuationSummaryRect
        } else {
            let projection = FloorPlanDrawing.draw(
                FloorPlanDrawing.Input(home: document.home, floor: page.floor, plan: document.plan),
                in: planRect, context: ctx)
            ctx.saveGState()
            PlanInk.hairline.apply(to: ctx)
            ctx.stroke(planRect)
            ctx.restoreGState()
            FloorPlanDrawing.drawScaleBar(projection,
                                          at: CGPoint(x: planRect.minX + 12, y: planRect.maxY - 12),
                                          maxWidth: 150,
                                          context: ctx)
            drawLegend(in: legendRect, context: ctx)
            summaryArea = summaryRect
        }

        drawBlocks(page.blocks, in: summaryArea, context: ctx)
        drawFooter(page: page, pageNumber: pageNumber, of: total, document: document, context: ctx)
    }

    private static func drawHeader(page: Page, document: EscapePlanDocument, context ctx: CGContext) {
        PDFText.draw(document.home.name,
                     at: CGPoint(x: headerRect.minX, y: headerRect.minY),
                     font: .systemFont(ofSize: 19, weight: .bold), gray: 0, context: ctx)

        let generated = "Generated \(document.generatedAt.formatted(date: .abbreviated, time: .shortened))"
        drawRightAligned(generated, rightEdge: headerRect.maxX, y: headerRect.minY + 4,
                         font: .systemFont(ofSize: 8.5), gray: 0.35, context: ctx)

        let suffix = page.isContinuation ? " (continued)" : ""
        let floorLine = "\(page.floor.name) · level \(page.floor.level)\(suffix)"
        PDFText.draw(floorLine,
                     at: CGPoint(x: headerRect.minX, y: headerRect.minY + 24),
                     font: .systemFont(ofSize: 11, weight: .semibold), gray: 0.2, context: ctx)

        let routesLine: String
        if let computed = document.routesComputedAt {
            routesLine = "Routes computed \(computed.formatted(date: .abbreviated, time: .shortened))"
        } else if document.hasRoutes {
            routesLine = "Routes from the Escape Plan routing engine"
        } else {
            routesLine = "Routes not included"
        }
        drawRightAligned(routesLine, rightEdge: headerRect.maxX, y: headerRect.minY + 25,
                         font: .systemFont(ofSize: 8.5), gray: 0.35, context: ctx)

        PlanInk.stroke([CGPoint(x: headerRect.minX, y: headerRect.maxY),
                        CGPoint(x: headerRect.maxX, y: headerRect.maxY)],
                       style: PlanInk.boxRule, in: ctx)
    }

    /// The meeting point gets a box of its own on every page: on a printed plan it is the one
    /// instruction that is not on the drawing, and the one everyone forgets.
    private static func drawMeetingPoint(_ text: String, in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        PlanInk.boxRule.apply(to: ctx)
        ctx.stroke(rect)
        ctx.restoreGState()

        PDFText.draw("OUTSIDE MEETING PLACE",
                     at: CGPoint(x: rect.minX + 8, y: rect.minY + 5),
                     font: .systemFont(ofSize: 7, weight: .heavy), gray: 0.35, context: ctx)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            PlanInk.stroke([CGPoint(x: rect.minX + 9, y: rect.maxY - 9),
                            CGPoint(x: rect.maxX - 120, y: rect.maxY - 9)],
                           style: PlanInk.hairline, in: ctx)
            drawRightAligned("write it in", rightEdge: rect.maxX - 8, y: rect.maxY - 18,
                             font: .italicSystemFont(ofSize: 8.5), gray: 0.4, context: ctx)
        } else {
            PDFText.drawWrapped(trimmed,
                                in: CGRect(x: rect.minX + 8, y: rect.minY + 16,
                                           width: rect.width - 16, height: rect.height - 18),
                                font: .systemFont(ofSize: 14, weight: .bold), gray: 0, context: ctx)
        }
    }

    private static func drawBlocks(_ blocks: [Block], in rect: CGRect, context ctx: CGContext) {
        for (block, frame) in layout(blocks, in: rect).placed {
            if block.rule {
                PlanInk.stroke([CGPoint(x: frame.minX, y: frame.minY - 3),
                                CGPoint(x: frame.maxX, y: frame.minY - 3)],
                               style: PlanInk.hairline, in: ctx)
            }
            PDFText.drawWrapped(block.text, in: frame,
                                font: block.font, gray: block.gray, context: ctx)
        }
    }

    private static func drawFooter(page: Page,
                                   pageNumber: Int,
                                   of total: Int,
                                   document: EscapePlanDocument,
                                   context ctx: CGContext) {
        PlanInk.stroke([CGPoint(x: margin, y: footerY - 6),
                        CGPoint(x: pageSize.width - margin, y: footerY - 6)],
                       style: PlanInk.hairline, in: ctx)
        PDFText.draw("Escape Plan · \(document.home.name) · print in black and white and post it where everyone can see it",
                     at: CGPoint(x: margin, y: footerY),
                     font: .systemFont(ofSize: 7), gray: 0.4, context: ctx)
        drawRightAligned("Page \(pageNumber) of \(total)",
                         rightEdge: pageSize.width - margin, y: footerY,
                         font: .systemFont(ofSize: 7, weight: .semibold), gray: 0.4, context: ctx)
    }

    private static func drawRightAligned(_ text: String, rightEdge: CGFloat, y: CGFloat,
                                         font: UIFont, gray: CGFloat, context ctx: CGContext) {
        let width = (text as NSString).size(withAttributes: PDFText.attributes(font: font, gray: gray)).width
        PDFText.draw(text, at: CGPoint(x: rightEdge - width, y: y), font: font, gray: gray, context: ctx)
    }

    // MARK: - Legend

    /// On EVERY page, because a page can be torn off or handed to a neighbour on its own, and
    /// because the whole greyscale scheme is worthless if the reader has to guess what a
    /// dashed line means.
    private static func drawLegend(in rect: CGRect, context ctx: CGContext) {
        ctx.saveGState()
        PlanInk.hairline.apply(to: ctx)
        ctx.stroke(rect)
        ctx.restoreGState()

        PDFText.draw("HOW TO READ THIS PLAN",
                     at: CGPoint(x: rect.minX + 8, y: rect.minY + 4),
                     font: .systemFont(ofSize: 7, weight: .heavy), gray: 0.35, context: ctx)

        let items: [(String, (CGPoint) -> Void)] = [
            ("Primary route", { centre in
                PlanInk.stroke([CGPoint(x: centre.x - 13, y: centre.y), CGPoint(x: centre.x + 13, y: centre.y)],
                               style: PlanInk.primaryRoute, in: ctx)
            }),
            ("Backup route", { centre in
                PlanInk.stroke([CGPoint(x: centre.x - 13, y: centre.y), CGPoint(x: centre.x + 13, y: centre.y)],
                               style: PlanInk.secondaryRoute, in: ctx)
            }),
            ("Step 1, 2, 3…", { centre in
                FloorPlanDrawing.drawStepMarker(number: 1, kind: .primary,
                                                at: CGPoint(x: centre.x - 8, y: centre.y), context: ctx)
                FloorPlanDrawing.drawStepMarker(number: 2, kind: .secondary,
                                                at: CGPoint(x: centre.x + 8, y: centre.y), context: ctx)
            }),
            ("Where you start", { centre in
                ctx.saveGState()
                ctx.setFillColor(gray: 0, alpha: 1)
                ctx.fillEllipse(in: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6))
                ctx.restoreGState()
            }),
            ("Door", { centre in
                FloorPlanDrawing.drawDoorGlyph(sampleFrame(at: CGPoint(x: centre.x - 5, y: centre.y - 5)),
                                               context: ctx)
            }),
            ("Window", { centre in
                FloorPlanDrawing.drawWindowGlyph(sampleFrame(at: centre), context: ctx)
            }),
            ("Way out", { centre in
                // No "EXIT" word here: the legend row already carries the label, and the
                // glyph's own text would climb into the row above.
                FloorPlanDrawing.drawExitMarker(sampleFrame(at: CGPoint(x: centre.x, y: centre.y + 6)),
                                                label: false, context: ctx)
            }),
            ("Stairs / furniture", { centre in
                for offset in stride(from: CGFloat(-6), through: 6, by: 3) {
                    PlanInk.stroke([CGPoint(x: centre.x - 13 + offset + 6, y: centre.y - 5),
                                    CGPoint(x: centre.x - 13 + offset + 6, y: centre.y + 5)],
                                   style: PlanInk.stairTread, in: ctx)
                }
                PlanInk.stroke([CGPoint(x: centre.x + 4, y: centre.y - 5),
                                CGPoint(x: centre.x + 16, y: centre.y - 5),
                                CGPoint(x: centre.x + 16, y: centre.y + 5),
                                CGPoint(x: centre.x + 4, y: centre.y + 5),
                                CGPoint(x: centre.x + 4, y: centre.y - 5)],
                               style: PlanInk.objectOutline, in: ctx)
            }),
        ]

        let columns = 4
        let columnWidth = (rect.width - 16) / CGFloat(columns)
        for (index, item) in items.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = rect.minX + 8 + CGFloat(column) * columnWidth
            let y = rect.minY + 20 + CGFloat(row) * 20
            item.1(CGPoint(x: x + 16, y: y + 5))
            PDFText.draw(item.0,
                         at: CGPoint(x: x + 36, y: y),
                         font: .systemFont(ofSize: 7.5), gray: 0.1, context: ctx)
        }
    }

    /// A horizontal opening 22 points wide, opening downward — the legend's stand-in for a
    /// real wall placement, drawn by exactly the same glyph code the plan uses.
    private static func sampleFrame(at centre: CGPoint) -> FloorPlanDrawing.OpeningFrame {
        FloorPlanDrawing.OpeningFrame(centre: centre,
                                      along: CGPoint(x: 1, y: 0),
                                      inward: CGPoint(x: 0, y: 1),
                                      halfWidth: 5.5)
    }
}
