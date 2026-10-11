//
//  HomeDocumentStore.swift
//  escape_plan — S2.4 persistence
//

import Foundation
import os

/// FileManager-backed store for home documents.
///
/// Layout — one file per home, named by its schema `home_id`:
///
///     <Documents>/Homes/<home_id>.homeplan.json
///
/// Each file is exactly the HomeModel JSON of `schema/homemodel.schema.json`,
/// so "export" is the stored file and there is no separate index to corrupt.
/// Writes are atomic; a crash mid-save leaves the previous document intact.
///
/// Every id is checked by `HomeID.isValid` before it becomes a path (S11.41, AUD-012): ids come
/// from the server and from hand-editable files, and `../` would otherwise leave the directory.
struct HomeDocumentStore {
    static let fileExtension = "homeplan.json"

    private static let log = Logger(subsystem: "escape_plan", category: "HomeDocumentStore")

    let directory: URL
    let fileManager: FileManager

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
    ///
    /// Listed by FILE NAME, because that is what `load(homeID:)` opens (S11.41, AUD-012). A file
    /// whose name is not a valid id, or whose embedded `home_id` differs from its name (renamed or
    /// hand-edited in Files), is logged and skipped rather than listed as a home that then fails
    /// to open. Case is ignored in that comparison (see below). Not repaired: rewriting the embedded id would change the home's identity for sync
    /// and could collide with another file's home. The file is left on disk untouched.
    func list() -> [HomeSummary] {
        summaries(reusing: [:]).summaries
    }

    /// What `summaries(reusing:)` remembers about one file: the file's identity on disk (change
    /// time and size) and the row it produced, or nil when the file's CONTENTS make it skipped
    /// (not a HomeModel, mismatched `home_id`). Such files are remembered so they are not re-read
    /// on every refresh. A file that could not be read at all is never remembered.
    struct SummaryEntry: Equatable, Sendable {
        let modificationDate: Date?
        let fileSize: Int?
        let summary: HomeSummary?
    }

    /// The listing plus what it learned. `entries` is handed back in as `known` next time, so only
    /// files whose change time or size moved are read again (AUD-047, S11.48). `filesRead` is how
    /// many that was.
    struct Listing: Sendable {
        let summaries: [HomeSummary]
        let entries: [String: SummaryEntry]
        let filesRead: Int
    }

    /// `list()`, reading again only the files that changed since `known` was produced.
    ///
    /// Same rules as `list()`: by file name, invalid ids skipped, a mismatched `home_id` skipped,
    /// newest first. A file that is gone is dropped from `entries`, so a deleted home cannot come
    /// back from a stale cache.
    func summaries(reusing known: [String: SummaryEntry]) -> Listing {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var entries: [String: SummaryEntry] = [:]
        var filesRead = 0
        let suffix = ".\(Self.fileExtension)"
        for url in urls where url.lastPathComponent.hasSuffix(suffix) {
            let homeID = String(url.lastPathComponent.dropLast(suffix.count))
            guard HomeID.isValid(homeID) else {
                Self.log.error("Skipped a home file whose name is not a valid home id.")
                continue
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modificationDate = values?.contentModificationDate
            let fileSize = values?.fileSize
            // Only a file we could stat both ways is trusted as unchanged: without a change time
            // there is nothing to compare, so it is read every time, as before.
            if let previous = known[homeID], modificationDate != nil, fileSize != nil,
               previous.modificationDate == modificationDate, previous.fileSize == fileSize {
                entries[homeID] = previous
                continue
            }
            filesRead += 1
            // A file that cannot be read at all (locked, a read racing a write) is not remembered,
            // so the next refresh tries it again. Only a verdict about the contents is cached.
            guard let data = try? Data(contentsOf: url) else { continue }
            entries[homeID] = SummaryEntry(
                modificationDate: modificationDate,
                fileSize: fileSize,
                summary: Self.readSummary(data, homeID: homeID, fallbackModified: modificationDate)
            )
        }
        // Ties (two homes stamped the same second) fall back to the id, so the order is the same on
        // every refresh instead of following the directory's enumeration order.
        let summaries = entries.values.compactMap(\.summary).sorted {
            $0.modified != $1.modified ? $0.modified > $1.modified : $0.id < $1.id
        }
        return Listing(summaries: summaries, entries: entries, filesRead: filesRead)
    }

    /// One row, from a light decode of one file: only `home_id`, `name`, `floors[].rooms` and
    /// `meta.modified` are materialised, not the whole document tree (which is most of what
    /// `list()` used to spend, since it built every home's full `JSONValue`).
    private static func readSummary(_ data: Data, homeID: String, fallbackModified: Date?) -> HomeSummary? {
        guard let probe = try? JSONDecoder().decode(SummaryProbe.self, from: data) else { return nil }
        // Case-insensitive: the simulator's (and a Mac's) volume is, so a pull of `ABC…`
        // over `abc….homeplan.json` can leave the old name on the new contents. Listing the
        // file name keeps it openable, since `load` opens by name.
        guard let embedded = probe.homeID,
              embedded.caseInsensitiveCompare(homeID) == .orderedSame else {
            log.error("Skipped home file \(homeID, privacy: .public): its home_id does not match its name.")
            return nil
        }
        return HomeSummary(
            id: homeID,
            name: probe.name ?? "Untitled Home",
            floorCount: probe.floorCount,
            roomCount: probe.roomCount,
            modified: probe.modified ?? fallbackModified ?? .distantPast
        )
    }

    /// Loads a home, checking `schema_version` and migrating forward if needed.
    /// A migrated document is written back so the upgrade happens once.
    func load(homeID: String) throws -> HomeDocument {
        let url = try checkedURL(for: homeID)
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
        guard let url = try? checkedURL(for: homeID) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    // MARK: - Write

    /// Saves (creates or overwrites) a home, stamping `meta.modified`.
    @discardableResult
    func save(_ document: HomeDocument, now: Date = Date()) throws -> HomeSummary {
        guard let homeID = document.homeID else { throw PersistenceError.missingHomeID }
        guard document.schemaVersion != nil else { throw PersistenceError.missingSchemaVersion }
        let target = try checkedURL(for: homeID)
        let stamped = document.touched(at: now)
        try write(stamped, to: target)
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
        let url = try checkedURL(for: homeID)
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
        try write(copy, to: checkedURL(for: copyID))
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
        try write(imported, to: checkedURL(for: newID))
        return HomeSummary(
            id: newID,
            name: imported.name ?? "Imported Home",
            floorCount: imported.floorCount,
            roomCount: imported.roomCount,
            modified: now
        )
    }

    // MARK: - Paths

    /// Where `homeID` is stored. Every read and write in this type goes through
    /// `checkedURL(for:)`, which refuses an invalid id; this non-throwing form stays for callers
    /// that only inspect paths. It still cannot leave the directory: an invalid id is
    /// percent-escaped, so `/` and `.` become `%2F` and `%2E` and the result is one file name
    /// inside `directory`, which this store never writes to.
    func url(for homeID: String) -> URL {
        let name = HomeID.isValid(homeID)
            ? homeID
            : homeID.addingPercentEncoding(withAllowedCharacters: Self.idCharacters) ?? "%"
        return directory.appendingPathComponent("\(name).\(Self.fileExtension)")
    }

    private static let idCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    /// `url(for:)`, after `HomeID.validate`. Throws `InvalidHomeID` before any file is touched.
    private func checkedURL(for homeID: String) throws -> URL {
        try HomeID.validate(homeID)
        return url(for: homeID)
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

/// The few fields a library row needs, decoded without building the document tree. Every field is
/// lenient the same way `HomeDocument`'s accessors are: a value of the wrong type reads as absent.
private struct SummaryProbe: Decodable {
    let homeID: String?
    let name: String?
    let floorCount: Int
    let roomCount: Int
    let modified: Date?

    private enum Keys: String, CodingKey { case home_id, name, floors, meta }
    private enum MetaKeys: String, CodingKey { case modified }
    private enum FloorKeys: String, CodingKey { case rooms }

    /// Accepts any JSON value without keeping it.
    private struct Skipped: Decodable { init(from decoder: Decoder) throws {} }

    /// A floor, reduced to its room count. Never throws, so one malformed floor counts as zero
    /// rooms instead of failing the whole array.
    private struct Floor: Decodable {
        let rooms: Int
        init(from decoder: Decoder) {
            let keyed = try? decoder.container(keyedBy: FloorKeys.self)
            rooms = (keyed.flatMap { try? $0.decode([Skipped].self, forKey: .rooms) })?.count ?? 0
        }
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Keys.self)
        homeID = try? root.decode(String.self, forKey: .home_id)
        name = try? root.decode(String.self, forKey: .name)
        let floors = (try? root.decode([Floor].self, forKey: .floors)) ?? []
        floorCount = floors.count
        roomCount = floors.reduce(0) { $0 + $1.rooms }
        let meta = try? root.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta)
        modified = (meta.flatMap { try? $0.decode(String.self, forKey: .modified) })
            .flatMap(ISO8601DateFormatter.parseHomeModelDate)
    }
}
