//  HouseEditorReloadTests.swift — S11.19, AUD-013, against the real store.
//
//  House keeps its editor session across tab switches. While it is away, other screens write the same
//  home file through `library.store` (the one store since S11.18). The session's next autosave must
//  not write its stale copy over that work. The EditorCore twin
//  (`HouseEditorSessionControllerTests`) covers the same rules with an in-memory disk; this file proves
//  them on `HomeDocumentStore` itself, whose save stamps `meta.modified`.

import XCTest

@testable import escape_plan

@MainActor
final class HouseEditorReloadTests: XCTestCase {

    private func makeLibrary() throws -> HomeLibrary {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("house-reload-\(UUID().uuidString)", isDirectory: true)
        return HomeLibrary(store: try HomeDocumentStore(directory: dir))
    }

    /// The session House builds: a store whose commits autosave through the controller.
    private func openSession(_ homeID: String, in library: HomeLibrary)
        throws -> (HomeModelStore, HouseEditorSessionController) {
        let controller = HouseEditorSessionController(homeID: homeID, disk: library.store)
        let model = try XCTUnwrap(try controller.open())
        let store = try HomeModelStore(model: model)
        return (store, controller)
    }

    /// MISSION 0(b): while a session holds home X, another writer saves a changed X through the
    /// library's store; the session then commits an edit. The other write must survive.
    func testAnotherWritersChangeSurvivesTheSessionsNextEdit() throws {
        let library = try makeLibrary()
        let home = HomeModelStore.newHome(name: "Shared")
        try library.store.save(model: home)

        let (store, controller) = try openSession(home.home_id, in: library)
        var outcomes: [HouseEditorSessionController.SaveOutcome] = []
        store.onCommit = { _ in outcomes.append(controller.save(store.model)) }

        // The onboarding interview, a re-scan "Add to Home" or a sync pull: a changed X, written
        // through the same store, without telling the session.
        var elsewhere = try library.store.load(homeID: home.home_id, as: HomeModel.self)
        elsewhere.name = "Renamed elsewhere"
        try library.store.save(model: elsewhere)

        // An edit in House on its stale copy.
        let addRoom = store.dispatch(.addRoom(floorId: store.activeFloorId, origin: Point(x: 20, y: 0),
                                              width_m: 3, height_m: 3, type: .other, name: "Stale edit"))
        XCTAssertTrue(addRoom.didApply, "precondition: the edit itself is valid")

        let onDisk = try library.store.load(homeID: home.home_id, as: HomeModel.self)
        XCTAssertEqual(onDisk.name, "Renamed elsewhere",
                       "the other writer's change was overwritten by the session's stale copy")
        guard case .reloaded(let newer)? = outcomes.last else {
            return XCTFail("the session must reload rather than save, got \(outcomes)")
        }
        XCTAssertEqual(newer.name, "Renamed elsewhere")
    }

    /// The session's own saves must not look like someone else's: `save(model:)` stamps
    /// `meta.modified`, so a fingerprint of the in-memory model would never match the file.
    func testTheSessionsOwnSavesAreNotMistakenForAnotherWriter() throws {
        let library = try makeLibrary()
        let home = HomeModelStore.newHome(name: "Mine")
        try library.store.save(model: home)

        let (store, controller) = try openSession(home.home_id, in: library)
        var outcomes: [HouseEditorSessionController.SaveOutcome] = []
        store.onCommit = { _ in outcomes.append(controller.save(store.model)) }

        store.dispatch(.setHomeName("First"))
        store.dispatch(.setHomeName("Second"))

        XCTAssertEqual(outcomes, [.saved, .saved])
        XCTAssertEqual(controller.checkDisk(), .current)
        XCTAssertEqual(try library.store.load(homeID: home.home_id, as: HomeModel.self).name, "Second")
    }

    /// The adapter returns the model it wrote instead of reading the file back, so what it returns
    /// must fingerprint exactly like the file (dates are stored to whole seconds). Real fixtures, a
    /// few saves each: a mismatch would make House reload after every one of its own edits.
    func testEachOwnSaveFingerprintsLikeTheFileOnTheRealFixtures() throws {
        for name in ["bungalow", "apartment", "twostory"] {
            let library = try makeLibrary()
            let home = try PersistenceFixtures.document(name).decode(as: HomeModel.self)
            try library.store.save(model: home)
            let (store, controller) = try openSession(home.home_id, in: library)
            var outcomes: [HouseEditorSessionController.SaveOutcome] = []
            store.onCommit = { _ in outcomes.append(controller.save(store.model)) }

            for rename in ["A", "B", "C"] { store.dispatch(.setHomeName("\(name) \(rename)")) }

            XCTAssertEqual(outcomes, [.saved, .saved, .saved], name)
            XCTAssertEqual(controller.checkDisk(), .current, name)
            XCTAssertEqual(controller.knownFingerprint,
                           HomeFingerprint.of(try library.store.load(homeID: home.home_id, as: HomeModel.self)), name)
        }
    }

    /// Deleted underneath: the session closes and its next autosave does not re-create the file.
    func testDeletedHomeIsNeverRecreatedByAutosave() throws {
        let library = try makeLibrary()
        let home = HomeModelStore.newHome(name: "Doomed")
        try library.store.save(model: home)
        library.refresh()

        let (store, controller) = try openSession(home.home_id, in: library)
        var outcomes: [HouseEditorSessionController.SaveOutcome] = []
        store.onCommit = { _ in outcomes.append(controller.save(store.model)) }

        library.delete(homeID: home.home_id)
        store.dispatch(.setHomeName("Too late"))

        XCTAssertEqual(outcomes, [.deleted])
        XCTAssertTrue(controller.isClosed)
        XCTAssertFalse(library.store.exists(homeID: home.home_id), "autosave re-created a deleted home")
    }

    /// MISSION 1, against the real sync repository: while House is visible with a live session,
    /// sync must refuse to write its home, including after a tab switch away and back.
    func testSyncStillRefusesTheOpenHomeAfterATabSwitch() throws {
        let library = try makeLibrary()
        let home = HomeModelStore.newHome(name: "Held")
        try library.store.save(model: home)
        let sync = HomeDocumentSyncRepository(store: library.store, stateStore: InMemorySyncStateStore())
        sync.library = library

        let (store, controller) = try openSession(home.home_id, in: library)
        let session = EditorSession(store: store)
        controller.registration = HouseEditorAppRegistration(session: session, library: library,
                                                             syncRepository: sync)
        var pulled = home
        pulled.name = "From the other phone"

        _ = controller.appear()
        XCTAssertThrowsError(try sync.writePulledHome(pulled), "visible House: sync must refuse")
        XCTAssertTrue(library.editor === session)

        controller.disappear()
        XCTAssertNil(sync.openHomeID)
        XCTAssertNil(library.editor)

        _ = controller.appear()
        XCTAssertEqual(sync.openHomeID, home.home_id, "re-armed on re-appear")
        XCTAssertTrue(library.editor === session)
        XCTAssertThrowsError(try sync.writePulledHome(pulled), "re-appeared House: sync must refuse again")
        XCTAssertEqual(try library.store.load(homeID: home.home_id, as: HomeModel.self).name, "Held")
    }
}
