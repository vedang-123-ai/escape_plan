//  ConversationStoreTests.swift
//  escape_planTests
//
//  S3.3's conversation persistence beyond the basic round-trip already covered in
//  ChatRequestEncodingTests: the corrupt-file fresh-conversation contract, relaunch
//  survival (the store half of the "survives backgrounding" acceptance), the
//  append-and-resave pattern AssistantScreen uses after every message, and the ChatError
//  messages the screen shows when /chat fails. All against a temp directory per test.

import XCTest
@testable import escape_plan

final class ConversationStoreTests: XCTestCase {

    private var directory: URL!
    private var store: ConversationStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationStoreTests-\(UUID().uuidString)")
        store = try ConversationStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeThread() -> ConversationDocument {
        ConversationDocument(
            homeID: "home-1",
            messages: [
                AssistantMessage(role: .user, content: "Is my smoke alarm coverage okay?"),
                AssistantMessage(role: .assistant,
                                 content: "Add one on floor 2 [cite: nfpa-alarms].",
                                 citations: ["nfpa-alarms"]),
            ])
    }

    // MARK: - Corrupt-file contract

    func testCorruptFileLoadsAsNilAndSaveRecovers() throws {
        try Data("{ this is not JSON".utf8).write(to: store.fileURL)
        XCTAssertNil(store.load(),
                     "a corrupt chat log must yield a fresh conversation, never a blocked screen")

        // Valid JSON of the wrong shape is equally corrupt from the store's point of view.
        try Data(#"{"messages": "should be an array"}"#.utf8).write(to: store.fileURL)
        XCTAssertNil(store.load())

        let thread = makeThread()
        try store.save(thread)
        XCTAssertEqual(store.load(), thread, "saving over a corrupt file must fully recover")
    }

    // MARK: - Relaunch / backgrounding survival

    func testThreadSurvivesRelaunchExactly() throws {
        let thread = makeThread()
        try store.save(thread)

        // A brand-new store over the same directory is the unit-level relaunch: nothing
        // shared with the first instance but the file it wrote on backgrounding.
        let relaunched = try ConversationStore(directory: directory)
        let loaded = try XCTUnwrap(relaunched.load())
        XCTAssertEqual(loaded, thread)
        XCTAssertEqual(loaded.messages.map(\.id), thread.messages.map(\.id),
                       "message identity must survive, or SwiftUI list state scrambles on relaunch")
        XCTAssertEqual(loaded.messages.last?.citations, ["nfpa-alarms"],
                       "citation chips must come back after relaunch")
    }

    func testReinitializingOverAnExistingDirectoryKeepsTheFile() throws {
        try store.save(makeThread())
        // The init's createDirectory runs again over an existing directory — it must not
        // truncate or replace what's already there.
        _ = try ConversationStore(directory: directory)
        XCTAssertNotNil(store.load())
    }

    // MARK: - Append-and-resave (AssistantScreen's per-message pattern)

    func testIncrementalResavesAccumulateTheWholeThread() throws {
        var document = ConversationDocument(homeID: "home-1")
        for turn in 0..<5 {
            document.messages.append(AssistantMessage(role: .user, content: "Question \(turn)"))
            try store.save(document)
            document.messages.append(AssistantMessage(role: .assistant, content: "Answer \(turn)"))
            try store.save(document)
        }

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.messages.count, 10)
        XCTAssertEqual(loaded.messages.map(\.content).prefix(2), ["Question 0", "Answer 0"],
                       "order must be preserved across every resave")
    }

    // MARK: - clear()

    func testClearWithNoFileDoesNotThrowAndSaveStillWorksAfter() throws {
        XCTAssertNoThrow(try store.clear(), "clearing an empty conversation is a no-op, not an error")

        try store.save(makeThread())
        try store.clear()
        XCTAssertNil(store.load())

        let fresh = ConversationDocument(homeID: "home-2")
        try store.save(fresh)
        XCTAssertEqual(store.load(), fresh, "New Chat must work immediately after a clear")
    }

    // MARK: - AssistantMessage persistence shape

    func testAssistantMessageRoundTripKeepsIdentityAndCitations() throws {
        let message = AssistantMessage(role: .assistant,
                                       content: "Close doors behind you [cite: nfpa-escape-planning].",
                                       citations: ["nfpa-escape-planning"])
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AssistantMessage.self, from: data)
        XCTAssertEqual(decoded, message, "persisted messages keep id + citations (unlike wireMessage)")
    }

    // MARK: - ChatError → user-facing message mapping

    func testChatErrorMessagesMatchWhatTheScreenShows() {
        XCTAssertEqual(ChatError.unauthorized.errorDescription,
                       "The server didn't accept the access token — check it in Settings.")

        let unavailable = ChatError.aiUnavailable(statusCode: 500).errorDescription ?? ""
        XCTAssertTrue(unavailable.contains("assistant is unavailable"),
                      "5xx must read as 'assistant down', not a raw status code: \(unavailable)")
        XCTAssertTrue(unavailable.contains("House tab still work"),
                      "the message must reassure that deterministic routes are unaffected")

        XCTAssertEqual(ChatError.unexpectedStatus(statusCode: 422, detail: "history must end with a user message").errorDescription,
                       "The assistant request failed (HTTP 422): history must end with a user message.")
        XCTAssertEqual(ChatError.unexpectedStatus(statusCode: 418, detail: nil).errorDescription,
                       "The assistant request failed (HTTP 418).")
    }
}
