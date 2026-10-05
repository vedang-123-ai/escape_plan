//  ChatMessageLengthTests.swift
//  S11.50: a chat message over the server's per-message cap is stopped before sending, in plain
//  words, and is never cut. Before, it was sent, the server answered 422 with a validation list
//  (not a sentence), and the user read "The server couldn't use what we sent for the assistant."

import Foundation
import XCTest

@testable import escape_plan

final class ChatMessageLengthTests: XCTestCase {

    func testAMessageAtTheCapIsSentAndOneOverItIsNot() {
        XCTAssertNil(ChatHistory.tooLongNotice(for: String(repeating: "a", count: ChatHistory.maxMessageChars)))
        let notice = ChatHistory.tooLongNotice(for: String(repeating: "a", count: ChatHistory.maxMessageChars + 1))
        XCTAssertEqual(notice,"This message is 8,001 characters. The assistant takes up to 8,000 at a time, "
                           + "so shorten it before sending.")
    }

    /// Counted as the server counts (Unicode scalars): 4,001 flags are 8,002 scalars.
    func testTheCapIsCountedTheWayTheServerCountsIt() {
        XCTAssertNil(ChatHistory.tooLongNotice(for: String(repeating: "🇺🇸", count: 4_000)))
        XCTAssertNotNil(ChatHistory.tooLongNotice(for: String(repeating: "🇺🇸", count: 4_001)))
    }

    func testTheNoticeIsAPlainRefusalWithNoRetry() {
        let failure = BackendFailure.chatMessageTooLong("This message is too long.")
        XCTAssertEqual(failure.kind, .rejectedInput)
        XCTAssertFalse(failure.isRetryable, "the same text is refused the same way")
        XCTAssertFalse(failure.suggestsSettings)
        XCTAssertEqual(failure.message, "This message is too long.")
    }

    /// The history trimmer still never drops or cuts the final question: the screen's check is
    /// what keeps an overlong one from going out.
    func testTrimmingNeverCutsTheFinalMessage() {
        let long = String(repeating: "q", count: ChatHistory.maxMessageChars + 50)
        let trimmed = ChatHistory.trimmed([ChatMessage(role: .user, content: long)])
        XCTAssertEqual(trimmed.messages.first?.content, long)
    }
}
