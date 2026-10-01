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
