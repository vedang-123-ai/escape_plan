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

        XCTAssertNil(store.load())

        let document = ConversationDocument(
            homeID: "home-1",
            messages: [
                AssistantMessage(role: .user, content: "Hi"),
                AssistantMessage(role: .assistant, content: "Hello [cite: x].", citations: ["x"]),
            ]
        )
        try store.save(document)
        XCTAssertEqual(store.load(), document)

        try store.clear()
        XCTAssertNil(store.load())
    }
}
