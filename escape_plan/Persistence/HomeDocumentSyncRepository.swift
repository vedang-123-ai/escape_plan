//
//  HomeDocumentSyncRepository.swift
//  escape_plan — S8.4 cloud sync
//
//  The app-side half of `SyncHomeRepository`: sync's two operations, implemented over the
//  S2.4 `HomeDocumentStore`.
//
//  It lives in `Persistence/` rather than `Sync/` on purpose. `Sync/` is symlinked into the
//  `tools/editorcore` SwiftPM package so it can be tested with no simulator, which means it
//  must stay pure Foundation and must not reach into this layer. Declaring the protocol there
//  and conforming to it here keeps the dependency pointing one way.
//

import Foundation
import Observation

@Observable
@MainActor
final class HomeDocumentSyncRepository: SyncHomeRepository {

    private let store: HomeDocumentStore

    /// The Home tab's library, attached once that screen exists. Two jobs, one reference:
    /// it is refreshed after a pull so a home from another device appears without the user
    /// leaving the screen, and its `editor` is how this type knows which home is open.
    /// Weak — the screen owns it, and sync must never keep it alive.
    weak var library: HomeLibrary?

    init(store: HomeDocumentStore) {
        self.store = store
    }

    /// Every home saved on this device.
    ///
    /// A document that cannot be decoded is skipped rather than thrown, matching what
    /// `HomeDocumentStore.list()` already does for the home list: one corrupt file must not
    /// stop the other eleven homes from syncing.
    func loadAllHomes() throws -> [HomeModel] {
        store.list().compactMap { summary in
            try? store.load(homeID: summary.id, as: HomeModel.self)
        }
    }

    func writePulledHome(_ home: HomeModel) throws {
        // Never overwrite the home the user is editing. The editor holds its working copy in
        // `HomeModelStore` and writes it on autosave, so replacing the file underneath it
        // would either be discarded by the next autosave or — worse — silently reverted on
        // screen mid-edit. A home that syncs a minute later is a much better outcome than a
        // lost edit, and `SyncFailure.editorHasTheHomeOpen` says exactly that to the user.
        guard library?.editor?.openHomeID != home.home_id else {
            throw SyncFailure.editorHasTheHomeOpen
        }

        // `now:` is the whole point of this line. The default stamps `meta.modified` with the
        // CURRENT time, which would make a just-pulled home look newer than the server's copy;
        // the next sync would push it straight back, the server would increment its revision,
        // and two devices would trade the same home forever with no edit between them. Passing
        // the home's own timestamp persists it verbatim. `SyncHomeRepository` documents this
        // as a requirement of the protocol, and `SyncManagerTests` pins the behaviour.
        try store.save(model: home, now: home.meta.modified)
        library?.refresh()
    }
}
