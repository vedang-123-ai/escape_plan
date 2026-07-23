//  EditorSession.swift — the app-side lifetime wrapper around one open home.
//
//  Bundles the pure editor core (`HomeModelStore` + `UndoStack`) with the one piece of app
//  lifecycle the core must not know about: what happens when the edited home is deleted out
//  from under the editor (`HomeLibrary.delete` → `HomeModelPersisting.homeWasDeleted`). The
//  undo history is dropped — its snapshots describe a document that no longer exists — and
//  `wasDeletedExternally` flips so `EditorScreen` can dismiss itself.
//
//  This is the conformer the `HomeModelPersisting` seam waited for since S2.4 (see the doc
//  comment in Persistence/HomeLibrary.swift). `EditorScreen` assigns `HomeLibrary.editor` to
//  its session on open and clears it on close.

import Foundation
import Observation

@MainActor
@Observable
final class EditorSession {

    let store: HomeModelStore
    let undoStack = UndoStack()

    /// Set when the open home is deleted from the home list while this editor holds it.
    /// `EditorScreen` observes it and dismisses.
    private(set) var wasDeletedExternally = false

    init(store: HomeModelStore) {
        self.store = store
    }
}

extension EditorSession: HomeModelPersisting {

    var openHomeID: String? { store.model.home_id }

    func homeWasDeleted(homeID: String) {
        guard homeID == store.model.home_id else { return }
        undoStack.reset()
        wasDeletedExternally = true
    }
}
