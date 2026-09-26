//
//  HomeDocumentStore.swift
//  escape_plan — S2.4 persistence
//

import Foundation

/// FileManager-backed store for home documents.
///
/// Layout — one file per home, named by its schema `home_id`:
///
///     <Documents>/Homes/<home_id>.homeplan.json
///
/// Each file is exactly the HomeModel JSON of `schema/homemodel.schema.json`,
/// so "export" is the stored file and there is no separate index to corrupt.
/// Writes are atomic; a crash mid-save leaves the previous document intact.
struct HomeDocumentStore {
    static let fileExtension = "homeplan.json"

    let directory: URL
    private let fileManager: FileManager

    /// The app's real store: `<Documents>/Homes`.
    init(fileManager: FileManager = .default) throws {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(directory: documents.appendingPathComponent("Homes", isDirectory: true),
                      fileManager: fileManager)
    }

    /// Explicit-directory init — used by tests, and by anything that needs a
    /// scratch store.
    init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The store the app launches with, and whether it is the real one.
    ///
    /// `<Documents>/Homes` when it can be opened. When it cannot (the only way the plain init
    /// throws), a store in the temporary directory, so the app still launches and works for
    /// the session, with `isFallback` set so the UI can say plainly that nothing will be kept.
    /// Replaces two `try! HomeDocumentStore()` at launch (audit 2026-09-25), which turned an
    /// unreadable Documents directory into a crash before the first frame.
    static func launchStore(fileManager: FileManager = .default) -> (store: HomeDocumentStore, isFallback: Bool) {
        if let real = try? HomeDocumentStore(fileManager: fileManager) {
            return (real, false)
        }
        let temporary = fileManager.temporaryDirectory.appendingPathComponent("Homes", isDirectory: true)
        if let scratch = try? HomeDocumentStore(directory: temporary, fileManager: fileManager) {
            return (scratch, true)
        }
        // Not even the temporary directory could be created. Point at it anyway: `list()` reads
        // a missing directory as empty and `save` throws into the caller's own error handling,
        // which is strictly better than a launch crash.
        return (HomeDocumentStore(uncheckedDirectory: temporary, fileManager: fileManager), true)
    }

    /// A store over `directory` without creating it. Only for `launchStore`'s last resort.
    private init(uncheckedDirectory directory: URL, fileManager: FileManager) {
        self.directory = directory
        self.fileManager = fileManager
    }

    // MARK: - Read

    /// Every saved home, newest first. Unreadable files are skipped rather than
    /// failing the whole list — one bad document must not hide the others.
    func list() -> [HomeSummary] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var summaries: [HomeSummary] = []
        for url in urls where url.lastPathComponent.hasSuffix(Self.fileExtension) {
            guard let data = try? Data(contentsOf: url),
                  let document = try? HomeDocument(data: data),
                  let homeID = document.homeID
            else { continue }
            let fallback = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            summaries.append(
                HomeSummary(
                    id: homeID,
                    name: document.name ?? "Untitled Home",
                    floorCount: document.floorCount,
                    roomCount: document.roomCount,
                    modified: document.modified ?? fallback ?? .distantPast
                )
            )
        }
        return summaries.sorted { $0.modified > $1.modified }
    }

    /// Loads a home, checking `schema_version` and migrating forward if needed.
    /// A migrated document is written back so the upgrade happens once.
    func load(homeID: String) throws -> HomeDocument {
        let url = url(for: homeID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PersistenceError.homeNotFound(homeID: homeID)
        }
        let document: HomeDocument
        do {
            document = try HomeDocument(data: Data(contentsOf: url))
        } catch {
            throw PersistenceError.malformedDocument(
                homeID: homeID,
                underlying: String(describing: error)
            )
        }
        let migrated = try SchemaMigrator.migrate(document)
        if migrated != document {
            try write(migrated, to: url)
        }
        return migrated
    }

    /// Loads and decodes into a Codable HomeModel — the S2.1 entry point.
    func load<Model: Decodable>(homeID: String, as type: Model.Type) throws -> Model {
        try load(homeID: homeID).decode(as: type)
    }

    func exists(homeID: String) -> Bool {
        fileManager.fileExists(atPath: url(for: homeID).path)
    }

    // MARK: - Write

    /// Saves (creates or overwrites) a home, stamping `meta.modified`.
    @discardableResult
    func save(_ document: HomeDocument, now: Date = Date()) throws -> HomeSummary {
        guard let homeID = document.homeID else { throw PersistenceError.missingHomeID }
        guard document.schemaVersion != nil else { throw PersistenceError.missingSchemaVersion }
        let stamped = document.touched(at: now)
        try write(stamped, to: url(for: homeID))
        return HomeSummary(
            id: homeID,
            name: stamped.name ?? "Untitled Home",
            floorCount: stamped.floorCount,
            roomCount: stamped.roomCount,
            modified: stamped.modified ?? now
        )
    }

    /// Saves a Codable HomeModel — the S2.1 entry point.
    @discardableResult
    func save<Model: Encodable>(model: Model, now: Date = Date()) throws -> HomeSummary {
        try save(HomeDocument(model: model), now: now)
    }

    func delete(homeID: String) throws {
        let url = url(for: homeID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PersistenceError.homeNotFound(homeID: homeID)
        }
        try fileManager.removeItem(at: url)
    }

    /// Copies a home under a fresh `home_id`. The copy is fully independent —
    /// editing or deleting it must never touch the original.
    @discardableResult
    func duplicate(homeID: String, newName: String? = nil, now: Date = Date()) throws -> HomeSummary {
        let source = try load(homeID: homeID)
        let copyID = UUID().uuidString.lowercased()
        let copyName = newName ?? "\(source.name ?? "Untitled Home") copy"
        let copy = source.reidentified(homeID: copyID, name: copyName, modified: now)
        try write(copy, to: url(for: copyID))
        return HomeSummary(
            id: copyID,
            name: copyName,
            floorCount: copy.floorCount,
            roomCount: copy.roomCount,
            modified: now
        )
    }

    // MARK: - Export / import

    /// Writes the home's JSON to a share-ready file and returns its URL.
    /// The bytes are the stored document, so the export validates against
    /// `schema/homemodel.schema.json` by construction.
    func export(homeID: String, to directory: URL? = nil) throws -> URL {
        let document = try load(homeID: homeID)
        let target = directory ?? fileManager.temporaryDirectory
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        let url = target.appendingPathComponent("\(exportFilename(for: document)).json")
        try write(document, to: url)
        return url
    }

    /// Reads an exported/shared file back in under a fresh `home_id` — importing
    /// must not clobber a home that happens to share the source's id.
    @discardableResult
    func importDocument(from url: URL, now: Date = Date()) throws -> HomeSummary {
        let document = try HomeDocument(data: Data(contentsOf: url))
        let migrated = try SchemaMigrator.migrate(document)
        let newID = UUID().uuidString.lowercased()
        let imported = migrated.reidentified(
            homeID: newID,
            name: migrated.name ?? "Imported Home",
            modified: now
        )
        try write(imported, to: self.url(for: newID))
        return HomeSummary(
            id: newID,
            name: imported.name ?? "Imported Home",
            floorCount: imported.floorCount,
            roomCount: imported.roomCount,
            modified: now
        )
    }

    // MARK: - Paths

    func url(for homeID: String) -> URL {
        directory.appendingPathComponent("\(homeID).\(Self.fileExtension)")
    }

    /// Filesystem-safe, human-recognisable name for a shared file.
    private func exportFilename(for document: HomeDocument) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = (document.name ?? "Home")
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Home" : name
    }

    private func write(_ document: HomeDocument, to url: URL) throws {
        try document.serialized().write(to: url, options: .atomic)
    }
}
