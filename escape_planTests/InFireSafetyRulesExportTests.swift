//  InFireSafetyRulesExportTests.swift
//  escape_planTests — A04-04 in-fire safety rules export verification
//
//  Verifies that the printable family escape plan PDF includes the authoritative
//  in-fire life-safety rules on the first page, and that responder snapshots omit them.

import CoreGraphics
import Foundation
import PDFKit
import Testing
import UIKit

@testable import escape_plan

@Suite("In-fire safety rules on escape plan PDF")
struct InFireSafetyRulesExportTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func routeSample(_ name: String) throws -> RoutePlan {
        let url = repoRoot.appendingPathComponent("docs/route-samples/\(name).routeplan.json")
        return try HomeModel.decoder.decode(RoutePlan.self, from: Data(contentsOf: url))
    }

    static func document(for fixture: HomeFixture,
                         plan: RoutePlan?,
                         isResponderSnapshot: Bool = false,
                         meetingPoint: String = "The big oak across the street") throws -> EscapePlanDocument {
        EscapePlanDocument(home: try FixtureLoader.load(fixture),
                           plan: plan,
                           routesComputedAt: plan == nil ? nil : Date(timeIntervalSince1970: 1_770_000_000),
                           meetingPoint: meetingPoint,
                           generatedAt: Date(timeIntervalSince1970: 1_770_000_000),
                           isResponderSnapshot: isResponderSnapshot)
    }

    @Test("Family plan PDF contains 'If there is a fire' rules block on the first page")
    func familyPlanIncludesInFireRulesOnFirstPage() throws {
        let document = try Self.document(for: .bungalow, plan: try Self.routeSample("bungalow"))
        #expect(!document.isResponderSnapshot)

        let output = EscapePlanPDF.render(document)
        #expect(output.pageCount == 1)

        let pdf = try #require(PDFDocument(data: output.data))
        let firstPage = try #require(pdf.page(at: 0))
        let text = try #require(firstPage.string)

        // Title
        #expect(text.contains("IF THERE IS A FIRE"))

        // Rule 1: Feel the door before opening
        #expect(text.contains("Feel the door before opening"))
        #expect(text.contains("backup route"))

        // Rule 2: Stay low
        #expect(text.contains("Stay low"))
        #expect(text.contains("crawl under smoke"))

        // Rule 3: Close doors behind you
        #expect(text.contains("Close doors behind you"))
        #expect(text.contains("slow fire and smoke"))

        // Rule 4: Get out and stay out
        #expect(text.contains("Get out and stay out"))
        #expect(text.contains("never go back inside"))

        // Rule 5 & 6: Outside meeting place and call 911 from outside
        #expect(text.contains("outside meeting place"))
        #expect(text.contains("call 911 from outside"))
    }

    @Test("Responder snapshot PDF does NOT include 'If there is a fire' family rules")
    func responderSnapshotOmitsInFireRules() throws {
        let document = try Self.document(for: .bungalow, plan: try Self.routeSample("bungalow"), isResponderSnapshot: true)
        #expect(document.isResponderSnapshot)

        let output = EscapePlanPDF.render(document)
        let pdf = try #require(PDFDocument(data: output.data))

        for index in 0..<output.pageCount {
            let page = try #require(pdf.page(at: index))
            let text = page.string ?? ""
            #expect(!text.contains("IF THERE IS A FIRE"))
            #expect(!text.contains("Feel the door before opening"))
            #expect(!text.contains("crawl under smoke"))
        }
    }

    @Test("Multi-floor home retains correct page count with rules on first page")
    func multiFloorFamilyPlanPaginatesCorrectly() throws {
        let document = try Self.document(for: .twostory, plan: try Self.routeSample("twostory"))
        let output = EscapePlanPDF.render(document)

        // Two-story house must remain exactly 2 pages (no overflow onto page 3)
        #expect(output.pageCount == document.home.floors.count)

        let pdf = try #require(PDFDocument(data: output.data))
        let firstPageText = try #require(pdf.page(at: 0)?.string)
        #expect(firstPageText.contains("IF THERE IS A FIRE"))

        let secondPageText = try #require(pdf.page(at: 1)?.string)
        #expect(!secondPageText.contains("IF THERE IS A FIRE"))
    }
}
