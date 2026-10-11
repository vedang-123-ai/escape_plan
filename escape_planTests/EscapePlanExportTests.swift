//  EscapePlanExportTests.swift
//  escape_planTests — printable escape plan (Export/)
//
//  The acceptance criterion for this feature is not "a PDF came out" — it is "a person can
//  read it off a black-and-white printout on a fridge door". So the greyscale tests below do
//  the real thing: they rasterise the production stroke code into a **DeviceGray** bitmap
//  (which IS desaturation — there is no colour channel left to cheat with) and assert that
//  the primary and backup routes are still tellable apart by continuity and weight alone.

import CoreGraphics
import Foundation
import SceneKit
import Testing
import UIKit

@testable import escape_plan

@Suite("Escape plan export")
struct EscapePlanExportTests {

    // MARK: - Helpers

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func routeSample(_ name: String) throws -> RoutePlan {
        let url = repoRoot.appendingPathComponent("docs/route-samples/\(name).routeplan.json")
        return try HomeModel.decoder.decode(RoutePlan.self, from: Data(contentsOf: url))
    }

    /// An 8-bit greyscale raster. Built in `CGColorSpaceCreateDeviceGray`, so anything that
    /// only differed by hue has already collapsed by the time we look at it.
    struct GrayRaster {
        var width: Int
        var height: Int
        var pixels: [UInt8]

        /// Indexed in Core Graphics coordinates — origin bottom-left, y up — which is the
        /// frame both the bitmap context and the PDF page are drawn in. The backing buffer's
        /// first row is the top of the image, hence the flip.
        func value(x: Int, y: Int) -> UInt8 { pixels[(height - 1 - y) * width + x] }

        /// Rows in column `x` dark enough to read as ink on paper.
        func inkRows(inColumn x: Int, threshold: UInt8 = 128) -> Int {
            (0..<height).reduce(0) { $0 + (value(x: x, y: $1) < threshold ? 1 : 0) }
        }

        var inkFraction: Double {
            Double(pixels.reduce(0) { $0 + (Int($1) < 250 ? 1 : 0) }) / Double(pixels.count)
        }

        var darkestValue: UInt8 { pixels.min() ?? 255 }

        /// Ink fraction inside a sub-rectangle. The default threshold counts only true ink:
        /// the room fill is a deliberately light 0.92 grey (≈235) and must NOT be counted,
        /// or route lines drawn on top of it would be invisible to the measurement.
        func inkFraction(in rect: CGRect, threshold: UInt8 = 100) -> Double {
            let x0 = max(0, Int(rect.minX)), x1 = min(width, Int(rect.maxX))
            let y0 = max(0, Int(rect.minY)), y1 = min(height, Int(rect.maxY))
            guard x1 > x0, y1 > y0 else { return 0 }
            var inked = 0
            for y in y0..<y1 {
                for x in x0..<x1 where value(x: x, y: y) < threshold { inked += 1 }
            }
            return Double(inked) / Double((x1 - x0) * (y1 - y0))
        }
    }

    /// `EscapePlanPDF.planRect` in raster coordinates. The PDF's origin is bottom-left and
    /// the page layout is written in UIKit's top-left frame, so the band flips.
    static let rasterScale: CGFloat = 1.5
    static var planBand: CGRect {
        let r = EscapePlanPDF.planRect
        let s = rasterScale
        return CGRect(x: r.minX * s,
                      y: (EscapePlanPDF.pageSize.height - r.maxY) * s,
                      width: r.width * s,
                      height: r.height * s)
    }

    static func rasterise(width: Int, height: Int, _ body: (CGContext) -> Void) throws -> GrayRaster {
        var pixels = [UInt8](repeating: 255, count: width * height)
        try pixels.withUnsafeMutableBytes { buffer in
            let ctx = try #require(CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue))
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            body(ctx)
        }
        return GrayRaster(width: width, height: height, pixels: pixels)
    }

    static func document(_ data: Data) throws -> CGPDFDocument {
        let provider = try #require(CGDataProvider(data: data as CFData))
        return try #require(CGPDFDocument(provider))
    }

    static func rasterisePage(_ data: Data, page pageNumber: Int, scale: CGFloat = 1.5) throws -> GrayRaster {
        let pdf = try document(data)
        let page = try #require(pdf.page(at: pageNumber))
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * scale)
        let height = Int(box.height * scale)
        return try rasterise(width: width, height: height) { ctx in
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            ctx.drawPDFPage(page)
        }
    }

    static func document(for fixture: HomeFixture,
                         plan: RoutePlan?,
                         meetingPoint: String = "The big oak across the street") throws -> EscapePlanDocument {
        EscapePlanDocument(home: try FixtureLoader.load(fixture),
                           plan: plan,
                           routesComputedAt: plan == nil ? nil : Date(timeIntervalSince1970: 1_770_000_000),
                           meetingPoint: meetingPoint,
                           generatedAt: Date(timeIntervalSince1970: 1_770_000_000))
    }

    // MARK: - Greyscale legibility (the hard criterion)

    @Test("Every ink on the plan is dark enough to print, and none needs colour")
    func inksArePrintable() {
        for ink in PlanInk.allInks {
            #expect(ink.style.gray <= 0.5, "\(ink.name) is too light to read on paper")
            #expect(ink.style.lineWidth > 0)
        }
    }

    @Test("Primary is solid and heavy, backup is broken and lighter — in greyscale, measured")
    func primaryAndSecondaryStayApartInGreyscale() throws {
        // One horizontal line of each style, drawn by the production stroke function, into a
        // pure-greyscale raster. Then: continuity, weight, darkness.
        func measure(_ style: InkStyle) throws -> (coverage: Double, thickness: Int, darkest: UInt8) {
            let raster = try Self.rasterise(width: 240, height: 40) { ctx in
                PlanInk.stroke([CGPoint(x: 20, y: 20), CGPoint(x: 220, y: 20)], style: style, in: ctx)
            }
            let columns = Array(25..<215)
            let inked = columns.filter { raster.inkRows(inColumn: $0) > 0 }
            let thickness = columns.map { raster.inkRows(inColumn: $0) }.max() ?? 0
            return (Double(inked.count) / Double(columns.count), thickness, raster.darkestValue)
        }

        let primary = try measure(PlanInk.primaryRoute)
        let secondary = try measure(PlanInk.secondaryRoute)

        // 1. Continuity: the primary route is unbroken; the backup route is visibly dashed.
        #expect(primary.coverage > 0.98,
                "primary must be continuous, measured \(primary.coverage)")
        #expect(secondary.coverage > 0.25 && secondary.coverage < 0.85,
                "backup must read as dashed, measured \(secondary.coverage)")

        // 2. Weight: the primary line is measurably thicker after desaturation.
        #expect(primary.thickness > secondary.thickness,
                "primary \(primary.thickness)px vs backup \(secondary.thickness)px")

        // 3. Both are genuinely ink, not grey suggestions.
        #expect(primary.darkest < 60)
        #expect(secondary.darkest < 128)
    }

    @Test("Step markers differ by shape, not colour: circle for primary, square for backup")
    func markerShapesDifferInGreyscale() throws {
        func corners(_ kind: RouteKind) throws -> Int {
            let raster = try Self.rasterise(width: 40, height: 40) { ctx in
                FloorPlanDrawing.drawStepMarker(number: 1, kind: kind,
                                                at: CGPoint(x: 20, y: 20), context: ctx)
            }
            // The square's edges run through its bounding-box corners; the circle's arc has
            // already curved away from them, leaving white paper there.
            let offsets = [(-6, -6), (6, -6), (-6, 6), (6, 6)]
            return offsets.filter { raster.value(x: 20 + $0.0, y: 20 + $0.1) < 200 }.count
        }
        let squareCorners = try corners(.secondary)
        let circleCorners = try corners(.primary)
        #expect(squareCorners > circleCorners,
                "square marker corners \(squareCorners) must exceed circle corners \(circleCorners)")
    }

    @Test("Door and window glyphs are different shapes, not different colours")
    func doorAndWindowGlyphsDiffer() throws {
        func raster(_ draw: @escaping (CGContext) -> Void) throws -> GrayRaster {
            try Self.rasterise(width: 60, height: 60, draw)
        }
        let frame = FloorPlanDrawing.OpeningFrame(centre: CGPoint(x: 30, y: 20),
                                                  along: CGPoint(x: 1, y: 0),
                                                  inward: CGPoint(x: 0, y: 1),
                                                  halfWidth: 9)
        let door = try raster { FloorPlanDrawing.drawDoorGlyph(frame, context: $0) }
        let window = try raster { FloorPlanDrawing.drawWindowGlyph(frame, context: $0) }

        #expect(door.inkFraction > 0, "the door glyph drew nothing")
        #expect(window.inkFraction > 0, "the window glyph drew nothing")
        #expect(door.pixels != window.pixels)

        // The door's swing arc sweeps a full opening-width into the room (the frame's inward
        // direction is +y here); the window's double line and jamb ticks stay on the wall.
        // The frame's centre is at y = 20 and its inward direction is +y, so the door's
        // swing (radius = one opening width = 18) reaches y ≈ 33. The window's double line
        // and jamb ticks never leave y ≤ 23.
        func inkDeepInRoom(_ raster: GrayRaster) -> Bool {
            (26..<40).contains { y in (0..<60).contains { x in raster.value(x: x, y: y) < 200 } }
        }
        #expect(inkDeepInRoom(door), "the door's swing arc must reach into the room")
        #expect(!inkDeepInRoom(window), "the window glyph must not draw a swing")
    }

    // MARK: - Document structure

    @Test("One page per floor, with the routes drawn on them")
    func onePagePerFloor() throws {
        for (fixture, sample) in [(HomeFixture.bungalow, "bungalow"),
                                  (HomeFixture.twostory, "twostory"),
                                  (HomeFixture.apartment, "apartment")] {
            let document = try Self.document(for: fixture, plan: try Self.routeSample(sample))
            let output = EscapePlanPDF.render(document)

            #expect(output.pageCount == document.home.floors.count,
                    "\(fixture.rawValue): \(output.pageCount) pages, \(document.home.floors.count) floors")
            let pdf = try Self.document(output.data)
            #expect(pdf.numberOfPages == output.pageCount)

            for floor in document.home.floors {
                #expect(output.firstPageIndexByFloorID[floor.id] != nil,
                        "\(fixture.rawValue): floor \(floor.id) has no page")
            }
            #expect(output.floorOrder == document.home.floorsByLevel.map(\.id))
        }
    }

    @Test("Rendered pages are not blank — real ink, including solid black")
    func pagesAreNotBlank() throws {
        let document = try Self.document(for: .twostory, plan: try Self.routeSample("twostory"))
        let output = EscapePlanPDF.render(document)

        for page in 1...output.pageCount {
            let raster = try Self.rasterisePage(output.data, page: page)
            #expect(raster.inkFraction > 0.01,
                    "page \(page) is effectively blank (ink fraction \(raster.inkFraction))")
            #expect(raster.darkestValue < 40,
                    "page \(page) has no true black — route and wall ink is missing")
        }
    }

    @Test("The jagged three-floor fixture prints three pages that share one scale")
    func jaggedStackPrintsEveryFloor() throws {
        let document = try Self.document(for: .jagged, plan: nil, meetingPoint: "")
        let output = EscapePlanPDF.render(document)
        #expect(output.pageCount == document.home.floors.count)
        #expect(output.pageCount >= 3)

        // One projection for the whole home means floors line up sheet to sheet.
        let bounds = DollhouseGeometry.bounds(of: document.home)
        let rect = CGRect(x: 0, y: 0, width: 500, height: 300)
        let a = PlanProjection(bounds: bounds, in: rect)
        let b = PlanProjection(bounds: bounds, in: rect)
        #expect(a.scale == b.scale)
        #expect(a.origin == b.origin)
    }

    @Test("PlanProjection and DollhouseGeometry agree on spatial orientation for an asymmetric room")
    func planProjectionAgreesWithDollhouseOrientation() {
        // Construct an asymmetric L-shaped room:
        // (0,0) -> (4,0) -> (4,2) -> (2,2) -> (2,4) -> (0,4)
        // In plan space:
        // - "North" is +y (maxY = 4, minY = 0)
        // - "East" is +x (maxX = 4, minX = 0)
        // The 'notch' or narrow tower is in the Northwest (x in [0, 2], y in [2, 4]).
        // The 'wide base' is in the South (x in [0, 4], y in [0, 2]).
        // Door placed on North wall of the wide wing: edge from (4,2) to (2,2), at (3, 2).
        var bounds = DollhouseGeometry.PlanBounds()
        let lPoints = [
            Point(x: 0, y: 0),
            Point(x: 4, y: 0),
            Point(x: 4, y: 2),
            Point(x: 2, y: 2),
            Point(x: 2, y: 4),
            Point(x: 0, y: 4),
        ]
        for p in lPoints { bounds.extend(p) }

        let rect = CGRect(x: 0, y: 0, width: 400, height: 400)
        let projection = PlanProjection(bounds: bounds, in: rect)

        // 1. South vs North:
        // A point in the South (y = 0) vs a point in the North (y = 4).
        let southPoint = Point(x: 2, y: 0)
        let northPoint = Point(x: 1, y: 4)

        // In 3D Dollhouse (default top-down view looking down -z):
        // scenePoint.z for south is -0 = 0.
        // scenePoint.z for north is -4.
        // Looking towards -z, -4 is further away (top of screen), 0 is closer (bottom of screen).
        let southScene = DollhouseGeometry.scenePoint(southPoint, y: 0)
        let northScene = DollhouseGeometry.scenePoint(northPoint, y: 0)
        #expect(northScene.z < southScene.z, "In 3D, North (+y) must map to smaller (more negative) scene z")

        // On the 2D PDF page (UIKit y increases downward):
        // North must have SMALLER page y (top of page).
        // South must have LARGER page y (bottom of page).
        let southPage = projection.point(southPoint)
        let northPage = projection.point(northPoint)
        #expect(northPage.y < southPage.y, "On PDF page, North (+y) must map to top of page (smaller page y)")

        // 2. West vs East:
        // Both 3D and 2D agree that East (+x) maps to right.
        let westPoint = Point(x: 0, y: 1)
        let eastPoint = Point(x: 4, y: 1)
        let westPage = projection.point(westPoint)
        let eastPage = projection.point(eastPoint)
        #expect(eastPage.x > westPage.x, "On PDF page, East (+x) must map to right (larger page x)")

        // 3. Handedness / Chiral check on the L-shape:
        // The narrow wing is at West (x in [0,2]) and North (y in [2,4]).
        // Top-left corner of the L is at (x=0, y=4).
        let topLeftPage = projection.point(Point(x: 0, y: 4))
        let bottomRightPage = projection.point(Point(x: 4, y: 0))
        #expect(topLeftPage.x < bottomRightPage.x)
        #expect(topLeftPage.y < bottomRightPage.y)
    }

    // MARK: - Honesty

    @Test("With no cached routes the plan still prints, and says so instead of faking one")
    func offlineWithoutRoutesStillPrints() throws {
        let document = try Self.document(for: .bungalow, plan: nil)
        #expect(document.hasRoutes == false)

        let output = EscapePlanPDF.render(document)
        #expect(output.pageCount == document.home.floors.count)
        let raster = try Self.rasterisePage(output.data, page: 1)
        #expect(raster.inkFraction > 0.01, "the geometry must still print")

        // Measured inside the plan drawing itself, not the whole sheet: the no-routes page
        // spends its text on an explanation, so page-wide ink proves nothing. Inside the
        // drawing, routes are the only difference — and there must be none without a plan.
        let withRoutes = EscapePlanPDF.render(
            try Self.document(for: .bungalow, plan: try Self.routeSample("bungalow")))
        let withRoutesRaster = try Self.rasterisePage(withRoutes.data, page: 1)

        let withRoutesInk = withRoutesRaster.inkFraction(in: Self.planBand)
        let geometryOnlyInk = raster.inkFraction(in: Self.planBand)
        #expect(withRoutesInk > geometryOnlyInk * 1.2,
                "routes must add real ink inside the drawing: \(withRoutesInk) vs \(geometryOnlyInk)")
    }

    @Test("A single-exit home prints the engine's no-secondary-egress warning")
    func findingsReachThePage() throws {
        let plan = try Self.routeSample("apartment")
        let home = try FixtureLoader.load(.apartment)
        let findings = plan.rooms.flatMap(\.findings)
        #expect(findings.contains { $0.kind == .no_secondary_egress })

        // The sentence the page prints resolves ids to names and quotes the engine verbatim.
        for finding in findings {
            let sentence = RouteNarration.findingSentence(finding, in: home)
            #expect(sentence.contains(finding.detail))
        }
        let output = EscapePlanPDF.render(try Self.document(for: .apartment, plan: plan))
        #expect(output.pageCount == home.floors.count)
    }

    @Test("Route drawing only ever uses waypoints on the page's own floor")
    func floorRunsNeverLeakBetweenPages() throws {
        let plan = try Self.routeSample("twostory")
        for room in plan.rooms {
            guard let route = room.primary else { continue }
            for floorID in ["f1", "f2"] {
                for run in FloorPlanDrawing.floorRuns(of: route, floorID: floorID) {
                    #expect(run.allSatisfy { $0.floor_id == floorID })
                }
            }
        }
    }

    // MARK: - Meeting point

    @Test("The meeting point round-trips through UserDefaults, keyed by home id")
    func meetingPointPersists() throws {
        let suite = "lane-f-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MeetingPointStore(defaults: defaults)

        #expect(store.meetingPoint(forHomeID: "home-a").isEmpty)
        store.setMeetingPoint("  The big oak across the street  ", forHomeID: "home-a")
        #expect(store.meetingPoint(forHomeID: "home-a") == "The big oak across the street")
        #expect(store.meetingPoint(forHomeID: "home-b").isEmpty, "entries are per home")

        // Reading through a fresh store proves it survived, not just that it was cached.
        #expect(MeetingPointStore(defaults: defaults).meetingPoint(forHomeID: "home-a")
                == "The big oak across the street")

        store.setMeetingPoint("   ", forHomeID: "home-a")
        #expect(store.meetingPoint(forHomeID: "home-a").isEmpty)
        #expect(MeetingPointStore.key(homeID: "home-a") == "export.meetingPoint.home-a")
    }

    @Test("A supplied meeting point becomes the last step of every printed route")
    func meetingPointReachesTheSteps() throws {
        let home = try FixtureLoader.load(.twostory)
        let plan = try Self.routeSample("twostory")
        for room in plan.rooms where room.primary != nil {
            let narrative = try #require(RouteNarration.narrate(room: room, in: home, kind: .primary,
                                                                meetingPoint: "the mailbox"))
            #expect(narrative.steps.last?.text.contains("the mailbox") == true)
        }
    }

    // MARK: - File output

    @Test("The exported file is named after the home and holds a readable PDF")
    func exportedFileIsNamedAndReadable() throws {
        #expect(EscapePlanExporter.filename(for: "Willow Street House")
                == "Willow Street House escape plan.pdf")
        #expect(EscapePlanExporter.filename(for: "Mum's/Dad's") == "Mum-s-Dad-s escape plan.pdf")
        #expect(EscapePlanExporter.filename(for: "   ") == "Home escape plan.pdf")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lane-f-\(UUID().uuidString)", isDirectory: true)
        let store = try HomeDocumentStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let home = try FixtureLoader.load(.bungalow)
        try store.save(model: home)

        let exporter = EscapePlanExporter(store: store,
                                          routeCache: nil,
                                          meetingPoints: MeetingPointStore())
        let preview = try exporter.preview(homeID: home.home_id)
        #expect(preview.floorCount == home.floors.count)
        #expect(preview.hasRoutes == false, "no route cache was given, so there are no routes")

        let url = try exporter.writePDF(preview: preview, meetingPoint: "The mailbox")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.lastPathComponent.hasSuffix("escape plan.pdf"))
        let pageCount = try Self.document(Data(contentsOf: url)).numberOfPages
        #expect(pageCount == home.floors.count)
    }

    @Test("Routes come from the offline cache — the exporter cannot reach the network")
    func exporterReadsCachedRoutes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lane-f-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HomeDocumentStore(directory: root.appendingPathComponent("homes"))
        let cache = try RoutePlanCache(directory: root.appendingPathComponent("routes"))

        let fixture = try FixtureLoader.load(.twostory)
        try store.save(model: fixture)
        let home = try store.load(homeID: fixture.home_id, as: HomeModel.self)
        
        let plan = try Self.routeSample("twostory")
        try cache.save(plan, key: RoutePlanKey(homeID: home.home_id),
                       homeFingerprint: RoutePlanCache.fingerprint(of: home),
                       now: Date(timeIntervalSince1970: 1_770_000_000))

        let exporter = EscapePlanExporter(store: store, routeCache: cache,
                                          meetingPoints: MeetingPointStore())
        let preview = try exporter.preview(homeID: home.home_id)
        #expect(preview.hasRoutes)
        #expect(preview.routesComputedAt == Date(timeIntervalSince1970: 1_770_000_000))
        #expect(preview.plan?.rooms.count == plan.rooms.count)
    }
}
