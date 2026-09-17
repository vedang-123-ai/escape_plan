//  SyncPreviewSupport.swift
//  escape_plan — S8.4 cloud sync
//
//  Environment values for SwiftUI previews, so a `#Preview` that renders a screen carrying the
//  sync badge does not have to assemble a client, a repository and a sidecar by hand.
//
//  DEBUG-only, like the token-store doubles in `Auth/TokenStore.swift` and for the same reason:
//  a preview must never touch the real Keychain, the real Documents directory or the network,
//  and none of this may ship in a release binary.

#if DEBUG
import Foundation
import SwiftUI

extension SyncManager {
    /// A manager with no token. It reports `.signedOut` forever and cannot make a request, so
    /// a preview renders the badge's quiet state without any I/O at all.
    static func previewSignedOut() -> SyncManager {
        SyncManager(client: CloudHomesClient(baseURL: APIClient.deployedDefaultBaseURL),
                    repository: InMemoryHomeRepository(),
                    stateStore: InMemorySyncStateStore(),
                    tokenProvider: { nil })
    }
}

extension HomeDocumentSyncRepository {
    /// A repository over a throwaway directory. Never the app's real `<Documents>/Homes`.
    static func preview() -> HomeDocumentSyncRepository {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-homes-\(UUID().uuidString)", isDirectory: true)
        // `try!` is confined to DEBUG preview code: a temporary directory that cannot be
        // created means the preview host is broken, and there is nothing useful to fall back to.
        return HomeDocumentSyncRepository(store: try! HomeDocumentStore(directory: scratch))
    }
}

extension View {
    /// Everything S8.4 puts in the environment, for a preview.
    func previewSyncEnvironment() -> some View {
        environment(SyncManager.previewSignedOut())
            .environment(HomeDocumentSyncRepository.preview())
    }
}
#endif
