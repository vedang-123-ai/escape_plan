import Foundation

struct ScoreCache {
    private let directory: URL

    init(fileManager: FileManager = .default) throws {
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true)
        directory = caches.appendingPathComponent("ScoreCache", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(for homeID: String) -> URL {
        directory.appendingPathComponent("\(homeID).json")
    }

    func save(_ score: ScoreBreakdown, for homeID: String) {
        do {
            let data = try HomeModel.encoder().encode(score)
            try data.write(to: file(for: homeID), options: Data.WritingOptions.atomic)
        } catch { }
    }

    func load(homeID: String) -> ScoreBreakdown? {
        do {
            let data = try Data(contentsOf: file(for: homeID))
            return try HomeModel.decoder.decode(ScoreBreakdown.self, from: data)
        } catch {
            return nil
        }
    }
}
