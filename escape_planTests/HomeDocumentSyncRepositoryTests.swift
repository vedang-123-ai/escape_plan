//
//  HomeDocumentSyncRepositoryTests.swift
//  escape_planTests — S8.4 cloud sync
//
//  ─── THIS FILE HAS NEVER EXECUTED ─────────────────────────────────────────────────────────
//  It needs `xcodebuild test`, and the machine S8.4 was written on cannot run a simulator.
//  It is listed in `docs/tracker/FIRST-PRIORITY.md` as something the next simulator run must
//  confirm. Do not treat its existence as coverage.
//
//  ─── WHY IT HAD TO BE WRITTEN HERE AND NOT IN tools/editorcore ────────────────────────────
//  `Persistence/` is not symlinked into the SwiftPM package, so `swift test` cannot reach
//  `HomeDocumentSyncRepository` at all. `SyncManagerTests` exercises `InMemoryHomeRepository`,
//  whose `writePulledHome` is one line — `homes[home.home_id] = home` — and which therefore
//  CANNOT reproduce the hazard this adapter exists to defuse: `HomeDocumentStore.save(model:)`
//  defaults to `now: Date()` and `HomeDocument.touched(at:)` writes that into
//  `meta.modified`. So the package's ping-pong test passes no matter what the real adapter
//  does. Every test below runs against a real `HomeDocumentStore` in a scratch directory.

import XCTest

@testable import escape_plan

@MainActor
final class HomeDocumentSyncRepositoryTests: XCTestCase {

    private var scratch: URL!
    private var store: HomeDocumentStore!
    private var stateStore: InMemorySyncStateStore!
    private var repository: HomeDocumentSyncRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-repo-tests-\(UUID().uuidString)", isDirectory: true)
        store = try HomeDocumentStore(directory: scratch)
        stateStore = InMemorySyncStateStore()
        repository = HomeDocumentSyncRepository(store: store, stateStore: stateStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        repository = nil
        store = nil
        stateStore = nil
        scratch = nil
        try super.tearDownWithError()
    }

    private func bungalow() throws -> HomeModel {
        try PersistenceFixtures.document("bungalow").decode(as: HomeModel.self)
    }

    // MARK: - The ping-pong guard (the reason this file exists)

    /// A pulled home must land on disk VERBATIM, `meta.modified` included.
    ///
    /// If it is re-stamped with the current time it looks newer than the server's copy, the
    /// next sync pushes it straight back, the server increments its revision, and two devices
    /// trade the same home forever with nobody editing anything.
    func testAPulledHomeKeepsTheServersModifiedDate() throws {
        var home = try bungalow()
        home.meta.modified = Date(timeIntervalSince1970: 1_500_000_000)

        try repository.writePulledHome(home)

        let onDisk = try store.load(homeID: home.home_id, as: HomeModel.self)
        XCTAssertEqual(onDisk.meta.modified, home.meta.modified)
        XCTAssertEqual(onDisk, home, "the whole model must round-trip, not just the timestamp")
    }

    /// The hazard itself, stated so the test above cannot be misread as trivial: the DEFAULT
    /// save path really does overwrite `meta.modified`.
    func testTheDefaultSavePathWouldHaveRewrittenTheDate() throws {
        var home = try bungalow()
        home.meta.modified = Date(timeIntervalSince1970: 1_500_000_000)

        try store.save(model: home)   // no `now:` — the trap

        let onDisk = try store.load(homeID: home.home_id, as: HomeModel.self)
        XCTAssertNotEqual(onDisk.meta.modified, home.meta.modified)
    }

    /// And the same property for the starter homes, which keep FIXED `home_id`s: a fresh
    /// install must not produce a pristine fixture carrying today's date, or it beats the
    /// user's real home on the conflict tiebreak and is pushed over a month of their work.
    func testStarterHomesAreSeededWithTheirOwnDatesNotTheInstallTime() throws {
        let defaults = UserDefaults(suiteName: "seed.\(UUID().uuidString)")!
        let seeded = try FixtureSeeder.seedStarterHomes(into: store, defaults: defaults)
        XCTAssertFalse(seeded.isEmpty)

        for model in seeded {
            let onDisk = try store.load(homeID: model.home_id, as: HomeModel.self)
            XCTAssertEqual(onDisk.meta.modified, model.meta.modified, model.name)
            XCTAssertLessThan(onDisk.meta.modified, Date(),
                              "\(model.name) was stamped at install time")
        }
    }

    // MARK: - Never overwrite an open editor

    func testAHomeOpenInTheEditorIsNotOverwritten() throws {
        let home = try bungalow()
        try store.save(model: home, now: home.meta.modified)
        repository.openHomeID = home.home_id

        var fromServer = home
        fromServer.name = "Renamed elsewhere"
        XCTAssertThrowsError(try repository.writePulledHome(fromServer)) { error in
            XCTAssertEqual((error as? SyncFailure)?.kind, .localWriteBlocked)
        }
        XCTAssertEqual(try store.load(homeID: home.home_id, as: HomeModel.self).name, home.name)
    }

    func testADifferentHomeIsStillWrittenWhileTheEditorIsOpen() throws {
        let open = try bungalow()
        repository.openHomeID = open.home_id

        var other = try bungalow()
        other.home_id = "home-from-the-other-phone"
        XCTAssertNoThrow(try repository.writePulledHome(other))
        XCTAssertTrue(store.exists(homeID: "home-from-the-other-phone"))
    }

    // MARK: - A document that exists but will not decode

    /// "Skipped because it did not decode" and "not on this device" mean very different things
    /// to sync. Treating the first as the second lets the server's copy be written over a file
    /// that a future `SchemaMigrator` may well be able to read.
    func testAnUndecodableDocumentIsNotOverwrittenByTheServersCopy() throws {
        let home = try bungalow()
        let corrupt = store.url(for: home.home_id)
        try Data(#"{"home_id":"\#(home.home_id)","schema_version":"2.1","floors":"not an array"}"#.utf8)
            .write(to: corrupt)

        // The load pass is what notices, so it has to happen first — as it does in a real run.
        _ = try repository.loadAllHomes()

        XCTAssertThrowsError(try repository.writePulledHome(home)) { error in
            XCTAssertEqual((error as? SyncFailure)?.kind, .localWriteBlocked)
        }
    }

    func testOneUnreadableDocumentDoesNotHideTheOthers() throws {
        let good = try bungalow()
        try store.save(model: good, now: good.meta.modified)
        try Data("not json at all".utf8)
            .write(to: store.url(for: "11111111-2222-3333-4444-555555555555"))

        let homes = try repository.loadAllHomes()
        XCTAssertEqual(homes.map(\.home_id), [good.home_id])
    }

    func testAMissingLibraryDirectoryThrowsRatherThanReportingAnEmptyDevice() throws {
        try FileManager.default.removeItem(at: scratch)
        // An apparently empty device synced against an account full of homes would download
        // everything over nothing, so this must NOT read as "no homes here".
        XCTAssertThrowsError(try repository.loadAllHomes())
    }

    // MARK: - A losing conflict is set aside

    func testPreservingTheLocalCopyLeavesBothHomesOnDisk() throws {
        let home = try bungalow()
        try store.save(model: home, now: home.meta.modified)

        let copyID = try repository.preserveLocalCopy(of: home, named: "Bungalow (this device)")

        XCTAssertNotEqual(copyID, home.home_id)
        XCTAssertTrue(store.exists(homeID: home.home_id))
        let copy = try store.load(homeID: copyID, as: HomeModel.self)
        XCTAssertEqual(copy.name, "Bungalow (this device)")
        XCTAssertEqual(copy.floors, home.floors, "the copy must be the user's actual content")
    }

    // MARK: - Asked before a conflict copy is made (S11.22, AUD-015)

    /// `SyncManager` asks this before preserving a losing local copy. It must refuse the home
    /// open in House with the same failure `writePulledHome` throws, and write nothing.
    func testTheOpenHomeIsRefusedBeforeAnyCopyIsMade() throws {
        let home = try bungalow()
        try store.save(model: home, now: home.meta.modified)
        repository.openHomeID = home.home_id
        let before = store.list().count

        XCTAssertThrowsError(try repository.checkCanWritePulledHome(home)) { error in
            XCTAssertEqual(error as? SyncFailure, .editorHasTheHomeOpen)
        }
        XCTAssertEqual(store.list().count, before, "a check must not write")

        repository.openHomeID = nil
        XCTAssertNoThrow(try repository.checkCanWritePulledHome(home), "a closed home may be written")
    }

    // MARK: - The server's home_id is checked before it becomes a path (S11.41, AUD-012)

    func testAPulledHomeWithATraversalIDIsAPerHomeFailureAndWritesNothing() throws {
        var hostile = try bungalow()
        let escapee = "s1141-pull-\(UUID().uuidString)"
        hostile.home_id = "../\(escapee)"
        let outside = scratch.deletingLastPathComponent()
            .appendingPathComponent("\(escapee).\(HomeDocumentStore.fileExtension)")
        defer { try? FileManager.default.removeItem(at: outside) }

        XCTAssertThrowsError(try repository.checkCanWritePulledHome(hostile)) { error in
            XCTAssertEqual(error as? SyncFailure, HomeDocumentSyncRepository.pulledHomeIDRefused)
        }
        XCTAssertThrowsError(try repository.writePulledHome(hostile)) { error in
            XCTAssertEqual(error as? SyncFailure, HomeDocumentSyncRepository.pulledHomeIDRefused)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(store.list().count, 0)
    }

    func testAPulledHomeWithAnUpperCaseUUIDIsStillWritten() throws {
        var home = try bungalow()
        home.home_id = UUID().uuidString
        XCTAssertNoThrow(try repository.writePulledHome(home))
        XCTAssertEqual(store.list().map(\.id), [home.home_id])
    }

    /// The same check covers a document that did not decode.
    func testAnUndecodableDocumentIsRefusedBeforeAnyCopyIsMade() throws {
        let home = try bungalow()
        try Data(#"{"home_id":"\#(home.home_id)","schema_version":"2.1","floors":"not an array"}"#.utf8)
            .write(to: store.url(for: home.home_id))
        _ = try repository.loadAllHomes()

        XCTAssertThrowsError(try repository.checkCanWritePulledHome(home)) { error in
            XCTAssertEqual(error as? SyncFailure, .localCopyUnreadable)
        }
    }

    // MARK: - Deletion tombstones

    func testDeletingAHomeRecordsATombstone() throws {
        try repository.homeWasDeletedLocally(homeID: "home-gone")
        XCTAssertTrue(stateStore.load().isDeletedLocally("home-gone"))
    }

    /// The seam that carries it: `HomeLibrary.delete` must tell the observer, or nothing above
    /// ever writes a tombstone and every deleted home comes back on the next sync.
    func testTheLibraryTellsTheRepositoryWhenAHomeIsDeleted() throws {
        let home = try bungalow()
        try store.save(model: home, now: home.meta.modified)
        let library = HomeLibrary(store: store)
        library.deletionObserver = repository

        library.delete(homeID: home.home_id)

        XCTAssertTrue(stateStore.load().isDeletedLocally(home.home_id))
        XCTAssertFalse(store.exists(homeID: home.home_id))
    }

    /// A tombstone that will not save is no longer swallowed (S11.22): the home is still gone,
    /// `delete` still says so, and the reason reaches `loadError` for Home to show.
    func testATombstoneThatWillNotSaveIsReportedNotSwallowed() throws {
        final class RefusingStore: SyncStateStore {
            struct Refused: Error {}
            func load() -> SyncState { .empty }
            func save(_ state: SyncState) throws { throw Refused() }
        }
        let home = try bungalow()
        try store.save(model: home, now: home.meta.modified)
        let refusing = HomeDocumentSyncRepository(store: store, stateStore: RefusingStore())
        let library = HomeLibrary(store: store)
        library.deletionObserver = refusing

        XCTAssertThrowsError(try refusing.homeWasDeletedLocally(homeID: "x")) { error in
            XCTAssertEqual(error as? DeletionNotRemembered, DeletionNotRemembered())
        }
        XCTAssertTrue(library.delete(homeID: home.home_id), "the file did go")
        XCTAssertFalse(store.exists(homeID: home.home_id))
        XCTAssertEqual(library.loadError, DeletionNotRemembered().errorDescription)
    }

    /// A delete that FAILS must not leave a tombstone for a home that is still on disk.
    func testAFailedDeleteLeavesNoTombstone() throws {
        let library = HomeLibrary(store: store)
        library.deletionObserver = repository

        library.delete(homeID: "no-such-home")

        XCTAssertFalse(stateStore.load().isDeletedLocally("no-such-home"))
    }
}
