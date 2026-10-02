//  HouseEditorSessionControllerTests.swift — S11.19, AUD-013: House never writes over a newer file.
//
//  The in-memory disk below stamps `meta.modified` on save, as `HomeDocumentStore` does, so the
//  "my own save is not someone else's" case is tested against the same trap the real store sets.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

/// An in-memory home directory. Every write goes through `write`, which stamps the time.
private final class MemoryDisk: HouseEditorDocumentAccess {
    var files: [String: HomeModel] = [:]
    var saves = 0
    var clock = Date(timeIntervalSince1970: 1_800_000_000)

    func homeFileExists(_ homeID: String) -> Bool { files[homeID] != nil }

    func loadHome(_ homeID: String) throws -> HomeModel {
        guard let home = files[homeID] else { throw CocoaError(.fileNoSuchFile) }
        return home
    }

    func saveHome(_ home: HomeModel) throws -> HomeModel {
        saves += 1
        return write(home)
    }

    /// Another writer (onboarding, re-scan, sync, Profiles) — or the session's own save.
    @discardableResult
    func write(_ home: HomeModel) -> HomeModel {
        clock += 1
        var stamped = home
        stamped.meta.modified = clock
        files[home.home_id] = stamped
        return stamped
    }
}

/// Records what the controller told the rest of the app.
@MainActor
private final class RegistrationRecorder: HouseEditorRegistration {
    var openHomeID: String?
    var events: [String] = []
    func registerOpenHome(_ homeID: String) { openHomeID = homeID; events.append("register") }
    func unregisterOpenHome(_ homeID: String) {
        if openHomeID == homeID { openHomeID = nil }
        events.append("unregister")
    }
}

@MainActor
final class HouseEditorSessionControllerTests: XCTestCase {

    private func homeOnDisk(_ disk: MemoryDisk, named name: String = "Home") -> HomeModel {
        let home = HomeModelStore.newHome(name: name)
        disk.write(home)
        return home
    }

    func testOpenReadsTheFileAndAFreshCheckIsCurrent() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk, named: "Bungalow")
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)

        XCTAssertEqual(try controller.open()?.name, "Bungalow")
        XCTAssertEqual(controller.checkDisk(), .current)
    }

    /// Re-appear after another tab wrote the home: the session must reload what is on disk.
    func testReloadsOnExternalChange() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk)
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)
        _ = try controller.open()

        var elsewhere = try disk.loadHome(home.home_id)
        elsewhere.name = "Changed by onboarding"
        disk.write(elsewhere)

        guard case .changed(let newer) = controller.checkDisk() else {
            return XCTFail("an external write must be reported as a change")
        }
        XCTAssertEqual(newer.name, "Changed by onboarding")
        XCTAssertEqual(controller.checkDisk(), .current, "the reloaded file is the new baseline")
    }

    func testAutosaveRefusesToOverwriteANewerFile() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk)
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)
        var stale = try XCTUnwrap(try controller.open())

        var elsewhere = try disk.loadHome(home.home_id)
        elsewhere.name = "Pulled from another device"
        disk.write(elsewhere)

        stale.name = "Stale edit"
        guard case .reloaded(let newer) = controller.save(stale) else {
            return XCTFail("a save over a changed file must reload instead")
        }
        XCTAssertEqual(newer.name, "Pulled from another device")
        XCTAssertEqual(disk.saves, 0, "nothing may be written over the newer file")
        XCTAssertEqual(try disk.loadHome(home.home_id).name, "Pulled from another device")

        // After the reload, the session is in step again and its next save goes through.
        var next = newer
        next.name = "Edited after reload"
        XCTAssertEqual(controller.save(next), .saved)
        XCTAssertEqual(try disk.loadHome(home.home_id).name, "Edited after reload")
    }

    /// The disk stamps `meta.modified` on every save. The session must fingerprint what landed,
    /// or each of its own saves would look like another writer's and trigger a reload.
    func testOwnSavesDoNotTriggerAReload() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk)
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)
        var model = try XCTUnwrap(try controller.open())

        for name in ["One", "Two", "Three"] {
            model.name = name
            XCTAssertEqual(controller.save(model), .saved)
        }
        XCTAssertEqual(controller.checkDisk(), .current)
        XCTAssertEqual(disk.saves, 3)
    }

    func testDeletedHomeClosesTheSessionAndIsNeverRecreated() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk)
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)
        var model = try XCTUnwrap(try controller.open())

        disk.files[home.home_id] = nil   // S11.21's delete, or the home list's

        XCTAssertEqual(controller.checkDisk(), .deleted)
        XCTAssertTrue(controller.isClosed)
        model.name = "Edit after delete"
        XCTAssertEqual(controller.save(model), .deleted)
        XCTAssertFalse(disk.homeFileExists(home.home_id), "autosave must not re-create a deleted home")

        // Closed is final: even if a file with that id reappears, this session stays out of it.
        disk.write(model)
        XCTAssertEqual(controller.save(model), .deleted)
        XCTAssertEqual(disk.saves, 0)
    }

    /// A brand-new home has no file until its first save; that is not a delete.
    func testABrandNewHomeIsCreatedByItsFirstSave() throws {
        let disk = MemoryDisk()
        let blank = HomeModelStore.newHome(name: "New Home")
        let controller = HouseEditorSessionController(homeID: blank.home_id, disk: disk)

        XCTAssertNil(try controller.open())
        XCTAssertEqual(controller.checkDisk(), .current)
        XCTAssertEqual(controller.save(blank), .saved)
        XCTAssertTrue(disk.homeFileExists(blank.home_id))
        XCTAssertNotNil(controller.knownFingerprint)

        // From now on a missing file is a delete.
        disk.files[blank.home_id] = nil
        XCTAssertEqual(controller.checkDisk(), .deleted)
    }

    func testAnUnreadableFileIsNeverOverwritten() throws {
        final class BrokenDisk: HouseEditorDocumentAccess {
            var saves = 0
            func homeFileExists(_ homeID: String) -> Bool { true }
            func loadHome(_ homeID: String) throws -> HomeModel { throw CocoaError(.fileReadCorruptFile) }
            func saveHome(_ home: HomeModel) throws -> HomeModel { saves += 1; return home }
        }
        let disk = BrokenDisk()
        let home = HomeModelStore.newHome(name: "Corrupt")
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)

        guard case .unreadable = controller.checkDisk() else { return XCTFail("expected unreadable") }
        guard case .failed = controller.save(home) else { return XCTFail("expected the save to refuse") }
        XCTAssertEqual(disk.saves, 0)
    }

    /// The screen could not take the newer file (it failed validation) and gave the session up.
    /// The old store may still commit (a drag frame in flight); it must never write over the file.
    func testAClosedSessionNeverSavesAfterARejectedReload() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk)
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)
        let recorder = RegistrationRecorder()
        controller.registration = recorder
        var stale = try XCTUnwrap(try controller.open())
        _ = controller.appear()

        var elsewhere = try disk.loadHome(home.home_id)
        elsewhere.name = "Too big for the editor"
        disk.write(elsewhere)
        guard case .changed = controller.checkDisk() else { return XCTFail("expected a change") }

        controller.close()

        stale.name = "Late drag frame"
        XCTAssertEqual(controller.save(stale), .deleted)
        XCTAssertEqual(disk.saves, 0)
        XCTAssertEqual(try disk.loadHome(home.home_id).name, "Too big for the editor")
        XCTAssertNil(recorder.openHomeID)
        XCTAssertEqual(controller.appear(), .deleted, "a closed session never re-arms")
    }

    // MARK: - The open-home guard (sync's openHomeID, HomeLibrary.editor)

    /// The bug: the guard was set once at load and cleared on every disappear, so after the first
    /// tab switch sync could write the home House still held. Every appear must re-arm it.
    func testOpenHomeGuardIsReArmedOnEveryAppear() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk)
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)
        let recorder = RegistrationRecorder()
        controller.registration = recorder
        _ = try controller.open()

        XCTAssertEqual(controller.appear(), .current)
        XCTAssertEqual(recorder.openHomeID, home.home_id)

        controller.disappear()                       // tab switch away
        XCTAssertNil(recorder.openHomeID, "sync may write the home while House is away")

        XCTAssertEqual(controller.appear(), .current) // and back
        XCTAssertEqual(recorder.openHomeID, home.home_id, "the guard must be re-armed on re-appear")
        XCTAssertEqual(recorder.events, ["register", "unregister", "register"])
    }

    /// A sync pull that lands while House is away is picked up on the way back, after the guard
    /// is armed again, so nothing can slip in between the check and the guard.
    func testAppearArmsTheGuardBeforeReadingTheFile() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk)
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)
        let recorder = RegistrationRecorder()
        controller.registration = recorder
        _ = try controller.open()
        _ = controller.appear()
        controller.disappear()

        var pulled = try disk.loadHome(home.home_id)
        pulled.name = "Pulled while away"
        disk.write(pulled)

        guard case .changed(let newer) = controller.appear() else {
            return XCTFail("the pull must be reloaded on re-appear")
        }
        XCTAssertEqual(newer.name, "Pulled while away")
        XCTAssertEqual(recorder.openHomeID, home.home_id)
    }

    func testADeletedHomeLiftsTheGuardAndIsNeverReArmed() throws {
        let disk = MemoryDisk()
        let home = homeOnDisk(disk)
        let controller = HouseEditorSessionController(homeID: home.home_id, disk: disk)
        let recorder = RegistrationRecorder()
        controller.registration = recorder
        _ = try controller.open()
        _ = controller.appear()

        disk.files[home.home_id] = nil
        XCTAssertEqual(controller.checkDisk(), .deleted)
        XCTAssertNil(recorder.openHomeID)

        XCTAssertEqual(controller.appear(), .deleted)
        XCTAssertNil(recorder.openHomeID, "a closed session must not claim the home again")
    }
}
