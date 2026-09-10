//
//  ScanExportTests.swift
//  escape_planTests — S1.4
//
//  Unit coverage for the scan export format (the converter-facing contract in
//  backend/app/convert/README.md).
//
//  STATUS: these tests COMPILE but have never been EXECUTED — the dev machine
//  used for S1.4 has the iOS Simulator SDK but no simulator runtime installed,
//  so XCTest cannot run at all here. The equivalent assertions DO run, natively
//  and against the real Python converter, via tools/scan-export-roundtrip/run.sh.
//  First person with a simulator runtime: run these and report anything red.
//

import XCTest
@testable import escape_plan

final class ScanExportTests: XCTestCase {

    // MARK: - Fixtures

    private func surface(_ seed: String,
                         category: RawScanCategory = .wall,
                         confidence: RawScanConfidence = .high) -> FakeExportSurface {
        FakeExportSurface(
            exportIdentifier: UUID(uuidString: "00000000-0000-5000-8000-0000000000\(seed)")!,
            exportTransform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 2.5, 1.25, 0, 1],
            exportDimensions: [5, 2.5, 0],
            exportConfidence: confidence,
            exportCategory: category,
            exportParentIdentifier: nil,
            exportStory: 0
        )
    }

    private func object(_ seed: String,
                        category: String = "sofa",
                        confidence: RawScanConfidence = .high) -> FakeExportObject {
        FakeExportObject(
            exportIdentifier: UUID(uuidString: "00000000-0000-5000-8000-0000000000\(seed)")!,
            exportTransform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 2.5, 1.25, 0, 1],
            exportDimensions: [5, 2.5, 0],
            exportConfidence: confidence,
            exportCategory: category
        )
    }

    // MARK: - Wire format

    /// Swift encodes a case-less enum as `{"high": {}}`; the converter's parser
    /// unwraps exactly that shape. Regressing this silently downgrades every
    /// surface's confidence.
    func testConfidenceEncodesAsSingleKeyObject() throws {
        let data = try RawScanExport.makeEncoder().encode(RawScanConfidence.high)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"high\""), json)
        let decoded = try JSONDecoder().decode(RawScanConfidence.self, from: data)
        XCTAssertEqual(decoded, .high)
    }

    /// The converter also accepts the bare `"high"` form; make sure we can read
    /// back a real export that uses it.
    func testConfidenceDecodesBareString() throws {
        let data = Data("\"medium\"".utf8)
        XCTAssertEqual(try JSONDecoder().decode(RawScanConfidence.self, from: data), .medium)
    }

    func testDoorCategoryCarriesIsOpen() throws {
        let data = try RawScanExport.makeEncoder().encode(RawScanCategory.door(isOpen: true))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("isOpen"), json)
        XCTAssertEqual(try JSONDecoder().decode(RawScanCategory.self, from: data),
                       .door(isOpen: true))
    }

    func testUnknownCategoryRoundTripsAsOther() throws {
        let data = Data("{\"skylight\":{}}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(RawScanCategory.self, from: data),
                       .other("skylight"))
    }

    // MARK: - Builder

    func testExportMatchesConverterTopLevelShape() throws {
        let room = FakeExportRoom(
            exportIdentifier: UUID(uuidString: "00000000-0000-5000-8000-000000000099")!,
            walls: [surface("01")],
            doors: [surface("02", category: .door(isOpen: false))],
            windows: [surface("03", category: .window)],
            objects: [object("04", category: "table")],
            exportSections: [RawScanSection(label: "livingRoom", center: [1, 1, 1])]
        )
        let export = ScanExportBuilder.makeExport(
            from: FakeExportStructure(rooms: [room]),
            mode: .mergedStructure,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(export.version, 3)
        XCTAssertEqual(export.rooms.count, 1)
        XCTAssertEqual(export.rooms[0].walls.count, 1)
        XCTAssertEqual(export.rooms[0].objects.count, 1)
        XCTAssertEqual(export.rooms[0].objects[0].category, "table")
        XCTAssertEqual(export.rooms[0].sections.first?.label, "livingRoom")
        XCTAssertEqual(export.capture?.mode, "mergedStructure")

        // Transform must stay 16 column-major floats: the converter reads the
        // translation at 12/13/14 and cannot detect a wrong layout.
        XCTAssertEqual(export.rooms[0].walls[0].transform.count, 16)
        XCTAssertEqual(export.rooms[0].walls[0].transform[12], 2.5)
    }

    /// Identifiers must be lowercased and passed through untouched — the
    /// converter uuid5-hashes them, so any mutation breaks idempotency.
    func testIdentifiersAreLowercasedAndStable() throws {
        let export = ScanExportBuilder.makeExport(
            from: FakeExportStructure(rooms: [FakeExportRoom(exportIdentifier: nil,
                                                             walls: [surface("01")])]),
            mode: .mergedStructure,
            exportedAt: Date(timeIntervalSince1970: 0)
        )
        let identifier = export.rooms[0].walls[0].identifier
        XCTAssertEqual(identifier, identifier.lowercased())
        XCTAssertNil(export.rooms[0].identifier)
    }

    func testEncodingIsDeterministic() throws {
        let export = ScanExportBuilder.makeExport(
            from: FakeExportStructure(rooms: [FakeExportRoom(exportIdentifier: nil,
                                                             walls: [surface("01")])]),
            mode: .sequentialRooms,
            exportedAt: Date(timeIntervalSince1970: 0),
            fallbackReason: "test"
        )
        XCTAssertEqual(try export.encoded(), try export.encoded())
    }
}

// MARK: - Test doubles
//
// `CapturedRoom` and `CapturedRoom.Surface` have no public initializers, so a
// test can never build one. These conform to the same protocols RoomPlan does —
// that seam is the only reason the export format is testable at all.

struct FakeExportSurface: ScanSurfaceConvertible {
    var exportIdentifier: UUID
    var exportTransform: [Float]
    var exportDimensions: [Float]
    var exportConfidence: RawScanConfidence
    var exportCategory: RawScanCategory
    var exportParentIdentifier: UUID?
    var exportStory: Int?
}

struct FakeExportObject: ScanObjectConvertible {
    var exportIdentifier: UUID
    var exportTransform: [Float]
    var exportDimensions: [Float]
    var exportConfidence: RawScanConfidence
    var exportCategory: String
}

struct FakeExportRoom: ScanRoomConvertible {
    var exportIdentifier: UUID?
    var walls: [FakeExportSurface] = []
    var doors: [FakeExportSurface] = []
    var windows: [FakeExportSurface] = []
    var openings: [FakeExportSurface] = []
    var objects: [FakeExportObject] = []
    var exportSections: [RawScanSection] = []

    var exportWalls: [any ScanSurfaceConvertible] { walls }
    var exportDoors: [any ScanSurfaceConvertible] { doors }
    var exportWindows: [any ScanSurfaceConvertible] { windows }
    var exportOpenings: [any ScanSurfaceConvertible] { openings }
    var exportObjects: [any ScanObjectConvertible] { objects }
}

struct FakeExportStructure: ScanStructureConvertible {
    var rooms: [FakeExportRoom]
    var exportRooms: [any ScanRoomConvertible] { rooms }
}
