//
//  PersistenceTests.swift
//  escape_planTests — S2.4 acceptance
//

import XCTest
@testable import escape_plan

/// Test homes come from `schema/fixtures/` (the project-wide test bed) read off
/// the host filesystem via `#filePath` — never a copy in the test bundle, which
/// would drift from the fixtures every other lane tests against.
enum PersistenceFixtures {
    /// The checkout root. Derived from this file's own path, unless
    /// `ESCAPE_PLAN_REPO_ROOT` overrides it — which it must when the tests are
    /// compiled somewhere other than in place (see
    /// `scripts/verify_export_validates.sh`, which runs them via SwiftPM).
    static let repoRoot: URL = {
        if let path = ProcessInfo.processInfo.environment["ESCAPE_PLAN_REPO_ROOT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // escape_planTests/
            .deletingLastPathComponent()   // repo root
    }()

    static func url(_ name: String) -> URL {
        repoRoot.appendingPathComponent("schema/fixtures/\(name).json")
    }

    static func document(_ name: String) throws -> HomeDocument {
        try HomeDocument(data: Data(contentsOf: url(name)))
    }
}

final class PersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("s24-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> HomeDocumentStore {
        try HomeDocumentStore(directory: directory)
    }

    // MARK: - Acceptance: kill and relaunch → everything persists

    /// A store instance is per-launch state; a fresh instance over the same
    /// directory is what the app sees after a cold start.
    func testDocumentSurvivesRelaunchByteForByte() throws {
        let original = try PersistenceFixtures.document("bungalow")
        let homeID = try XCTUnwrap(original.homeID)
        try makeStore().save(original)

        // Simulate termination + relaunch: nothing in memory carries over.
        let reloaded = try makeStore().load(homeID: homeID)

        XCTAssertEqual(reloaded.name, original.name)
        XCTAssertEqual(reloaded.floorCount, original.floorCount)
        XCTAssertEqual(reloaded.roomCount, original.roomCount)
        XCTAssertEqual(reloaded.schemaVersion, original.schemaVersion)
        // The whole tree, not just the fields this layer knows about —
        // meta.modified is restamped on save, so compare everything else.
        XCTAssertEqual(
            reloaded.body.setting("meta", to: .null),
            original.body.setting("meta", to: .null)
        )
    }

    func testEveryFixtureRoundTripsLosslessly() throws {
        for name in ["bungalow", "apartment", "twostory"] {
            let original = try PersistenceFixtures.document(name)
            let store = try HomeDocumentStore(
                directory: directory.appendingPathComponent(name)
            )
            try store.save(original)
            let reloaded = try store.load(homeID: XCTUnwrap(original.homeID))
            XCTAssertEqual(
                reloaded.body.setting("meta", to: .null),
                original.body.setting("meta", to: .null),
                "\(name) did not survive a save/load round trip"
            )
        }
    }

    // MARK: - Acceptance: two saved homes coexist

    func testTwoHomesCoexistAndAreIndependent() throws {
        let bungalow = try PersistenceFixtures.document("bungalow")
        let apartment = try PersistenceFixtures.document("apartment")
        let store = try makeStore()
        try store.save(bungalow)
        try store.save(apartment)

        let listed = try makeStore().list()
        XCTAssertEqual(Set(listed.map(\.id)),
                       [try XCTUnwrap(bungalow.homeID), try XCTUnwrap(apartment.homeID)])
        XCTAssertEqual(Set(listed.map(\.name)),
                       [try XCTUnwrap(bungalow.name), try XCTUnwrap(apartment.name)])

        // Deleting one leaves the other untouched.
        try store.delete(homeID: XCTUnwrap(bungalow.homeID))
        let remaining = try makeStore().list()
        XCTAssertEqual(remaining.map(\.id), [try XCTUnwrap(apartment.homeID)])
        XCTAssertNoThrow(try makeStore().load(homeID: XCTUnwrap(apartment.homeID)))
    }

    func testListReportsNameFloorsRoomsAndModified() throws {
        let twostory = try PersistenceFixtures.document("twostory")
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        try makeStore().save(twostory, now: now)

        let row = try XCTUnwrap(makeStore().list().first)
        XCTAssertEqual(row.name, twostory.name)
        XCTAssertEqual(row.floorCount, 2)
        XCTAssertGreaterThan(row.roomCount, 0)
        // Stored to the second — the schema's date-time has no sub-second part.
        XCTAssertEqual(row.modified.timeIntervalSince1970,
                       now.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    func testListSkipsUnreadableFilesInsteadOfFailing() throws {
        let store = try makeStore()
        try store.save(try PersistenceFixtures.document("bungalow"))
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("garbage.homeplan.json")
        )

        XCTAssertEqual(store.list().count, 1)
    }

    // MARK: - Acceptance: duplicate gets a fresh id

    func testDuplicateGetsFreshIDAndIsIndependent() throws {
        let original = try PersistenceFixtures.document("bungalow")
        let originalID = try XCTUnwrap(original.homeID)
        let store = try makeStore()
        try store.save(original)

        let copy = try store.duplicate(homeID: originalID)

        XCTAssertNotEqual(copy.id, originalID)
        XCTAssertNotNil(UUID(uuidString: copy.id), "copy id must be a UUID (schema: format uuid)")
        XCTAssertEqual(copy.name, "Bungalow copy")
        XCTAssertEqual(copy.floorCount, original.floorCount)
        XCTAssertEqual(copy.roomCount, original.roomCount)
        XCTAssertEqual(store.list().count, 2)

        // The copy's own body carries the new id — not just the summary row.
        let loadedCopy = try store.load(homeID: copy.id)
        XCTAssertEqual(loadedCopy.homeID, copy.id)

        // Deleting the copy leaves the original intact.
        try store.delete(homeID: copy.id)
        XCTAssertEqual(try store.load(homeID: originalID).homeID, originalID)
    }

    func testDuplicateOfDuplicateGetsAnotherFreshID() throws {
        let original = try PersistenceFixtures.document("bungalow")
        let store = try makeStore()
        try store.save(original)
        let first = try store.duplicate(homeID: XCTUnwrap(original.homeID))
        let second = try store.duplicate(homeID: first.id)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(store.list().count, 3)
    }

    // MARK: - Acceptance: export validates against the schema

    /// Writes the exported file to a host path so the S0.2 validator CLI can be
    /// run over it. The schema check itself is the second half of this test and
    /// lives in `scripts/verify_export_validates.sh` — `python3 -m app.validate`
    /// can't run inside the simulator.
    func testExportProducesTheStoredDocumentAtAHostVisiblePath() throws {
        let original = try PersistenceFixtures.document("bungalow")
        let store = try makeStore()
        try store.save(original)

        let exported = try store.export(homeID: XCTUnwrap(original.homeID),
                                        to: Self.exportArtifactDirectory)

        XCTAssertEqual(exported.lastPathComponent, "Bungalow.json")
        let exportedDocument = try HomeDocument(data: Data(contentsOf: exported))
        XCTAssertEqual(exportedDocument.body,
                       try store.load(homeID: XCTUnwrap(original.homeID)).body)
        XCTAssertEqual(exportedDocument.schemaVersion, SchemaMigrator.currentVersion)
        XCTAssertEqual(
            exportedDocument.body.setting("meta", to: .null),
            original.body.setting("meta", to: .null)
        )
    }

    /// Set by `scripts/verify_export_validates.sh`; defaults to the repo's
    /// build artifacts dir so a plain `xcodebuild test` still produces the file.
    static var exportArtifactDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["EXPORT_ARTIFACT_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return PersistenceFixtures.repoRoot.appendingPathComponent(".build/s24-exports", isDirectory: true)
    }

    func testImportedExportGetsAFreshIDAndDoesNotClobber() throws {
        let original = try PersistenceFixtures.document("bungalow")
        let store = try makeStore()
        try store.save(original)
        let exported = try store.export(homeID: XCTUnwrap(original.homeID),
                                        to: directory.appendingPathComponent("exports"))

        let imported = try store.importDocument(from: exported)

        XCTAssertNotEqual(imported.id, try XCTUnwrap(original.homeID))
        XCTAssertEqual(store.list().count, 2)
        XCTAssertEqual(try store.load(homeID: XCTUnwrap(original.homeID)).name, "Bungalow")
    }

    // MARK: - Schema version / migration

    func testLoadRefusesADocumentFromANewerBuild() throws {
        let future = try XCTUnwrap(
            PersistenceFixtures.document("bungalow").body.setting("schema_version", to: .string("2.0"))
        )
        let document = HomeDocument(body: future)
        let homeID = try XCTUnwrap(document.homeID)
        // Write it directly — save() would be a legitimate refusal too, but the
        // case we care about is a file left by a newer build of the app.
        try document.serialized().write(to: try makeStore().url(for: homeID))

        XCTAssertThrowsError(try makeStore().load(homeID: homeID)) { error in
            XCTAssertEqual(
                error as? PersistenceError,
                .documentTooNew(documentVersion: "2.0", supportedVersion: "1.1")
            )
        }
        // Refused gracefully: the file is still there, unmodified, and the rest
        // of the library still lists.
        XCTAssertTrue(makeStoreUnchecked().exists(homeID: homeID))
    }

    func testMigrationHookRefusesAnUnknownOlderVersion() throws {
        // No 0.x documents exist in the wild (1.0 is the first version), so this
        // asserts the hook's contract rather than a real upgrade.
        let old = try XCTUnwrap(
            PersistenceFixtures.document("bungalow").body.setting("schema_version", to: .string("0.9"))
        )
        XCTAssertThrowsError(try SchemaMigrator.migrate(HomeDocument(body: old))) { error in
            XCTAssertEqual(
                error as? PersistenceError,
                .migrationUnavailable(fromVersion: "0.9", toVersion: "1.1")
            )
        }
    }

    func testMigrationUpgradesAOneOhDocumentToCurrentAndItDecodes() throws {
        // The real upgrade path: every pre-revamp home on disk is a 1.0 document.
        // 1.0 → 1.1 only re-stamps the version (floor.objects defaults to []).
        let old = try XCTUnwrap(
            PersistenceFixtures.document("bungalow").body.setting("schema_version", to: .string("1.0"))
        )
        let migrated = try SchemaMigrator.migrate(HomeDocument(body: old))
        XCTAssertEqual(migrated.schemaVersion, SchemaMigrator.currentVersion)
        let model = try migrated.decode(as: HomeModel.self)
        XCTAssertEqual(model.schema_version, "1.1")
        XCTAssertTrue(model.floors.allSatisfy { $0.objects.isEmpty },
                      "a migrated 1.0 document has no objects yet")
    }

    func testCurrentVersionMatchesTheSchemaContract() throws {
        let schema = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(contentsOf: PersistenceFixtures.repoRoot
                .appendingPathComponent("schema/homemodel.schema.json"))
        )
        XCTAssertEqual(
            schema["properties"]?["schema_version"]?["const"]?.stringValue,
            SchemaMigrator.currentVersion,
            "SchemaMigrator.currentVersion has drifted from the schema"
        )
    }

    func testVersionComparisonIsNumericNotLexicographic() {
        XCTAssertEqual(SchemaMigrator.compare("1.10", "1.2"), .orderedDescending)
        XCTAssertEqual(SchemaMigrator.compare("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(SchemaMigrator.compare("0.9", "1.0"), .orderedAscending)
    }

    func testSaveRejectsADocumentWithoutSchemaVersionOrHomeID() throws {
        let store = try makeStore()
        let noVersion = try XCTUnwrap(
            PersistenceFixtures.document("bungalow").body.objectValue.map { object -> JSONValue in
                var copy = object
                copy["schema_version"] = nil
                return .object(copy)
            }
        )
        XCTAssertThrowsError(try store.save(HomeDocument(body: noVersion))) {
            XCTAssertEqual($0 as? PersistenceError, .missingSchemaVersion)
        }

        let noID = try XCTUnwrap(
            PersistenceFixtures.document("bungalow").body.objectValue.map { object -> JSONValue in
                var copy = object
                copy["home_id"] = nil
                return .object(copy)
            }
        )
        XCTAssertThrowsError(try store.save(HomeDocument(body: noID))) {
            XCTAssertEqual($0 as? PersistenceError, .missingHomeID)
        }
    }

    func testLoadAndDeleteOfAnUnknownHomeThrow() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.load(homeID: "nope")) {
            XCTAssertEqual($0 as? PersistenceError, .homeNotFound(homeID: "nope"))
        }
        XCTAssertThrowsError(try store.delete(homeID: "nope")) {
            XCTAssertEqual($0 as? PersistenceError, .homeNotFound(homeID: "nope"))
        }
    }

    // MARK: - Codable HomeModel entry points (S2.1 seam)

    /// Stands in for S2.1's `HomeModel` until it lands: any Codable type the
    /// store round-trips proves the generic save/load path works.
    private struct StubHomeModel: Codable, Equatable {
        let schema_version: String
        let home_id: String
        let name: String
        let floors: [String]
    }

    func testGenericSaveAndLoadOfACodableModel() throws {
        let model = StubHomeModel(
            schema_version: SchemaMigrator.currentVersion,
            home_id: UUID().uuidString.lowercased(),
            name: "Stub",
            floors: ["ground"]
        )
        let store = try makeStore()
        try store.save(model: model)

        let reloaded = try makeStore().load(homeID: model.home_id, as: StubHomeModel.self)
        XCTAssertEqual(reloaded, model)
    }

    // MARK: - Anonymous device id

    func testDeviceIDIsStableAcrossLaunchesAndIsAUUID() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "s24-\(UUID().uuidString)"))
        DeviceIdentity.reset(defaults: defaults)

        let first = DeviceIdentity.current(defaults: defaults)
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(DeviceIdentity.current(defaults: defaults), first)

        DeviceIdentity.reset(defaults: defaults)
        XCTAssertNotEqual(DeviceIdentity.current(defaults: defaults), first)
    }

    // MARK: - Helpers

    private func makeStoreUnchecked() -> HomeDocumentStore {
        try! HomeDocumentStore(directory: directory)
    }
}
