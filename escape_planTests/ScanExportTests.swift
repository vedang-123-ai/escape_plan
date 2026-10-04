//
//  ScanExportTests.swift
//  escape_planTests — S1.4
//
//  Unit coverage for the scan export format (the converter-facing contract in
//  backend/app/convert/README.md).
//
//  The same format assertions also run natively, against the real Python
//  converter, via tools/scan-export-roundtrip/run.sh. `ScanCleanupTests` at the
//  bottom covers raw-scan deletion (S11.40).
//

import XCTest
@testable import escape_plan

@MainActor
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

// MARK: - Raw scan cleanup (S11.40, AUD-008)

/// Every test works in its own temporary folder through `ScanStore.rootOverride`; none touches
/// the simulator's real Documents.
final class ScanCleanupTests: XCTestCase {

    private var root: URL!
    private var store: ScanStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanCleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ScanStore(rootOverride: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A scan directory with a file in it, the way RoomCaptureController leaves one.
    private func makeScan(_ name: String) throws -> URL {
        let directory = try store.scansDirectory().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("raw.roomplan.json"))
        return directory
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Local wall-clock time, matching how the directory stamp is written.
    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: y, month: mo, day: d, hour: h, minute: mi, second: s)))
    }

    // MARK: After import

    func testDiscardRemovesTheImportedScanAndNothingElse() throws {
        let imported = try store.makeScanDirectory(exportedAt: Date(), scanID: UUID())
        try Data("{}".utf8).write(to: imported.appendingPathComponent("raw.roomplan.json"))
        let other = try makeScan("20260101-000000-0badcafe")

        XCTAssertTrue(store.discardImportedScan(at: imported, keepRawScans: false))
        XCTAssertFalse(exists(imported))
        XCTAssertTrue(exists(other))
        XCTAssertTrue(exists(try store.scansRoot()))
    }

    func testDiscardKeepsTheScanWhenRawScansAreKept() throws {
        let imported = try makeScan("20260101-000000-0badcafe")
        XCTAssertFalse(store.discardImportedScan(at: imported, keepRawScans: true))
        XCTAssertTrue(exists(imported.appendingPathComponent("raw.roomplan.json")))
    }

    /// The delete is fenced to scan-named directories directly inside Scans/.
    func testDiscardRefusesAnythingThatIsNotAScanDirectoryInsideScans() throws {
        let outside = root.appendingPathComponent("20260101-000000-0badcafe", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let wrongName = try makeScan("my-notes")
        let nested = try makeScan("20260101-000000-0badcafe")
            .appendingPathComponent("20260101-000000-00000001", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        XCTAssertFalse(store.discardImportedScan(at: outside, keepRawScans: false))
        XCTAssertFalse(store.discardImportedScan(at: wrongName, keepRawScans: false))
        XCTAssertFalse(store.discardImportedScan(at: nested, keepRawScans: false))
        XCTAssertFalse(store.discardImportedScan(at: try store.scansRoot(), keepRawScans: false))
        XCTAssertTrue(exists(outside))
        XCTAssertTrue(exists(wrongName))
        XCTAssertTrue(exists(nested))
    }

    /// A symlink with a scan-shaped name inside Scans/ is the most dangerous case: following it
    /// would delete whatever it points at. Neither path may touch the link or its target.
    func testSymlinkNamedLikeAScanIsNeverDeleted() throws {
        let target = root.appendingPathComponent("precious", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let keep = target.appendingPathComponent("home.json")
        try Data("{}".utf8).write(to: keep)
        let link = try store.scansDirectory().appendingPathComponent("20250101-000000-ffffffff")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertFalse(store.discardImportedScan(at: link, keepRawScans: false))
        XCTAssertEqual(store.sweepStaleScans(now: try local(2026, 10, 3, 12, 0, 0),
                                             maxAge: ScanRetention.staleAge, keepRawScans: false), [])
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
        XCTAssertTrue(exists(keep))
    }

    // MARK: Launch sweep

    func testExportDateIsReadFromTheDirectoryNameStamp() throws {
        XCTAssertEqual(ScanStore.exportDate(fromDirectoryName: "20260925-131415-abcdef01"),
                       try local(2026, 9, 25, 13, 14, 15))
        XCTAssertNil(ScanStore.exportDate(fromDirectoryName: "20260925-131415-ABCDEF01"))
        XCTAssertNil(ScanStore.exportDate(fromDirectoryName: "20260925-131415-abcdef01x"))
        XCTAssertNil(ScanStore.exportDate(fromDirectoryName: "Scans"))
    }

    /// Now is 2026-10-03 12:00 local; the window is 7 days, so the cut-off is 2026-09-26 12:00.
    /// Margins are two hours so a daylight-saving change in the window cannot flip the answer.
    func testSweepRemovesOnlyScanDirectoriesOlderThanTheWindow() throws {
        let now = try local(2026, 10, 3, 12, 0, 0)
        let stale = try makeScan("20260926-095959-aaaaaaaa")
        let veryStale = try makeScan("20250101-000000-bbbbbbbb")
        let recent = try makeScan("20260926-140000-cccccccc")
        let future = try makeScan("20270101-000000-dddddddd")
        let notAScan = try makeScan("20200101-000000-notahexx")
        let plainFile = try store.scansRoot().appendingPathComponent("20200101-000000-eeeeeeee")
        try Data("x".utf8).write(to: plainFile)

        let removed = store.sweepStaleScans(now: now, maxAge: ScanRetention.staleAge, keepRawScans: false)

        XCTAssertEqual(Set(removed.map(\.lastPathComponent)),
                       ["20260926-095959-aaaaaaaa", "20250101-000000-bbbbbbbb"])
        XCTAssertFalse(exists(stale))
        XCTAssertFalse(exists(veryStale))
        XCTAssertTrue(exists(recent))
        XCTAssertTrue(exists(future))
        XCTAssertTrue(exists(notAScan))
        XCTAssertTrue(exists(plainFile))
    }

    func testSweepKeepsEverythingWhenRawScansAreKept() throws {
        let stale = try makeScan("20250101-000000-bbbbbbbb")
        let removed = store.sweepStaleScans(now: try local(2026, 10, 3, 12, 0, 0),
                                            maxAge: ScanRetention.staleAge, keepRawScans: true)
        XCTAssertEqual(removed, [])
        XCTAssertTrue(exists(stale))
    }

    func testSweepWithNoScansFolderDoesNotCreateOne() throws {
        let removed = store.sweepStaleScans(now: Date(), maxAge: ScanRetention.staleAge, keepRawScans: false)
        XCTAssertEqual(removed, [])
        XCTAssertFalse(exists(try store.scansRoot()))
    }

    // MARK: Debug setting

    /// Tests run in Debug, where scans are kept unless the switch is set to false. (Release
    /// always returns false; that branch is compiled out of a Debug test build.)
    func testDebugKeepsRawScansUnlessTheSwitchIsOff() throws {
        let suite = "ScanCleanupTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

#if DEBUG
        XCTAssertTrue(ScanRetention.keepsRawScans(defaults: defaults))
        defaults.set(false, forKey: ScanRetention.keepRawScansKey)
        XCTAssertFalse(ScanRetention.keepsRawScans(defaults: defaults))
#else
        defaults.set(true, forKey: ScanRetention.keepRawScansKey)
        XCTAssertFalse(ScanRetention.keepsRawScans(defaults: defaults))
#endif
    }
}
