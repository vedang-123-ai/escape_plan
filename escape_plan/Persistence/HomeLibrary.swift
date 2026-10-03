//
//  HomeLibrary.swift
//  escape_plan — S2.4 persistence
//

import Combine
import Foundation

/// The narrow seam between persistence (S2.4) and the editor (S2.1).
///
/// Conformed to by `EditorSession` (the app-side wrapper around `HomeModelStore` +
/// `UndoStack`): `EditorScreen` assigns `HomeLibrary.editor` to its session on open and
/// clears it on close, so deleting a home from the list while it is open in the editor
/// clears the editor's undo history and dismisses it.
@MainActor
protocol HomeModelPersisting: AnyObject {
    /// The home currently open in the editor, if any.
    var openHomeID: String? { get }
    /// Called by the library after a home is deleted out from under the editor.
    func homeWasDeleted(homeID: String)
}

/// Observable façade over `HomeDocumentStore` for the home-list UI.
///
/// This is the only stateful piece of S2.4; the store itself is a value type
/// with no cache, so nothing here can disagree with what is on disk.
@MainActor
final class HomeLibrary: ObservableObject {
    @Published private(set) var homes: [HomeSummary] = []
    @Published private(set) var loadError: String?

    let store: HomeDocumentStore
    /// The session of the currently open editor, if any — see `HomeModelPersisting` above.
    weak var editor: HomeModelPersisting?
    /// Told when a home is deleted here, so cloud sync can remember it (S8.4). Without a
    /// tombstone the next sync downloads the home straight back; with one owned by the signed-in
    /// account, sync also sends `DELETE /homes/{id}` (docs/decisions.md 2026-09-24). Weak, and
    /// optional — deleting works exactly as before with nobody listening.
    weak var deletionObserver: HomeDeletionObserving?

    init(store: HomeDocumentStore) {
        self.store = store
        refresh()
    }

    func refresh() {
        homes = store.list()
    }

    /// Returns false when the file could not be deleted (the reason is in `loadError`). Returns
    /// true with `loadError` set when the file went but its deletion could not be remembered.
    @discardableResult
    func delete(homeID: String) -> Bool {
        var deleted = false
        perform {
            try store.delete(homeID: homeID)
            deleted = true
            editor?.homeWasDeleted(homeID: homeID)
            // After the delete succeeds, so a failed delete never leaves a tombstone for a
            // home that is still on disk. A tombstone that will not save lands in `loadError`
            // while `deleted` stays true: the file is gone either way (S11.22).
            try deletionObserver?.homeWasDeletedLocally(homeID: homeID)
        }
        return deleted
    }

    /// Copies a home under a new id and the name "<name> copy". Returns the copy's id, or nil when
    /// it failed (the reason is in `loadError`).
    ///
    /// Only the home document is copied: household profiles live inside it and come along, but the
    /// checklist ticks, drill log and meeting point are keyed by home id and start empty, because
    /// they are things someone did or decided about the original (docs/decisions.md 2026-10-02).
    @discardableResult
    func duplicate(homeID: String) -> String? {
        var copyID: String?
        perform { copyID = try store.duplicate(homeID: homeID).id }
        return copyID
    }

    /// The bundled starter homes (`FixtureSeeder`), which keep their fixtures' fixed ids. Labelled
    /// "Demo" in the home list. A duplicate gets a new id, so it is the user's own home, not a demo.
    static let starterHomeIDs: Set<String> = Set(HomeFixture.allCases.compactMap {
        try? FixtureLoader.load($0).home_id
    })

    static func isStarterHome(_ homeID: String) -> Bool { starterHomeIDs.contains(homeID) }

    func export(homeID: String) -> URL? {
        var url: URL?
        perform { url = try store.export(homeID: homeID) }
        return url
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
        }
        refresh()
    }
}
