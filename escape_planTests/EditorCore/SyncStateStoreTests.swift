//  SyncStateStoreTests.swift — the sidecar that keeps sync state OUT of the schema.
//
//  Recording `last_synced_revision` on `HomeModel` would have been a change to
//  `schema/homemodel.schema.json` — the project's one law — needing a `schema_version` bump,
//  matching pydantic and Swift changes, and a clean `schema-contract-guardian` run. It would
//  also be wrong: sync progress is a fact about THIS DEVICE, and a device-local fact stored
//  inside a synced document is overwritten by the very sync it describes.
//
//  These tests run against a real FileManager in a scratch directory, so the file store is
//  exercised rather than argued about.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class SyncStateStoreTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-state-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        scratch = nil
        try super.tearDownWithError()
    }

    private var fileURL: URL { scratch.appendingPathComponent(FileSyncStateStore.filename) }

    private func makeRecord(_ id: String, revision: Int = 3) -> HomeSyncRecord {
        HomeSyncRecord(localHomeID: id,
                       remoteID: "srv-\(id)",
                       syncedRevision: revision,
                       syncedFingerprint: "0123456789abcdef",
                       lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - Round trip

    func testAnUnwrittenSidecarReadsAsNothingEverSynced() {
        XCTAssertEqual(FileSyncStateStore(url: fileURL).load(), .empty)
    }

    func testRecordsSurviveAcrossStoreInstances() throws {
        var state = SyncState.empty
        state.remember(makeRecord("home-1"))
        state.remember(makeRecord("home-2", revision: 11))
        try FileSyncStateStore(url: fileURL).save(state)

        // A SECOND store object reading the same file — which is the only shape of this test
        // that says anything about persistence. Re-reading from the same instance would prove
        // only that a property holds what was assigned to it.
        let reloaded = FileSyncStateStore(url: fileURL).load()
        XCTAssertEqual(reloaded, state)
        XCTAssertEqual(reloaded.record(for: "home-2")?.syncedRevision, 11)
        XCTAssertEqual(reloaded.record(for: "home-2")?.remoteID, "srv-home-2")
    }

    func testTheLastSyncedDateSurvivesTheRoundTrip() throws {
        var state = SyncState.empty
        let record = makeRecord("home-1")
        state.remember(record)
        try FileSyncStateStore(url: fileURL).save(state)
        XCTAssertEqual(FileSyncStateStore(url: fileURL).load().record(for: "home-1")?.lastSyncedAt,
                       record.lastSyncedAt)
    }

    func testForgettingARecordRemovesItFromTheFile() throws {
        let store = FileSyncStateStore(url: fileURL)
        var state = SyncState.empty
        state.remember(makeRecord("home-1"))
        state.remember(makeRecord("home-2"))
        try store.save(state)

        state.forget(localHomeID: "home-1")
        try store.save(state)

        let reloaded = FileSyncStateStore(url: fileURL).load()
        XCTAssertNil(reloaded.record(for: "home-1"))
        XCTAssertNotNil(reloaded.record(for: "home-2"))
    }

    // MARK: - Degrading safely

    /// Corruption must read as "nothing has ever synced" — one redundant upload per home —
    /// never as a crash and never as a partial state that could push a stale home.
    func testAnUnreadableSidecarReadsAsEmptyRatherThanThrowing() throws {
        try Data("this is not JSON".utf8).write(to: fileURL)
        XCTAssertEqual(FileSyncStateStore(url: fileURL).load(), .empty)
    }

    /// A sidecar written by a FUTURE build describes records in a shape this build may
    /// misread, and acting on a misread record could push a stale home over a newer one.
    func testASidecarFromAFutureVersionIsIgnored() throws {
        let json = """
        {"version":99,"records":{"home-1":{"localHomeID":"home-1","remoteID":"srv-1",\
        "syncedRevision":4,"syncedFingerprint":"aaaaaaaaaaaaaaaa",\
        "lastSyncedAt":"2026-09-16T05:33:58Z"}}}
        """
        try Data(json.utf8).write(to: fileURL)
        XCTAssertEqual(FileSyncStateStore(url: fileURL).load(), .empty)
    }

    /// The same document at the CURRENT version must load — otherwise the test above would
    /// pass for the wrong reason (a decode failure rather than the version guard).
    ///
    /// Note what this payload does NOT have: `deletedHomeIDs`. A sidecar written before a
    /// field existed must not take the whole file down with it, which would silently degrade
    /// to "this device has never synced anything".
    func testTheSameSidecarAtTheCurrentVersionDoesLoad() throws {
        let json = """
        {"version":\(SyncState.currentVersion),"records":{"home-1":{"localHomeID":"home-1",\
        "remoteID":"srv-1","syncedRevision":4,"syncedFingerprint":"aaaaaaaaaaaaaaaa",\
        "lastSyncedAt":"2026-09-16T05:33:58Z"}}}
        """
        try Data(json.utf8).write(to: fileURL)
        let loaded = FileSyncStateStore(url: fileURL).load()
        XCTAssertEqual(loaded.record(for: "home-1")?.syncedRevision, 4)
        XCTAssertTrue(loaded.deletions.isEmpty, "an absent collection must decode as empty")
    }

    // MARK: - Conflict copies (S11.22): a new field, the same version

    /// A sidecar exactly as a build from before S11.22 wrote it: version 3, no
    /// `preservedCopies`. It must load with every record, tombstone and owner intact. Bumping
    /// the version instead would discard it, and with it the tombstones that stop deleted homes
    /// coming back.
    func testAVersion3SidecarWrittenBeforeConflictCopiesStillLoadsWhole() throws {
        let old = """
        {
          "deletions" : {
            "home-gone" : { "deletedAt" : "2026-09-30T10:00:00Z", "ownerUserID" : "alice" }
          },
          "homeOwners" : { "home-1" : "alice" },
          "records" : {
            "home-1" : {
              "lastSyncedAt" : "2026-09-30T09:00:00Z",
              "localHomeID" : "home-1",
              "remoteID" : "srv-1",
              "syncedFingerprint" : "0123456789abcdef",
              "syncedRevision" : 4
            }
          },
          "userID" : "alice",
          "version" : 3
        }
        """
        try Data(old.utf8).write(to: fileURL)

        let loaded = FileSyncStateStore(url: fileURL).load()

        XCTAssertEqual(SyncState.currentVersion, 3, "a bump would discard every phone's sidecar")
        XCTAssertEqual(loaded.userID, "alice")
        XCTAssertEqual(loaded.record(for: "home-1")?.syncedRevision, 4)
        XCTAssertEqual(loaded.deletions["home-gone"]?.ownerUserID, "alice")
        XCTAssertEqual(loaded.homeOwners["home-1"], "alice")
        XCTAssertEqual(loaded.preservedCopies, [:])
    }

    func testARecordedConflictCopySurvivesTheRoundTrip() throws {
        var state = SyncState(userID: "alice")
        state.preservedCopies["home-1"] = PreservedCopy(copyHomeID: "copy-1",
                                                        preservedFingerprint: "fedcba9876543210")
        try FileSyncStateStore(url: fileURL).save(state)

        XCTAssertEqual(FileSyncStateStore(url: fileURL).load(), state)
    }

    /// The conflict is over once both sides agree, or once the original is deleted.
    func testARecordedConflictCopyIsClearedBySyncingOrDeletingTheOriginal() {
        var state = SyncState(userID: "alice")
        let copy = PreservedCopy(copyHomeID: "copy-1", preservedFingerprint: "fedcba9876543210")
        state.preservedCopies["home-1"] = copy
        state.preservedCopies["home-2"] = copy

        state.remember(makeRecord("home-1"))
        state.markDeleted(localHomeID: "home-2", at: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(state.preservedCopies, [:])
    }

    func testSavingCreatesTheDirectoryIfItIsMissing() throws {
        let nested = scratch.appendingPathComponent("not/created/yet/sync-state.json")
        try FileSyncStateStore(url: nested).save(SyncState())
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    /// The sidecar must not live in `<Documents>/Homes`, whose contract is one file per home.
    func testTheAppsSidecarSitsBesideTheHomesFolderNotInsideIt() {
        XCTAssertEqual(FileSyncStateStore.filename, "sync-state.json")
        XCTAssertFalse(FileSyncStateStore.filename.hasSuffix(HomeDocumentStoreFilenameProbe.suffix),
                       "a sidecar named like a home document would be listed as one")
    }
}

/// `HomeDocumentStore` lives in `Persistence/`, which is not symlinked into this package, so
/// its extension constant is restated here rather than imported. If the two ever diverge the
/// consequence is cosmetic — the guard above gets weaker — not a runtime bug.
private enum HomeDocumentStoreFilenameProbe {
    static let suffix = "homeplan.json"
}
