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

    init(_ homes: [HomeModel] = []) {
        self.homes = Dictionary(homes.map { ($0.home_id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func loadAllHomes() throws -> [HomeModel] {
        if let loadError { throw loadError }
        return homes.values.sorted { $0.home_id < $1.home_id }
    }

    func writePulledHome(_ home: HomeModel) throws {
        homes[home.home_id] = home
        writes.append(home)
    }

    func preserveLocalCopy(of home: HomeModel, named name: String) throws -> String {
        let id = "preserved-\(home.home_id)"
        var copy = home
        copy.home_id = id
        copy.name = name
        homes[id] = copy
        preserved.append(copy)
        return id
    }
}
#endif
