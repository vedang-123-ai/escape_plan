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
    /// Told when a home is deleted here, so cloud sync can remember it (S8.4). The backend has
    /// no delete endpoint, so without a tombstone the next sync downloads the home straight
    /// back. Weak, and optional — deleting works exactly as before with nobody listening.
    weak var deletionObserver: HomeDeletionObserving?

    init(store: HomeDocumentStore) {
        self.store = store
        refresh()
    }

    func refresh() {
        homes = store.list()
    }

    func delete(homeID: String) {
        perform {
            try store.delete(homeID: homeID)
            editor?.homeWasDeleted(homeID: homeID)
            // After the delete succeeds, so a failed delete never leaves a tombstone for a
            // home that is still on disk.
            deletionObserver?.homeWasDeletedLocally(homeID: homeID)
        }
    }

    func duplicate(homeID: String) {
        perform { _ = try store.duplicate(homeID: homeID) }
    }

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
