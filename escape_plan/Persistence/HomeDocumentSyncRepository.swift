//
//  HomeDocumentSyncRepository.swift
//  escape_plan — S8.4 cloud sync
//
//  The app-side half of `SyncHomeRepository`: sync's operations, implemented over the S2.4
//  `HomeDocumentStore`.
//
//  It lives in `Persistence/` rather than `Sync/` on purpose. `Sync/` is symlinked into the
//  `tools/editorcore` SwiftPM package so it can be tested with no simulator, which means it
//  must stay pure Foundation and must not reach into this layer. Declaring the protocol there
//  and conforming to it here keeps the dependency pointing one way.
//
//  **This type is NOT covered by `swift test`** — `Persistence/` is not symlinked into the
//  package, so `SyncManagerTests` exercises `InMemoryHomeRepository` and says nothing about
//  the code below. `escape_planTests/HomeDocumentSyncRepositoryTests.swift` covers it and has
//  never executed; see `docs/tracker/FIRST-PRIORITY.md`.
//

import Foundation
import Observation

/// Told when a home is deleted on this device, so the deletion can be remembered.
///
/// The backend has no delete endpoint, so without this the next sync downloads the deleted
/// home straight back and it reappears in the library.
@MainActor
protocol HomeDeletionObserving: AnyObject {
    func homeWasDeletedLocally(homeID: String)
}

@Observable
@MainActor
final class HomeDocumentSyncRepository: SyncHomeRepository, HomeDeletionObserving {

    private let store: HomeDocumentStore
    private let stateStore: SyncStateStore

    /// The home currently open in the editor, or nil.
    ///
    /// App-scoped and set by House's session (`HouseEditorAppRegistration`, S11.19) on EVERY
    /// appear, cleared on every disappear. While House is visible with a live session, this
    /// names its home and `writePulledHome` refuses it; while House is away, a pull may land, and
    /// the next appear reloads it instead of autosaving over it.
    /// An earlier version resolved this through `HomeLibrary.editor`, which was wrong: the
    /// editor is reachable from three places with three different `HomeLibrary` instances, and
    /// the House tab's own entry point constructs itself with `library: nil`. So for two of the
    /// three entry points the guard read `nil` and passed, and sync wrote the server's copy
    /// over the file the editor was autosaving from.
    var openHomeID: String?

    /// The library to refresh after a pull, so a home from another device appears without the
    /// user leaving the screen. Weak — the screen owns it, and sync must never keep it alive.
    weak var library: HomeLibrary?

    /// Home ids whose document exists on disk but could not be decoded on the last
    /// `loadAllHomes()`. They are invisible to the reconciler, which would otherwise read them
    /// as "absent locally" and happily write the server's copy over a file that may be one
    /// migration away from being readable. See `writePulledHome`.
    private var undecodableHomeIDs: Set<String> = []

    init(store: HomeDocumentStore, stateStore: SyncStateStore) {
        self.store = store
        self.stateStore = stateStore
    }

    // MARK: - Reading

    /// Every home saved on this device.
    ///
    /// A single document that cannot be decoded is skipped rather than thrown — one corrupt
    /// file must not stop the other eleven homes from syncing, which is the position
    /// `HomeDocumentStore.list()` already takes for the home list. But the id is REMEMBERED,
    /// because "skipped" and "not on this device" mean very different things to sync.
    ///
    /// The directory being unreadable is a different matter and does throw: that is not one
    /// bad home, it is no library at all, and syncing an apparently empty device against an
    /// account full of homes would download everything over nothing.
    func loadAllHomes() throws -> [HomeModel] {
        guard FileManager.default.fileExists(atPath: store.directory.path) else {
            throw PersistenceError.malformedDocument(
                homeID: "<library>",
                underlying: "the Homes directory could not be read")
        }
        let summaries = store.list()
        var homes: [HomeModel] = []
        var undecodable: Set<String> = []
        for summary in summaries {
            if let home = try? store.load(homeID: summary.id, as: HomeModel.self) {
                homes.append(home)
            } else {
                undecodable.insert(summary.id)
            }
        }
        undecodableHomeIDs = undecodable
        return homes
    }

    // MARK: - Writing

    func writePulledHome(_ home: HomeModel) throws {
        // Never overwrite the home the user is editing. The editor holds its working copy in
        // `HomeModelStore` and writes it on autosave, so replacing the file underneath it
        // would either be discarded by the next autosave or — worse — silently reverted on
        // screen mid-edit. A home that syncs a minute later beats a lost edit.
        guard openHomeID != home.home_id, library?.editor?.openHomeID != home.home_id else {
            throw SyncFailure.editorHasTheHomeOpen
        }

        // A document that exists but did not decode is not an absent home. Writing the
        // server's copy over it would destroy whatever is in there — possibly a home that a
        // future `SchemaMigrator` can read, possibly a partial write that is about to be
        // completed. Refuse, loudly, and leave the file alone.
        guard !undecodableHomeIDs.contains(home.home_id) else {
            throw SyncFailure.localCopyUnreadable
        }

        // `now:` is the whole point of this line. The default stamps `meta.modified` with the
        // CURRENT time, which would make a just-pulled home look newer than the server's copy;
        // the next sync would push it straight back, the server would increment its revision,
        // and two devices would trade the same home forever with no edit between them.
        // Passing the home's own timestamp persists it verbatim.
        try store.save(model: home, now: home.meta.modified)
        library?.refresh()
    }

    /// Copies the local home under a fresh `home_id` before the server's version replaces it.
    /// Reuses `HomeDocumentStore.duplicate`, which already guarantees the copy is fully
    /// independent of the original.
    func preserveLocalCopy(of home: HomeModel, named name: String) throws -> String {
        let copy = try store.duplicate(homeID: home.home_id, newName: name)
        library?.refresh()
        return copy.id
    }

    // MARK: - Deletion

    /// Writes a tombstone so the next sync does not download the home straight back.
    ///
    /// Best-effort: a sidecar that will not write is not worth failing a deletion over — the
    /// home is already gone from disk. The cost is that it may reappear once.
    func homeWasDeletedLocally(homeID: String) {
        var state = stateStore.load()
        // `markDeleted` reads the home's owner out of the state itself, so the tombstone is
        // scoped to the account the home belonged to rather than suppressing it for everyone.
        state.markDeleted(localHomeID: homeID, at: Date())
        try? stateStore.save(state)
    }
}
