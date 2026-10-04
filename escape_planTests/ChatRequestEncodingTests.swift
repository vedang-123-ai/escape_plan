//  ChatRequestEncodingTests.swift
//  escape_planTests
//
//  S3.3 iOS half: guards the /chat wire contract. The backend's request models are
//  pydantic `extra="forbid"`, so the encoded JSON must carry exactly the allowed keys —
//  an accidental extra field (e.g. a persisted message's id/citations leaking into the
//  wire type) would turn every chat call into a 422.

import XCTest
@testable import escape_plan

final class ChatRequestEncodingTests: XCTestCase {

    func testRequestEncodesExactlyTheAllowedKeys() throws {
        let home = try FixtureLoader.load(.twostory)
        let request = ChatRequest(
            home: home,
            messages: [
                ChatMessage(role: .assistant, content: "Hello!"),
                ChatMessage(role: .user, content: "Is my smoke alarm coverage okay?"),
            ]
        )

        let data = try HomeModel.encoder().encode(request)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["home", "messages"],
                       "extra top-level keys would be rejected by the server (extra=forbid)")

        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        for message in messages {
            XCTAssertEqual(Set(message.keys), ["role", "content"],
                           "extra message keys would be rejected by the server (extra=forbid)")
        }
        XCTAssertEqual(messages.last?["role"] as? String, "user",
                       "the server requires the history to end with a user message")
    }

    func testAssistantMessageProjectsToWireFormatWithoutCitations() throws {
        let assistant = AssistantMessage(
            role: .assistant,
            content: "Test alarms monthly [cite: nfpa-escape-planning].",
            citations: ["nfpa-escape-planning"]
        )
        let wire = assistant.wireMessage
        XCTAssertEqual(wire, ChatMessage(role: .assistant,
                                         content: assistant.content))
    }

    func testChatResponseDecodes() throws {
        let json = #"{"reply": "Yes [cite: nfpa-escape-planning].", "citations": ["nfpa-escape-planning"]}"#
        let response = try JSONDecoder().decode(ChatResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.reply, "Yes [cite: nfpa-escape-planning].")
        XCTAssertEqual(response.citations, ["nfpa-escape-planning"])
    }

    func testConversationDocumentRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatRequestEncodingTests-\(UUID().uuidString)")
        let store = try ConversationStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(try store.load(forHomeID: "home-1"))

        let document = ConversationDocument(
            homeID: "home-1",
            messages: [
                AssistantMessage(role: .user, content: "Hi"),
                AssistantMessage(role: .assistant, content: "Hello [cite: x].", citations: ["x"]),
            ]
        )
        try store.save(document)
        XCTAssertEqual(try store.load(forHomeID: "home-1"), document)

        try store.clear(homeID: "home-1")
        XCTAssertNil(try store.load(forHomeID: "home-1"))
    }

    // MARK: - History trimming (S11.45, AUD-033)

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // escape_planTests/
        .deletingLastPathComponent()  // repo root

    /// The client's caps are the server's caps, read from the server's own file, so a change to
    /// either side without the other fails here instead of as a 422 on a long conversation.
    func testCapsEqualTheServersDocumentedLimits() throws {
        let limits = try String(contentsOf: Self.repoRoot.appendingPathComponent("backend/app/limits.py"),
                                encoding: .utf8)
        func serverValue(_ name: String) throws -> Int {
            let pattern = try NSRegularExpression(pattern: "^\(name) = ([0-9_]+)$", options: .anchorsMatchLines)
            let match = try XCTUnwrap(pattern.firstMatch(in: limits, range: NSRange(limits.startIndex..., in: limits)),
                                      "\(name) not found in backend/app/limits.py")
            let digits = String(limits[Range(match.range(at: 1), in: limits)!]).replacingOccurrences(of: "_", with: "")
            return try XCTUnwrap(Int(digits))
        }
        XCTAssertEqual(ChatHistory.maxMessages, try serverValue("MAX_CHAT_MESSAGES"))
        XCTAssertEqual(ChatHistory.maxMessageChars, try serverValue("MAX_CHAT_MESSAGE_CHARS"))
        XCTAssertEqual(ChatHistory.maxTotalChars, try serverValue("MAX_CHAT_TOTAL_CHARS"))
    }

    /// Alternating user/assistant turns ending on a user turn, each `length` characters.
    private func thread(_ count: Int, length: Int = 10) -> [ChatMessage] {
        (0..<count).map { index in
            let role: ChatRole = (count - 1 - index).isMultiple(of: 2) ? .user : .assistant
            let tag = "\(index):"
            return ChatMessage(role: role, content: tag + String(repeating: "x", count: max(0, length - tag.count)))
        }
    }

    /// Everything the server checks (api_chat.py ChatRequest, service.py ChatMessage), in one place.
    private func assertWithinServerCaps(_ sent: [ChatMessage], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(sent.isEmpty, file: file, line: line)
        XCTAssertLessThanOrEqual(sent.count, ChatHistory.maxMessages, file: file, line: line)
        XCTAssertLessThanOrEqual(sent.map { ChatHistory.characterCount($0.content) }.reduce(0, +),
                                 ChatHistory.maxTotalChars, file: file, line: line)
        XCTAssertEqual(sent.last?.role, .user, "the server requires a final user turn", file: file, line: line)
        XCTAssertEqual(sent.first?.role, .user, "a trimmed request opens with the user", file: file, line: line)
    }

    func testAShortThreadIsSentWhole() {
        let history = thread(7)
        let trimmed = ChatHistory.trimmed(history)
        XCTAssertEqual(trimmed.messages, history)
        XCTAssertEqual(trimmed.omittedCount, 0)
    }

    func testALongThreadSendsOnlyTheMostRecentTurnsWithinTheCountCap() {
        let history = thread(101)
        let trimmed = ChatHistory.trimmed(history)
        assertWithinServerCaps(trimmed.messages)
        XCTAssertEqual(trimmed.messages.count, 39, "40 would open on an assistant turn, so one more goes")
        XCTAssertEqual(Array(history.suffix(trimmed.messages.count)), trimmed.messages,
                       "the newest turns, in order, with no gap")
        XCTAssertEqual(trimmed.omittedCount, 101 - 39)
    }

    func testTheTotalCharacterCapBindsBeforeTheCount() {
        let history = thread(30, length: 7_000)  // 210k characters, far over 100k
        let trimmed = ChatHistory.trimmed(history)
        assertWithinServerCaps(trimmed.messages)
        XCTAssertEqual(trimmed.messages.count, 13, "14 x 7,000 = 98,000 fits; 14 opens on an assistant turn")
        XCTAssertEqual(trimmed.omittedCount, 17)
    }

    func testAnOverlongEarlierTurnEndsTheRunRatherThanLeavingAHole() {
        var history = thread(9)
        history[3].content = String(repeating: "y", count: ChatHistory.maxMessageChars + 1)
        let trimmed = ChatHistory.trimmed(history)
        assertWithinServerCaps(trimmed.messages)
        XCTAssertEqual(trimmed.messages, Array(history.suffix(5)),
                       "turns 4-8 are sent; the overlong turn 3 and everything before it are not")
    }

    func testTheUsersFinalQuestionIsAlwaysSent() {
        var history = thread(5)
        history[4].content = String(repeating: "z", count: ChatHistory.maxTotalChars + 5)
        let trimmed = ChatHistory.trimmed(history)
        XCTAssertEqual(trimmed.messages, [history[4]],
                       "never drop the question just asked; the server's 422 explains an oversize one")
        XCTAssertEqual(trimmed.omittedCount, 4)
    }

    /// Python's len() counts Unicode scalars. A flag is one Swift Character but two scalars.
    func testCharactersAreCountedTheWayTheServerCountsThem() {
        XCTAssertEqual(ChatHistory.characterCount("🇺🇸"), 2)
        XCTAssertEqual(ChatHistory.characterCount("é"), 1)
        let flag = "🇺🇸"
        let history = [ChatMessage(role: .user, content: String(repeating: flag, count: 30_000)),
                       ChatMessage(role: .assistant, content: "ok"),
                       ChatMessage(role: .user, content: String(repeating: flag, count: 30_000))]
        // 60,000 Characters would fit 100k twice over; 120,000 scalars do not.
        XCTAssertEqual(ChatHistory.trimmed(history).messages.count, 1)
    }

    func testEmptyHistoryTrimsToEmpty() {
        XCTAssertEqual(ChatHistory.trimmed([]), ChatHistory.Trimmed(messages: [], omittedCount: 0))
    }
}
