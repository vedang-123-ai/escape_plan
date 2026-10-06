//  HomeLibraryEditorSeamTests.swift — the HomeModelPersisting seam, finally wired.
//
//  The scenario the seam exists for: a home is open in the editor while the user deletes it
//  from the home list. The library must tell the open session, the session must drop its undo
//  history (those snapshots describe a document that no longer exists), and flag itself so
//  `EditorScreen` dismisses.

import XCTest

@testable import escape_plan

@MainActor
final class HomeLibraryEditorSeamTests: XCTestCase {

    private func makeStores() throws -> (HomeDocumentStore, HomeLibrary) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seam-tests-\(UUID().uuidString)", isDirectory: true)
        let docStore = try HomeDocumentStore(directory: dir)
        return (docStore, HomeLibrary(store: docStore))
    }

    private func openSession(for model: HomeModel, in library: HomeLibrary) throws -> EditorSession {
        let store = try HomeModelStore(model: model)
        let session = EditorSession(store: store)
        store.onCommit = { session.undoStack.recordCommit($0) }
        library.editor = session
        return session
    }

    func testDeletingTheOpenHomeClosesEditorAndClearsUndo() throws {
        let (docStore, library) = try makeStores()
        let model = HomeModelStore.newHome(name: "Doomed")
        _ = try docStore.save(model: model)
        library.refresh()

        let session = try openSession(for: model, in: library)
        session.store.dispatch(.setHomeName("Renamed"))
        XCTAssertTrue(session.undoStack.canUndo, "precondition: there is history to lose")
        XCTAssertEqual(session.openHomeID, model.home_id)

        library.delete(homeID: model.home_id)

        XCTAssertTrue(session.wasDeletedExternally, "the session must learn its home is gone")
        XCTAssertFalse(session.undoStack.canUndo)
        XCTAssertFalse(session.undoStack.canRedo)
        XCTAssertFalse(library.homes.contains { $0.id == model.home_id })
    }

    func testDeletingADifferentHomeLeavesTheOpenEditorAlone() throws {
        let (docStore, library) = try makeStores()
        let open = HomeModelStore.newHome(name: "Open")
        let other = HomeModelStore.newHome(name: "Other")
        _ = try docStore.save(model: open)
        _ = try docStore.save(model: other)
        library.refresh()

        let session = try openSession(for: open, in: library)
        session.store.dispatch(.setHomeName("Still Open"))

        library.delete(homeID: other.home_id)

        XCTAssertFalse(session.wasDeletedExternally)
        XCTAssertTrue(session.undoStack.canUndo, "history for a different home must survive")
    }

    // MARK: - Delete, duplicate, and no blank home until the first edit (S11.21, AUD-021)

    /// Home's "Your homes" list deletes the active home with `library.delete` then
    /// `readiness.ensureActiveHome()`. The next home takes over; deleting the last leaves none,
    /// which is what shows "Map your home".
    func testDeletingTheActiveHomeMovesToAnotherAndTheLastLeavesNone() throws {
        let (docStore, library) = try makeStores()
        let first = HomeModelStore.newHome(name: "First")
        let second = HomeModelStore.newHome(name: "Second")
        _ = try docStore.save(model: first, now: Date(timeIntervalSince1970: 1_000))
        _ = try docStore.save(model: second, now: Date(timeIntervalSince1970: 2_000))
        library.refresh()
        let readiness = ReadinessStore(library: library)
        XCTAssertEqual(readiness.activeHomeID, second.home_id, "precondition: newest is active")

        XCTAssertTrue(library.delete(homeID: second.home_id))
        readiness.ensureActiveHome()
        XCTAssertEqual(readiness.activeHomeID, first.home_id)

        XCTAssertTrue(library.delete(homeID: first.home_id))
        readiness.ensureActiveHome()
        XCTAssertNil(readiness.activeHomeID)
        XCTAssertTrue(library.homes.isEmpty)
    }

    /// The app's own path, not a copy of it: the library tells the real sync repository, whose
    /// tombstone carries the owner the confirmation promised to delete from (SyncDeletionTests
    /// then proves what a sync does with that tombstone).
    func testTheConfirmationsPromiseMatchesTheTombstoneTheAppWrites() throws {
        let (docStore, library) = try makeStores()
        let stateStore = InMemorySyncStateStore()
        let sync = HomeDocumentSyncRepository(store: docStore, stateStore: stateStore)
        library.deletionObserver = sync
        let owned = HomeModelStore.newHome(name: "Backed up")
        let local = HomeModelStore.newHome(name: "Only here")
        _ = try docStore.save(model: owned, now: Date())
        _ = try docStore.save(model: local, now: Date())
        library.refresh()
        var state = stateStore.load()
        state.homeOwners[owned.home_id] = "u-1"
        try stateStore.save(state)

        XCTAssertEqual(sync.deletionReach(of: owned.home_id, signedInUserID: "u-1"), .deviceAndAccount)
        XCTAssertEqual(sync.deletionReach(of: owned.home_id, signedInUserID: nil), .deviceNowAccountLater)
        XCTAssertEqual(sync.deletionReach(of: local.home_id, signedInUserID: "u-1"), .thisDeviceOnly)

        XCTAssertTrue(library.delete(homeID: owned.home_id))
        XCTAssertTrue(library.delete(homeID: local.home_id))
        let after = stateStore.load()
        XCTAssertEqual(after.deletions[owned.home_id]?.ownerUserID, "u-1")
        XCTAssertNotNil(after.deletions[local.home_id])
        XCTAssertNil(after.deletions[local.home_id]?.ownerUserID, "an ownerless tombstone never deletes from a server")
    }

    func testAFailedDeleteSaysSoAndLeavesNoTombstone() throws {
        let (_, library) = try makeStores()
        let observer = RecordingDeletionObserver()
        library.deletionObserver = observer

        XCTAssertFalse(library.delete(homeID: "no-such-home"))
        XCTAssertNotNil(library.loadError)
        XCTAssertTrue(observer.deleted.isEmpty, "a tombstone for a home still on disk, or never there")
    }

    /// House opens a brand-new home through a controller with no file behind it. Nothing reaches
    /// disk until the first committed edit saves, so backing out of Build Manually leaves nothing.
    /// (HomeDeleteUITests drives the real screen.)
    func testABlankHomeIsNotWrittenUntilItsFirstSave() throws {
        let (docStore, library) = try makeStores()
        let blank = HomeModelStore.newHome(name: "New Home")
        let controller = HouseEditorSessionController(homeID: blank.home_id, disk: docStore)

        XCTAssertNil(try controller.open())
        XCTAssertEqual(controller.appear(), .current)
        library.refresh()
        XCTAssertTrue(library.homes.isEmpty, "opening a blank home wrote a file")

        XCTAssertEqual(controller.save(blank), .saved)
        library.refresh()
        XCTAssertEqual(library.homes.map(\.id), [blank.home_id])
    }

    /// S53-1: a fresh install gets the three real demo homes and opens on Two-Story House, never
    /// on "Jagged Stack" (the floor-stacking test model, which stays a bundled fixture).
    func testAFreshInstallGetsTheThreeDemoHomesAndOpensOnTwoStory() throws {
        let (docStore, library) = try makeStores()
        let suite = "s1157-seed-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let seeded = try FixtureSeeder.seedStarterHomes(into: docStore, defaults: defaults)
        XCTAssertEqual(Set(seeded.map(\.name)), ["Bungalow", "Apartment 4B", "Two-Story House"])
        library.refresh()
        XCTAssertEqual(library.homes.count, 3)
        XCTAssertFalse(library.homes.contains { $0.name == "Jagged Stack" })
        XCTAssertNoThrow(try FixtureLoader.load(.jagged), "the test model is still bundled")

        let readiness = ReadinessStore(library: library, homeMemory: ActiveHomeMemory(defaults: defaults))
        XCTAssertEqual(library.homes.first { $0.id == readiness.activeHomeID }?.name, "Two-Story House")
        XCTAssertEqual(readiness.activeHomeID, FixtureSeeder.demoHomeID)
    }

    /// Starter homes are removable like any home, and the seeding flag keeps a deleted one gone
    /// on the next launch.
    func testADeletedStarterHomeIsNotReseeded() throws {
        let (docStore, library) = try makeStores()
        let suite = "s1121-seed-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let seeded = try FixtureSeeder.seedStarterHomes(into: docStore, defaults: defaults)
        let bungalow = try XCTUnwrap(seeded.first { $0.name == "Bungalow" })
        library.refresh()
        XCTAssertTrue(library.homes.allSatisfy { HomeLibrary.isStarterHome($0.id) }, "labelled Demo")

        XCTAssertTrue(library.delete(homeID: bungalow.home_id))
        // The next launch runs the same call with the same defaults.
        XCTAssertTrue(try FixtureSeeder.seedStarterHomes(into: docStore, defaults: defaults).isEmpty)
        library.refresh()
        XCTAssertFalse(library.homes.contains { $0.id == bungalow.home_id }, "the deleted starter came back")
    }

    /// A duplicate is a new home: new id, "<name> copy", the household comes along inside the
    /// document, not a demo even when copied from one, and the original's checklist ticks stay
    /// with the original (docs/decisions.md 2026-10-02).
    func testDuplicateIsAnIndependentHomeWithTheHouseholdButNotTheTicks() throws {
        let (docStore, library) = try makeStores()
        let suite = "s1121-dup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = try XCTUnwrap(
            FixtureSeeder.seedStarterHomes(into: docStore, defaults: defaults).first { !$0.profiles.isEmpty },
            "a starter home with a household")
        let ticks = ChecklistStateStore(defaults: defaults)
        ticks.save(["smoke.test": true], homeID: original.home_id)
        library.refresh()

        let copyID = try XCTUnwrap(library.duplicate(homeID: original.home_id))

        XCTAssertNotEqual(copyID, original.home_id)
        let copy = try docStore.load(homeID: copyID, as: HomeModel.self)
        XCTAssertEqual(copy.name, "\(original.name) copy")
        XCTAssertEqual(copy.profiles, original.profiles)
        XCTAssertFalse(HomeLibrary.isStarterHome(copyID))
        XCTAssertTrue(ticks.load(homeID: copyID).isEmpty)
        XCTAssertEqual(ticks.load(homeID: original.home_id), ["smoke.test": true])
    }

    // MARK: - One store for the whole app (AUD-019, S11.18)
    //
    // On the launch fallback the library reads a temporary directory. A screen that built its own
    // `HomeDocumentStore()` wrote to the real Documents path instead, so its saves never showed up
    // in the library. Each screen-level writer must save into the library's directory.

    /// Asserts `writer` is the library's store by saving through it and finding the file there.
    private func assertSavesLandInLibrary(_ writer: HomeDocumentStore?, _ library: HomeLibrary,
                                          file: StaticString = #filePath, line: UInt = #line) throws {
        let writer = try XCTUnwrap(writer, "the screen must have a store", file: file, line: line)
        XCTAssertEqual(writer.directory, library.store.directory, file: file, line: line)
        let model = HomeModelStore.newHome(name: "Through the screen")
        _ = try writer.save(model: model)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.store.url(for: model.home_id).path),
                      "the save must land in the library's directory", file: file, line: line)
        library.refresh()
        XCTAssertTrue(library.homes.contains { $0.id == model.home_id }, file: file, line: line)
    }

    func testHouseScreenSavesThroughTheLibrarysStore() throws {
        let (_, library) = try makeStores()
        try assertSavesLandInLibrary(HouseScreen(homeID: nil, library: library).documentStore, library)
    }

    func testProfilesScreenSavesThroughTheStoreItIsGiven() throws {
        let (_, library) = try makeStores()
        try assertSavesLandInLibrary(ProfilesScreen(homeID: "any", store: library.store).documentStore, library)
    }

    func testOnboardingSeedsIntoTheLibrarysStore() throws {
        let (_, library) = try makeStores()
        let state = OnboardingState(documentStore: library.store)

        state.seedIfNeeded()

        let seeded = try XCTUnwrap(state.seededHome, state.seedError ?? "nothing was seeded")
        library.refresh()
        XCTAssertEqual(library.homes.map(\.id), [seeded.home_id],
                       "the demo home must land in the library's directory, not Documents")
    }
}

@MainActor
private final class RecordingDeletionObserver: HomeDeletionObserving {
    var deleted: [String] = []
    func homeWasDeletedLocally(homeID: String) { deleted.append(homeID) }
}
