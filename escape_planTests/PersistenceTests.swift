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

    // MARK: - S11.48: light summary decode, incremental refresh, seeding notice

    /// What `list()` produced before S11.48: a row from the FULL `HomeDocument` decode. The light
    /// decode must match it for any file, so this is kept here as the reference.
    private func referenceSummary(of data: Data, id: String, fallback: Date?) -> HomeSummary? {
        guard let document = try? HomeDocument(data: data),
              let embedded = document.homeID,
              embedded.caseInsensitiveCompare(id) == .orderedSame
        else { return nil }
        return HomeSummary(id: id, name: document.name ?? "Untitled Home",
                           floorCount: document.floorCount, roomCount: document.roomCount,
                           modified: document.modified ?? fallback ?? .distantPast)
    }

    private func writeRaw(_ json: String, id: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent("\(id).homeplan.json"))
    }

    func testLightSummaryMatchesFullDecodeForEveryFixture() throws {
        let fixtureDirectory = PersistenceFixtures.repoRoot.appendingPathComponent("schema/fixtures")
        let files = try FileManager.default.contentsOfDirectory(at: fixtureDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 5)
        var expected: [HomeSummary] = []
        for file in files {
            let data = try Data(contentsOf: file)
            let id = try XCTUnwrap(HomeDocument(data: data).homeID, file.lastPathComponent)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("\(id).homeplan.json")
            try data.write(to: target)
            let stamp = try XCTUnwrap(target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            expected.append(try XCTUnwrap(referenceSummary(of: data, id: id, fallback: stamp), file.lastPathComponent))
        }
        let listed = try makeStore().list()
        XCTAssertEqual(Set(listed.map(\.id)), Set(expected.map(\.id)))
        for row in listed {
            XCTAssertEqual(row, expected.first { $0.id == row.id }, row.id)
        }
        XCTAssertEqual(listed.map(\.modified), listed.map(\.modified).sorted(by: >), "newest first")
        // A fixture with rooms, so a decoder that returned zeros could not pass.
        XCTAssertTrue(listed.contains { $0.roomCount > 0 && $0.floorCount > 0 })
    }

    func testLightSummaryMatchesFullDecodeOnOddShapes() throws {
        let cases: [String: String] = [
            // wrong types read as absent, exactly as HomeDocument's accessors do
            "odd-name-number": #"{"home_id":"odd-name-number","name":42,"floors":[{"rooms":[{},{}]},{"rooms":"x"},7],"meta":{"modified":"2026-07-10T12:00:00Z"}}"#,
            "odd-floors-object": #"{"home_id":"odd-floors-object","name":"A","floors":{"rooms":[1]},"meta":{"modified":"2026-07-10T12:00:00.250Z"}}"#,
            "odd-meta-bad-date": #"{"home_id":"odd-meta-bad-date","floors":[],"meta":{"modified":"yesterday"}}"#,
            "odd-no-meta": #"{"home_id":"odd-no-meta","name":"B","floors":[{"rooms":[null]}]}"#,
            "odd-meta-string": #"{"home_id":"odd-meta-string","name":"C","meta":"nope"}"#,
            "ODD-case": #"{"home_id":"odd-case","name":"D"}"#,
            "odd-mismatch": #"{"home_id":"someone-else","name":"E"}"#,
            "odd-no-id": #"{"name":"F"}"#,
            "odd-array-root": "[1,2,3]",
        ]
        for (id, json) in cases { try writeRaw(json, id: id) }
        let store = try makeStore()
        let listed = Dictionary(uniqueKeysWithValues: store.list().map { ($0.id, $0) })
        for (id, json) in cases {
            let url = directory.appendingPathComponent("\(id).homeplan.json")
            let stamp = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let expected = referenceSummary(of: Data(json.utf8), id: id, fallback: stamp)
            XCTAssertEqual(listed[id], expected, id)
        }
        XCTAssertNotNil(listed["odd-name-number"])
        XCTAssertEqual(listed["odd-name-number"]?.roomCount, 2)
        XCTAssertNil(listed["odd-mismatch"])
    }

    func testRefreshRereadsOnlyTheFileThatChanged() throws {
        let store = try makeStore()
        let base = try PersistenceFixtures.document("bungalow")
        let firstID = try store.save(base).id
        var others: [String] = []
        for _ in 0..<4 { others.append(try store.duplicate(homeID: firstID).id) }

        var listing = store.summaries(reusing: [:])
        XCTAssertEqual(listing.summaries.count, 5)
        XCTAssertEqual(listing.filesRead, 5)

        let unchanged = store.summaries(reusing: listing.entries)
        XCTAssertEqual(unchanged.filesRead, 0, "nothing changed, nothing re-read")
        XCTAssertEqual(unchanged.summaries, listing.summaries)

        // An editor autosave: one home gets a new name.
        let target = others[2]
        let edited = try store.load(homeID: target).reidentified(
            homeID: target, name: "Renamed by autosave", modified: Date().addingTimeInterval(60))
        try store.save(edited, now: Date().addingTimeInterval(60))

        listing = store.summaries(reusing: listing.entries)
        XCTAssertEqual(listing.filesRead, 1, "only the saved home is read again")
        XCTAssertEqual(listing.summaries.first?.id, target, "newest first after the save")
        XCTAssertEqual(listing.summaries.first?.name, "Renamed by autosave")
        XCTAssertEqual(listing.summaries.count, 5)
        XCTAssertEqual(listing.summaries, store.list(), "incremental result equals a cold listing")
    }

    func testCacheIsKeyedOnBothChangeTimeAndSize() throws {
        let store = try makeStore()
        let id = try store.save(try PersistenceFixtures.document("bungalow")).id
        let url = store.url(for: id)
        let known = store.summaries(reusing: [:]).entries
        let original = try Data(contentsOf: url)
        let stamp = try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        // Same size, later change time (a same-length rename): must be read again.
        let sameSize = try XCTUnwrap(String(data: original, encoding: .utf8)?
            .replacingOccurrences(of: "\"name\" : \"Bungalow\"", with: "\"name\" : \"Bungalaw\""))
        XCTAssertEqual(sameSize.utf8.count, original.count)
        try Data(sameSize.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: stamp.addingTimeInterval(5)], ofItemAtPath: url.path)
        var listing = store.summaries(reusing: known)
        XCTAssertEqual(listing.filesRead, 1)
        XCTAssertEqual(listing.summaries.first?.name, "Bungalaw")

        // Different size, SAME change time: must be read again.
        let longer = sameSize.replacingOccurrences(of: "Bungalaw", with: "Bungalaw Extended")
        let before = listing.entries
        try Data(longer.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: stamp.addingTimeInterval(5)], ofItemAtPath: url.path)
        listing = store.summaries(reusing: before)
        XCTAssertEqual(listing.filesRead, 1)
        XCTAssertEqual(listing.summaries.first?.name, "Bungalaw Extended")
    }

    func testAFileThatCannotBeReadIsRetriedNotRemembered() throws {
        let store = try makeStore()
        let id = try store.save(try PersistenceFixtures.document("bungalow")).id
        let url = store.url(for: id)
        let good = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        guard (try? Data(contentsOf: url)) == nil else {
            throw XCTSkip("this environment ignores file permissions (root)")
        }
        let unreadable = store.summaries(reusing: [:])
        XCTAssertTrue(unreadable.summaries.isEmpty)
        XCTAssertNil(unreadable.entries[id], "an unreadable file is not cached as skipped")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(try Data(contentsOf: url), good)
        XCTAssertEqual(store.summaries(reusing: unreadable.entries).summaries.map(\.id), [id])
    }

    func testRefreshDropsADeletedHomeAndNeverResurrectsIt() throws {
        let store = try makeStore()
        let id = try store.save(try PersistenceFixtures.document("bungalow")).id
        let copy = try store.duplicate(homeID: id).id
        let before = store.summaries(reusing: [:])
        try store.delete(homeID: copy)
        let after = store.summaries(reusing: before.entries)
        XCTAssertEqual(after.summaries.map(\.id), [id])
        XCTAssertNil(after.entries[copy])
        XCTAssertEqual(after.filesRead, 0)
    }

    @MainActor
    func testLibraryRefreshAfterASaveShowsTheChangeImmediately() throws {
        let store = try makeStore()
        let id = try store.save(try PersistenceFixtures.document("bungalow")).id
        let library = HomeLibrary(store: store)
        XCTAssertEqual(library.homes.map(\.id), [id])

        let copy = try store.duplicate(homeID: id, newName: "Fresh copy", now: Date().addingTimeInterval(120))
        library.refresh()
        XCTAssertEqual(Set(library.homes.map(\.id)), [id, copy.id])
        XCTAssertEqual(library.homes.first?.name, "Fresh copy")

        XCTAssertTrue(library.delete(homeID: copy.id))
        XCTAssertEqual(library.homes.map(\.id), [id], "a delete shows at once and stays deleted")
        XCTAssertNotNil(library.duplicate(homeID: id))
        XCTAssertEqual(library.homes.count, 2)
    }

    func testSeedingFailureNoticeIsShownOnceAndExplainsItself() throws {
        let suite = "s11-48-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        struct Boom: Error {}

        let first = StarterSeedingNotice.noticeToShow(for: Boom(), defaults: defaults)
        XCTAssertEqual(first, StarterSeedingNotice.message)
        XCTAssertTrue(first?.contains("couldn't be set up") ?? false)
        XCTAssertEqual(StarterSeedingNotice.noticeToShow(for: Boom(), defaults: defaults), first,
                       "not recorded until the alert is dismissed: a kill before then re-tells it")
        StarterSeedingNotice.markShown(defaults: defaults)
        XCTAssertNil(StarterSeedingNotice.noticeToShow(for: Boom(), defaults: defaults),
                     "a failure that repeats every launch is not announced every launch")
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
            PersistenceFixtures.document("bungalow").body.setting("schema_version", to: .string("3.0"))
        )
        let document = HomeDocument(body: future)
        let homeID = try XCTUnwrap(document.homeID)
        // Write it directly — save() would be a legitimate refusal too, but the
        // case we care about is a file left by a newer build of the app.
        try document.serialized().write(to: try makeStore().url(for: homeID))

        XCTAssertThrowsError(try makeStore().load(homeID: homeID)) { error in
            XCTAssertEqual(
                error as? PersistenceError,
                .documentTooNew(documentVersion: "3.0",
                                supportedVersion: SchemaMigrator.currentVersion)
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
                .migrationUnavailable(fromVersion: "0.9",
                                      toVersion: SchemaMigrator.currentVersion)
            )
        }
    }

    func testMigrationUpgradesAOneOhDocumentToCurrentAndItDecodes() throws {
        // The real upgrade path: every pre-revamp home on disk is a 1.0 document.
        // It now chains 1.0 → 1.1 → 2.0; both steps only re-stamp the version, because
        // every field either half added is optional with a decoder-side default.
        let old = try XCTUnwrap(
            PersistenceFixtures.document("bungalow").body.setting("schema_version", to: .string("1.0"))
        )
        let migrated = try SchemaMigrator.migrate(HomeDocument(body: old))
        XCTAssertEqual(migrated.schemaVersion, SchemaMigrator.currentVersion)
        let model = try migrated.decode(as: HomeModel.self)
        XCTAssertEqual(model.schema_version, SchemaMigrator.currentVersion)
        XCTAssertTrue(model.floors.allSatisfy { $0.objects.isEmpty },
                      "a migrated 1.0 document has no objects yet")
    }

    func testTheTwoCurrentVersionConstantsAgree() {
        // ModelSupport.currentSchemaVersion (what the editor stamps on new homes) and
        // SchemaMigrator.currentVersion (what the loader will accept) are separate literals
        // that must be bumped together. If they drift, EditorValidation rejects every home
        // the migrator just successfully upgraded — a total editor outage. Only the migrator's
        // half was pinned to the schema before S6.1.
        XCTAssertEqual(HomeModel.currentSchemaVersion, SchemaMigrator.currentVersion)
    }

    func testCurrentVersionMatchesTheSchemaContract() throws {
        let schema = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(contentsOf: PersistenceFixtures.repoRoot
                .appendingPathComponent("schema/homemodel.schema.json"))
        )
        let versions = schema["properties"]?["schema_version"]?["enum"]?
            .arrayValue?.compactMap({ $0.stringValue }) ?? []
        XCTAssertFalse(versions.isEmpty, "the schema no longer enumerates schema_version")

        // Membership is NOT enough, and used to be all this asserted. S7.1 widened the
        // enum from ["1.1","2.0"] to every version the migrators accept, at which point
        // `contains` would have passed with currentVersion reverted to any of the four —
        // the one test named for catching that drift could no longer catch it. The
        // current version must be the NEWEST version the contract knows about.
        let newest = versions.max { SchemaMigrator.compare($0, $1) == .orderedAscending }
        XCTAssertEqual(
            SchemaMigrator.currentVersion, newest,
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

    // MARK: - Home ids are file names, so they are checked (S11.41, AUD-012)

    /// A sibling of the Homes directory: where `../<name>` would land if an id were not checked.
    private func outside(_ name: String) -> URL {
        directory.deletingLastPathComponent()
            .appendingPathComponent("\(name).\(HomeDocumentStore.fileExtension)")
    }

    private func bungalow(id: String) throws -> HomeDocument {
        try PersistenceFixtures.document("bungalow")
            .reidentified(homeID: id, name: "Bungalow", modified: Date(timeIntervalSince1970: 1_780_000_000))
    }

    func testSaveRefusesATraversalIDAndWritesNothingOutsideTheDirectory() throws {
        let store = try makeStore()
        let escapee = "s1141-save-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: outside(escapee)) }

        XCTAssertThrowsError(try store.save(bungalow(id: "../\(escapee)"))) {
            XCTAssertEqual($0 as? InvalidHomeID, InvalidHomeID(homeID: "../\(escapee)"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(escapee).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    /// Delete reads its id from a file (S11.21's "Your homes" row), so it is checked too. Without
    /// the check, this deletes a file outside the Homes directory.
    func testDeleteRefusesATraversalIDAndLeavesTheFileOutsideAlone() throws {
        let store = try makeStore()
        let victim = "s1141-delete-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: outside(victim)) }
        try Data("keep me".utf8).write(to: outside(victim))

        XCTAssertThrowsError(try store.delete(homeID: "../\(victim)")) {
            XCTAssertEqual($0 as? InvalidHomeID, InvalidHomeID(homeID: "../\(victim)"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside(victim).path))
    }

    func testLoadAndExistsRefuseATraversalIDEvenWhenTheFileIsThere() throws {
        let store = try makeStore()
        let target = "s1141-load-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: outside(target)) }
        try bungalow(id: target).serialized().write(to: outside(target))

        XCTAssertThrowsError(try store.load(homeID: "../\(target)")) {
            XCTAssertEqual($0 as? InvalidHomeID, InvalidHomeID(homeID: "../\(target)"))
        }
        XCTAssertFalse(store.exists(homeID: "../\(target)"))
        // The non-throwing path stays inside the directory too.
        XCTAssertEqual(store.url(for: "../\(target)").deletingLastPathComponent().standardizedFileURL,
                       directory.standardizedFileURL)
    }

    /// Import never uses the file's own id, so a hostile one cannot become a path.
    func testImportOfAFileWithATraversalIDStoresItUnderAFreshValidID() throws {
        let store = try makeStore()
        let escapee = "s1141-import-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: outside(escapee)) }
        let source = directory.deletingLastPathComponent()
            .appendingPathComponent("s1141-import-src-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: source) }
        try bungalow(id: "../\(escapee)").serialized().write(to: source)

        let imported = try store.importDocument(from: source)

        XCTAssertTrue(HomeID.isValid(imported.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(escapee).path))
        XCTAssertEqual(store.list().map(\.id), [imported.id])
    }

    /// Existing homes must keep loading: every id format in use today saves, lists and opens.
    func testEveryCurrentIDFormatSavesListsAndLoads() throws {
        let store = try makeStore()
        let ids = [
            UUID().uuidString.lowercased(),
            UUID().uuidString,                  // HouseScreen.blankHome
            "TEST-DEMO-HOME-1234",
            "9a5e6d34-2c3f-4a1b-8d70-empty-123",
            "preserved-\(UUID().uuidString.lowercased())-1",
            "home-1",
        ]
        for id in ids { try store.save(bungalow(id: id)) }

        XCTAssertEqual(Set(store.list().map(\.id)), Set(ids))
        for id in ids {
            XCTAssertEqual(try store.load(homeID: id).homeID, id)
            XCTAssertTrue(store.exists(homeID: id), id)
        }
    }

    /// A file renamed (or hand-edited) so its name and its `home_id` disagree used to be listed
    /// under the embedded id, which `load` then could not find.
    func testAFileWhoseNameAndIDDisagreeIsNotListed() throws {
        let store = try makeStore()
        let good = try bungalow(id: "real-home")
        try store.save(good)
        try good.serialized().write(to: store.url(for: "renamed-in-files"))

        let listed = store.list()
        XCTAssertEqual(listed.map(\.id), ["real-home"])
        for row in listed { XCTAssertNoThrow(try store.load(homeID: row.id), row.id) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: "renamed-in-files").path),
                      "a skipped file is left alone, not deleted")
    }

    /// A name that differs from the embedded id only in letter case is the same file on a
    /// case-insensitive volume, so it is listed, under the name `load` opens.
    func testAFileWhoseNameDiffersOnlyInCaseIsListedAndOpens() throws {
        let store = try makeStore()
        try bungalow(id: "ABC-HOME").serialized().write(to: store.url(for: "abc-home"))

        XCTAssertEqual(store.list().map(\.id), ["abc-home"])
        XCTAssertNoThrow(try store.load(homeID: "abc-home"))
    }

    func testAFileWhoseNameIsNotAValidIDIsNotListed() throws {
        let store = try makeStore()
        try bungalow(id: "a.b").serialized()
            .write(to: directory.appendingPathComponent("a.b.\(HomeDocumentStore.fileExtension)"))

        XCTAssertEqual(store.list().map(\.id), [])
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
