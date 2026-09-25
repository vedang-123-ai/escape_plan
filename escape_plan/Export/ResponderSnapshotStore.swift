import Foundation

struct ResponderSnapshotStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var snapshotDirectory: URL {
        // Caches is the right home (the system may purge it; a snapshot is re-made on demand).
        // If it cannot be resolved, fall back to the temporary directory rather than crash
        // with a `try!` (audit 2026-09-25) — the same fallback the home store uses at launch.
        let caches = (try? fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return caches.appendingPathComponent("ResponderSnapshots", isDirectory: true)
    }

    func clearSnapshots() {
        try? fileManager.removeItem(at: snapshotDirectory)
    }
}
