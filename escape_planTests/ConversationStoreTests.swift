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

    // MARK: - A thread belongs to one home (audit 2026-09-25)

    func testAThreadResumesOnlyForTheHomeItWasAbout() throws {
        let thread = ConversationDocument(homeID: "home-a",
                                          messages: [AssistantMessage(role: .user, content: "hi")])
        try store.save(thread)

        XCTAssertEqual(store.load(forHomeID: "home-a"), thread)
        XCTAssertNil(store.load(forHomeID: "home-b"),
                     "a thread about one house must not resume as if it were about another")
        XCTAssertNil(store.load(forHomeID: nil))
    }

    func testAThreadWithNoRecordedHomeIsNotAssumedToMatch() throws {
        try store.save(ConversationDocument(homeID: nil,
                                            messages: [AssistantMessage(role: .user, content: "hi")]))
        XCTAssertNil(store.load(forHomeID: "home-a"))
        XCTAssertNotNil(store.load(), "the plain load still reads it")
    }

    // MARK: - ChatError → user-facing message mapping

    /// Audit 2026-09-25: the chat client had its own copy of every failure message, which had
    /// drifted from `BackendFailure` (a 502 told the user "the server's AI isn't configured
    /// yet" where every other screen said an operator must act). Chat errors now bridge into
    /// the shared classifier, so the assistant says exactly what the rest of the app says.
    func testChatErrorsReadExactlyAsTheSharedClassifierSaysForTheAssistant() {
        let cases: [(ChatError, Int)] = [
            (.unauthorized, 401),
            (.aiUnavailable(statusCode: 502), 502),
            (.aiUnavailable(statusCode: 503), 503),
            (.unexpectedStatus(statusCode: 422, detail: "history must end with a user message"), 422),
            (.unexpectedStatus(statusCode: 429, detail: nil), 429),
        ]
        for (error, status) in cases {
            let direct = BackendFailure(APIClientError.unexpectedResponse(statusCode: status),
                                        while: .assistant)
            XCTAssertEqual(BackendFailure(error, while: .assistant), direct, "HTTP \(status)")
            XCTAssertEqual(error.errorDescription, direct.message, "HTTP \(status)")
        }
    }

    func testA502FromChatIsNotRetryableAndSaysRoutesStillWork() {
        let failure = BackendFailure(ChatError.aiUnavailable(statusCode: 502), while: .assistant)
        XCTAssertEqual(failure.kind, .aiUnavailable)
        XCTAssertFalse(failure.isRetryable, "a Retry button cannot fix an operator problem")
        XCTAssertTrue(failure.message.contains("escape routes still work"), failure.message)
    }

    /// The backend's AI cost guard answers 429; that is "busy, wait a moment", not an error.
    func testA429FromChatReadsAsBusyAndOffersRetry() {
        let failure = BackendFailure(ChatError.unexpectedStatus(statusCode: 429, detail: nil),
                                     while: .assistant)
        XCTAssertEqual(failure.kind, .serverBusy)
        XCTAssertTrue(failure.isRetryable)
    }
}
