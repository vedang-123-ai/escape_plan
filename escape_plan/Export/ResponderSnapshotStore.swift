import Foundation

struct ResponderSnapshotStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var snapshotDirectory: URL {
        let caches = try! fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return caches.appendingPathComponent("ResponderSnapshots", isDirectory: true)
    }

    func clearSnapshots() {
        try? fileManager.removeItem(at: snapshotDirectory)
    }
}
