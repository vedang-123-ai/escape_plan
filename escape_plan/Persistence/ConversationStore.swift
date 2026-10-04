//  ConversationStore.swift
//  escape_plan — S3.3 iOS half; one conversation per home since S11.45 (AUD-033, AUD-049)
//
//  Persists the Assistant tab's conversations so they survive backgrounding and force-quit
//  (S3.3 acceptance). Modeled on HomeDocumentStore: one JSON document per home under Documents,
//  atomic writes. Distinct from the wire-format ChatMessage — the persisted message carries
//  citations, which must never be encoded into a /chat request (the server's message model is
//  `extra="forbid"`).
//
//  Before S11.45 there was ONE file for every home, so chatting about home B overwrote home A's
//  thread. Each home now has its own file, the old single file is moved to its home on first
//  launch, and nothing this store cannot read is ever overwritten or deleted: it is renamed aside.

import Foundation

/// A displayed/persisted message. `citations` is the server's id list for assistant
/// replies (empty for user messages and uncited replies).
struct AssistantMessage: Codable, Equatable, Identifiable {
    var id: UUID
    var role: ChatRole
    var content: String
    var citations: [String]

    init(id: UUID = UUID(), role: ChatRole, content: String, citations: [String] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.citations = citations
    }

    /// Wire-format projection for the /chat request history.
    var wireMessage: ChatMessage { ChatMessage(role: role, content: content) }
}

/// The persisted unit: the thread plus the id of the home it's grounded in.
struct ConversationDocument: Codable, Equatable {
    var homeID: String?
    var messages: [AssistantMessage]

    init(homeID: String? = nil, messages: [AssistantMessage] = []) {
        self.homeID = homeID
        self.messages = messages
    }
}

/// A home's saved conversation could not be read. It was renamed to `keptAt` (never overwritten
/// or deleted), and the screen starts a fresh thread and says so.
struct UnreadableConversation: LocalizedError, Equatable {
    let keptAt: URL

    var errorDescription: String? {
        "An earlier chat about this home couldn't be read, so it was kept aside and a new one started."
    }
}

/// What `migrateLegacyConversation()` did with the pre-S11.45 single file.
enum LegacyConversationMigration: Equatable {
    /// There was no old file (the usual case after the first launch).
    case nothingToMigrate
    /// Moved to its home's own file.
    case moved(homeID: String)
    /// Could not be given to a home (no home recorded, an id that cannot be a file name, a file
    /// that does not decode, or that home already has a conversation). Renamed, never deleted.
    case keptAside(URL)
}

/// FileManager-backed store, one file per home:
///
///     <Documents>/Assistant/<home_id>.json
///
/// Every path goes through `HomeID.validate` (S11.41), so a hostile id cannot name a file outside
/// the folder. Writes are atomic; a crash mid-save leaves the previous thread intact.
struct ConversationStore {
    let directory: URL
    private let fileManager: FileManager

    /// The pre-S11.45 single file, shared by every home. Only `migrateLegacyConversation()` reads it.
    var legacyFileURL: URL { directory.appendingPathComponent("\(Self.legacyStem).json") }
    private static let legacyStem = "conversation"

    init(fileManager: FileManager = .default) throws {
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent("Assistant", isDirectory: true)
        try self.init(directory: directory, fileManager: fileManager)
    }

    /// Explicit-directory init for tests/scratch use.
    init(directory: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.directory = directory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `<home_id>.json`, after `HomeID.validate`. Throws `InvalidHomeID` before any file is touched.
    /// `conversation` is refused too: its file would be the legacy file, which migration moves.
    func fileURL(for homeID: String) throws -> URL {
        try HomeID.validate(homeID)
        guard homeID != Self.legacyStem else { throw InvalidHomeID(homeID: homeID) }
        return directory.appendingPathComponent("\(homeID).json")
    }

    /// The saved thread for `homeID`, or nil when it has none. A thread about one home never
    /// resumes for another: each home reads only its own file, and a file whose recorded home
    /// disagrees with its name is treated as unreadable.
    ///
    /// Throws `UnreadableConversation` (after renaming the file aside) when the file is there but
    /// does not decode, so the next save cannot silently replace it. Any other failure (the file
    /// could not be read, or could not be moved aside) is rethrown with the file left where it is;
    /// the caller must then not save over it (AssistantScreen blocks saving for that home).
    func load(forHomeID homeID: String?) throws -> ConversationDocument? {
        // No home, or an id that cannot be a file name: there is no file this could be.
        guard let homeID, HomeID.isValid(homeID), homeID != Self.legacyStem else { return nil }
        let url = try fileURL(for: homeID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let document = try? JSONDecoder().decode(ConversationDocument.self, from: data),
              document.homeID == homeID else {
            let aside = try keepAside(url, stem: "\(homeID).unreadable")
            throw UnreadableConversation(keptAt: aside)
        }
        return document
    }

    /// Writes `document` to its home's file. Throws `InvalidHomeID` when it has no usable home id;
    /// the caller shows the failure (AUD-049: this used to be a silent `try?`).
    func save(_ document: ConversationDocument) throws {
        let url = try fileURL(for: document.homeID ?? "")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    /// "New chat": removes this home's thread only.
    func clear(homeID: String) throws {
        let url = try fileURL(for: homeID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// The home itself was deleted (`HomeLibrary.delete`): its thread goes, and so does any copy
    /// of it that was kept aside as unreadable, since both are about a home that no longer exists.
    /// Ids contain no `.`, so the `<id>.` prefix cannot match another home's files.
    /// Every file is attempted even if one fails; the first failure is then thrown.
    func deleteConversation(homeID: String) throws {
        var firstError: Error?
        do { try clear(homeID: homeID) } catch { firstError = error }
        let prefix = "\(homeID).unreadable"
        do {
            for name in try fileManager.contentsOfDirectory(atPath: directory.path) where name.hasPrefix(prefix) {
                do { try fileManager.removeItem(at: directory.appendingPathComponent(name)) } catch {
                    firstError = firstError ?? error
                }
            }
        } catch { firstError = firstError ?? error }
        if let firstError { throw firstError }
    }

    /// Moves the pre-S11.45 `conversation.json` to `<its home_id>.json`. Cheap when there is
    /// nothing to do (one existence check), so the screen calls it before every load. Never
    /// deletes the old file: whatever cannot be given to a home is renamed aside instead.
    @discardableResult
    func migrateLegacyConversation() throws -> LegacyConversationMigration {
        let legacy = legacyFileURL
        guard fileManager.fileExists(atPath: legacy.path) else { return .nothingToMigrate }
        // A failed READ is rethrown with the file left in place (it may be readable next launch);
        // only a file that was read and cannot be given to a home is renamed aside.
        let data = try Data(contentsOf: legacy)
        if let document = try? JSONDecoder().decode(ConversationDocument.self, from: data),
           let homeID = document.homeID, HomeID.isValid(homeID), homeID != Self.legacyStem {
            let target = try fileURL(for: homeID)
            if !fileManager.fileExists(atPath: target.path) {
                try fileManager.moveItem(at: legacy, to: target)
                return .moved(homeID: homeID)
            }
        }
        return .keptAside(try keepAside(legacy, stem: "conversation.unmigrated"))
    }

    /// Renames `url` to a fresh `<stem>-<uuid>.json` beside it and returns the new location.
    private func keepAside(_ url: URL, stem: String) throws -> URL {
        let aside = directory.appendingPathComponent("\(stem)-\(UUID().uuidString).json")
        try fileManager.moveItem(at: url, to: aside)
        return aside
    }
}
