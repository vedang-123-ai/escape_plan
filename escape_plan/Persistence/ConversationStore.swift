//  ConversationStore.swift
//  escape_plan — S3.3 iOS half
//
//  Persists the Assistant tab's single conversation so it survives backgrounding and
//  force-quit (S3.3 acceptance). Modeled on HomeDocumentStore: one JSON document under
//  Documents, atomic writes. Distinct from the wire-format ChatMessage — the persisted
//  message carries citations, which must never be encoded into a /chat request
//  (the server's message model is `extra="forbid"`).

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

/// FileManager-backed store for the conversation document:
///
///     <Documents>/Assistant/conversation.json
///
/// Writes are atomic; a crash mid-save leaves the previous thread intact. Load failures
/// return nil (a fresh conversation) rather than throwing — a corrupt chat log must
/// never block the screen.
struct ConversationStore {
    let fileURL: URL
    private let fileManager: FileManager

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
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("conversation.json")
    }

    func load() -> ConversationDocument? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ConversationDocument.self, from: data)
    }

    func save(_ document: ConversationDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
