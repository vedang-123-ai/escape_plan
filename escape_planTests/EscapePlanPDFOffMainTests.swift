import CoreGraphics
import Foundation
import XCTest
@testable import escape_plan

final class EscapePlanPDFOffMainTests: XCTestCase {

    private func makeTestDocument() throws -> EscapePlanDocument {
        let home = try FixtureLoader.load(.twostory)
        return EscapePlanDocument(
            home: home,
            plan: nil,
            routesComputedAt: nil,
            meetingPoint: "Under the large oak tree across the street",
            generatedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
    }

    func testRenderAsyncProducesValidPDFOffMainActor() async throws {
        let doc = try makeTestDocument()

        let output = await EscapePlanPDF.renderAsync(doc)

        XCTAssertGreaterThan(output.pageCount, 0, "PDF should produce at least one page")
        XCTAssertGreaterThan(output.data.count, 1024, "PDF output data should be non-empty and substantial")

        // Verify PDF magic header bytes "%PDF-"
        let header = String(decoding: output.data.prefix(5), as: UTF8.self)
        XCTAssertEqual(header, "%PDF-", "Generated document must begin with PDF magic header")
    }

    func testRenderOffMainActorInDetachedTask() async throws {
        let doc = try makeTestDocument()

        let output = try await Task.detached(priority: .userInitiated) {
            XCTAssertFalse(Thread.isMainThread, "Execution must take place off the main thread")
            return EscapePlanPDF.render(doc)
        }.value

        XCTAssertGreaterThan(output.pageCount, 0)
        XCTAssertGreaterThan(output.data.count, 1024)
        let header = String(decoding: output.data.prefix(5), as: UTF8.self)
        XCTAssertEqual(header, "%PDF-")
    }

    func testConcurrentOffMainActorPDFRendering() async throws {
        let doc = try makeTestDocument()

        async let r1 = Task.detached(priority: .userInitiated) { EscapePlanPDF.render(doc) }.value
        async let r2 = Task.detached(priority: .userInitiated) { EscapePlanPDF.render(doc) }.value
        async let r3 = Task.detached(priority: .userInitiated) { EscapePlanPDF.render(doc) }.value
        async let r4 = Task.detached(priority: .userInitiated) { EscapePlanPDF.render(doc) }.value

        let (out1, out2, out3, out4) = await (try r1, try r2, try r3, try r4)

        XCTAssertEqual(out1.pageCount, out2.pageCount)
        XCTAssertEqual(out2.pageCount, out3.pageCount)
        XCTAssertEqual(out3.pageCount, out4.pageCount)
        XCTAssertGreaterThan(out1.data.count, 1024)
    }
}
