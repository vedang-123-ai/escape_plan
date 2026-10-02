//  HouseEditorSessionController+App.swift — S11.19: the app's side of House's session lifecycle.
//
//  `HouseEditorSessionController` lives in Editor/Core, which is compiled into the Foundation-only
//  editorcore package where `HomeDocumentStore`, `HomeLibrary` and `HomeDocumentSyncRepository` do
//  not exist. These two conformances are the bridge.

import Foundation

extension HomeDocumentStore: HouseEditorDocumentAccess {
    func homeFileExists(_ homeID: String) -> Bool { exists(homeID: homeID) }

    func loadHome(_ homeID: String) throws -> HomeModel { try load(homeID: homeID, as: HomeModel.self) }

    func saveHome(_ home: HomeModel) throws -> HomeModel {
        // Whole seconds: the file stores ISO-8601 without fractions, so this is the date that
        // reads back, and the returned model fingerprints the same as the file.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var stamped = home
        stamped.meta.modified = now
        try save(model: stamped, now: now)
        return stamped
    }
}

/// Tells the library and sync that House holds a home. Both are weak: the screen's session must
/// never keep the app's shared objects alive, nor they it.
@MainActor
final class HouseEditorAppRegistration: HouseEditorRegistration {
    private weak var session: EditorSession?
    private weak var library: HomeLibrary?
    private weak var syncRepository: HomeDocumentSyncRepository?

    init(session: EditorSession, library: HomeLibrary?, syncRepository: HomeDocumentSyncRepository?) {
        self.session = session
        self.library = library
        self.syncRepository = syncRepository
    }

    func registerOpenHome(_ homeID: String) {
        if let session { library?.editor = session }
        syncRepository?.openHomeID = homeID
    }

    func unregisterOpenHome(_ homeID: String) {
        if let library, let session, library.editor === session {
            library.editor = nil
        }
        if syncRepository?.openHomeID == homeID {
            syncRepository?.openHomeID = nil
        }
    }
}
