//
//  HomeLibrary.swift
//  escape_plan — S2.4 persistence
//

import Combine
import Foundation

/// The narrow seam between persistence (S2.4) and the editor's store (S2.1).
///
/// TODO(integration) — S2.1's `HomeModelStore` should conform to this and call
/// `HomeLibrary` for all disk access; persistence deliberately knows nothing
/// about the store, undo/redo, or SwiftUI. When `HomeModel` lands:
///
///   1. Have `HomeModelStore` call `store.save(model:)` on autosave and
///      `store.load(homeID:as: HomeModel.self)` on open — both generic entry
///      points already exist on `HomeDocumentStore`.
///   2. Set `HomeLibrary.editor` to the store so a home deleted from the list
///      closes the editor and clears its undo history.
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
    /// TODO(integration) — set by S2.1's store once it exists.
    weak var editor: HomeModelPersisting?

    init(store: HomeDocumentStore) {
        self.store = store
        refresh()
    }

    /// Convenience init against the app's real Documents directory.
    convenience init() throws {
        self.init(store: try HomeDocumentStore())
    }

    func refresh() {
        homes = store.list()
    }

    func delete(homeID: String) {
        perform {
            try store.delete(homeID: homeID)
            editor?.homeWasDeleted(homeID: homeID)
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
