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
}

#if DEBUG
/// Test double. Holds homes in memory, keyed by `home_id`.
final class InMemoryHomeRepository: SyncHomeRepository {
    private(set) var homes: [String: HomeModel]
    private(set) var writes: [HomeModel] = []

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
}
#endif
