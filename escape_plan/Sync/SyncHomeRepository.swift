//  SyncHomeRepository.swift
//  escape_plan — S8.4 cloud sync
//
//  The seam between sync and persistence.
//
//  `SyncManager` needs to read and write the user's home documents, but `Persistence/` is not
//  symlinked into the `tools/editorcore` package (it carries types that reach beyond
//  Foundation), and pulling it in would trade this layer's testability for a convenience.
//  So sync declares the two operations it actually needs, the app conforms `HomeDocumentStore`
//  to them in `Persistence/HomeDocumentSyncRepository.swift`, and the tests conform an
//  in-memory double. One protocol, two implementations, no duplicated logic.

import Foundation

@MainActor
protocol SyncHomeRepository: AnyObject {

    /// Every home saved on this device, decoded.
    ///
    /// A document that cannot be decoded must be SKIPPED, not thrown — one corrupt file must
    /// not stop the other eleven homes from syncing. `HomeDocumentStore.list()` already takes
    /// that position for the home list; this keeps sync consistent with it.
    func loadAllHomes() throws -> [HomeModel]

    /// Write a home pulled from the server over the local document.
    ///
    /// **Must persist the model verbatim, `meta.modified` included.** The obvious
    /// implementation — `store.save(model:)` — stamps `meta.modified` with the current time,
    /// which would make a just-pulled home look newer than the server's copy. The next sync
    /// would then push it straight back, the server would increment its revision, and the two
    /// devices would trade the same home forever without a single edit between them.
    func writePulledHome(_ home: HomeModel) throws

    /// Keep a copy of the local home under a NEW `home_id` before the server's version is
    /// written over it, and return that id.
    ///
    /// Only called when a pull would overwrite edits this device also has — a genuine
    /// two-sided conflict, or a home present on both sides with no record of a sync. Last
    /// write wins is a rule for deciding which copy is CANONICAL, not a licence to destroy
    /// the other one: the losing side is somebody's real work, the tiebreak is two devices'
    /// wall clocks, and the badge would otherwise report "Synced" over a silent loss.
    func preserveLocalCopy(of home: HomeModel, named name: String) throws -> String

    /// Throws the reason `writePulledHome(home)` would refuse, without writing anything.
    ///
    /// Asked BEFORE a conflict copy is made (S11.22, AUD-015). A pull that preserves first and
    /// is then refused leaves the sync record unchanged, so the next sync plans the same pull
    /// and makes another copy: with the home open in House, one more "(this device)" copy per
    /// sync, each uploaded and downloaded to every other device.
    func checkCanWritePulledHome(_ home: HomeModel) throws
}

#if DEBUG
/// Test double. Holds homes in memory, keyed by `home_id`.
final class InMemoryHomeRepository: SyncHomeRepository {
    private(set) var homes: [String: HomeModel]
    private(set) var writes: [HomeModel] = []
    private(set) var preserved: [HomeModel] = []

    /// Set to make `loadAllHomes()` throw, so the manager's "could not read the library"
    /// path is tested rather than assumed.
    var loadError: Error?

    /// The home open in House. Writes to it are refused exactly as
    /// `HomeDocumentSyncRepository.writePulledHome` refuses them (S11.22).
    var openHomeID: String?

    /// Set to make the next `writePulledHome` throw after its open-home check passes, then
    /// clear: a disk that refuses a write AFTER the conflict copy was made.
    var failNextWrite: Error?

    init(_ homes: [HomeModel] = []) {
        self.homes = Dictionary(homes.map { ($0.home_id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Runs once, just after `loadAllHomes()` has taken its snapshot: something that happens
    /// while the sync is still waiting on `GET /homes`.
    var afterLoadAllHomes: (() -> Void)?

    func loadAllHomes() throws -> [HomeModel] {
        if let loadError { throw loadError }
        let snapshot = homes.values.sorted { $0.home_id < $1.home_id }
        if let hook = afterLoadAllHomes {
            afterLoadAllHomes = nil
            hook()
        }
        return snapshot
    }

    func writePulledHome(_ home: HomeModel) throws {
        try checkCanWritePulledHome(home)
        if let failNextWrite {
            self.failNextWrite = nil
            throw failNextWrite
        }
        homes[home.home_id] = home
        writes.append(home)
    }

    func checkCanWritePulledHome(_ home: HomeModel) throws {
        guard openHomeID != home.home_id else { throw SyncFailure.editorHasTheHomeOpen }
    }

    /// The user editing a home on this device.
    func edit(_ home: HomeModel) {
        homes[home.home_id] = home
    }

    /// The user deleting a home on this device, e.g. a "(this device)" copy (S11.21).
    func delete(homeID: String) {
        homes.removeValue(forKey: homeID)
    }

    /// A fresh id per copy, as `HomeDocumentStore.duplicate` mints one. A fixed id per home made
    /// a second copy silently replace the first here, which hid AUD-015 from these tests.
    func preserveLocalCopy(of home: HomeModel, named name: String) throws -> String {
        let id = "preserved-\(home.home_id)-\(preserved.count + 1)"
        var copy = home
        copy.home_id = id
        copy.name = name
        homes[id] = copy
        preserved.append(copy)
        return id
    }
}
#endif
