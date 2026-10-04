//  APIClient+Chat.swift
//  escape_plan — S3.3 iOS half
//
//  /chat wire types + endpoint call, kept out of APIClient.swift per the session scope.
//  The backend is stateless: every call resends the turn history, which must end with a user
//  message; since S11.45 that is the most recent turns within the server's caps (`ChatHistory`). Request/response bodies mirror backend/app/api_chat.py exactly — the
//  server's models are `extra="forbid"`, so these structs must never grow extra encoded keys.

import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
}

/// Wire-format message: exactly `{role, content}`, nothing else (server forbids extra keys).
struct ChatMessage: Codable, Equatable {
    var role: ChatRole
    var content: String
}

/// POST /chat body. `route_plan` and `profiles` are optional server-side and deliberately
/// not sent (v1 grounds chat in the home alone — see docs/decisions.md).
struct ChatRequest: Encodable {
    var home: HomeModel
    var messages: [ChatMessage]
}

/// What one /chat request may carry, and the trimming that keeps a long thread inside it
/// (S11.45, AUD-033). Every send used to post the whole thread, so a long one hit the server's
/// caps (a 422) and stayed stuck until "New chat". The thread on screen is never cut; only what
/// is SENT is: the most recent turns that fit.
enum ChatHistory {
    /// These three mirror `backend/app/limits.py` ("/chat inputs (AUD-035)") exactly, and
    /// `ChatRequestEncodingTests` reads that file to prove it, so they cannot drift silently.
    /// Characters are counted as the server counts them: Python's `len`, one per Unicode scalar.
    static let maxMessages = 40           // MAX_CHAT_MESSAGES
    static let maxMessageChars = 8_000    // MAX_CHAT_MESSAGE_CHARS
    static let maxTotalChars = 100_000    // MAX_CHAT_TOTAL_CHARS

    /// The history to send, and how many earlier turns were left out of it.
    struct Trimmed: Equatable {
        var messages: [ChatMessage]
        var omittedCount: Int
    }

    /// The longest run of most-recent turns within every cap, oldest dropped first.
    ///
    /// - The final message is always kept, even if it alone breaks a cap: dropping the question
    ///   the user just asked would answer something else. The server then refuses it with a 422
    ///   whose sentence the screen shows (S11.37), which is the honest outcome.
    /// - The run is contiguous: a long turn in the middle ends it rather than being skipped, so
    ///   the model never sees a conversation with a hole in it.
    /// - It never starts with an assistant turn (unless that is all there is), so a trimmed
    ///   request reads as the user opening the conversation. A history that ends with the user's
    ///   message still does after trimming, which the server requires.
    static func trimmed(_ history: [ChatMessage]) -> Trimmed {
        guard let last = history.last else { return Trimmed(messages: [], omittedCount: 0) }
        var kept: [ChatMessage] = [last]
        var total = characterCount(last.content)
        for message in history.dropLast().reversed() {
            let length = characterCount(message.content)
            guard kept.count < maxMessages,
                  length <= maxMessageChars,
                  total + length <= maxTotalChars else { break }
            kept.append(message)
            total += length
        }
        kept.reverse()
        while kept.count > 1, kept.first?.role == .assistant { kept.removeFirst() }
        return Trimmed(messages: kept, omittedCount: history.count - kept.count)
    }

    /// Python's `len(str)`: Unicode scalars, not Swift's grapheme clusters (an emoji flag is one
    /// `Character` but two scalars, and the server would count two).
    static func characterCount(_ text: String) -> Int { text.unicodeScalars.count }
}

/// 200 response. Citations appear inline in `reply` as `[cite: source-id]` tags;
/// `citations` is the server's de-duplicated, sorted id list (may be empty — small talk
/// and 911 deferrals legitimately carry no citation).
struct ChatResponse: Decodable, Equatable {
    var reply: String
    var citations: [String]
}

/// What `chat(home:messages:)` throws on a non-200. It keeps the server's 422 `detail` for
/// logs and tests; what the user is told comes from `BackendFailure(error, while: .assistant)`,
/// the same classifier every other endpoint uses, so the assistant's 401/429/502/503 copy
/// cannot drift from the rest of the app's (audit 2026-09-25).
enum ChatError: LocalizedError, Equatable {
    /// 5xx from the backend. 502 is the deliberate "the server's AI needs an operator" answer
    /// (no key, no credit, grounding failed after retries); 503 is "busy, retry".
    case aiUnavailable(statusCode: Int)
    /// 401 — bearer token missing/wrong (Settings tab).
    case unauthorized
    /// 422, 429 or any other unexpected status.
    case unexpectedStatus(statusCode: Int, detail: String?)

    var statusCode: Int {
        switch self {
        case .aiUnavailable(let code): return code
        case .unauthorized: return 401
        case .unexpectedStatus(let code, _): return code
        }
    }

    var errorDescription: String? {
        BackendFailure(self, while: .assistant).message
    }
}

extension APIClient {
    /// How long the phone waits for /chat. Must stay above the server's chat deadline
    /// (`CHAT_DEADLINE_S` in backend/app/ai/client.py, 110 s) so the server gives up first and
    /// answers 504, rather than the phone giving up first and leaving the server working
    /// (S11.37, AUD-032). A 51 s cold start plus a real answer did not fit in the old 60 s.
    static let chatTimeout: TimeInterval = 120

    /// Sends the full conversation (ending with the user's latest message) grounded in `home`.
    /// Generous timeout: the free-tier Render deploy cold-starts in multi-second territory.
    func chat(home: HomeModel, messages: [ChatMessage]) async throws -> ChatResponse {
        var request = try authenticatedRequest(path: "chat", method: "POST")
        request.timeoutInterval = Self.chatTimeout
        request.httpBody = try HomeModel.encoder().encode(ChatRequest(home: home, messages: messages))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(ChatResponse.self, from: data)
        case 401:
            throw ChatError.unauthorized
        case 500...599:
            throw ChatError.aiUnavailable(statusCode: http.statusCode)
        default:
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
            throw ChatError.unexpectedStatus(statusCode: http.statusCode, detail: detail)
        }
    }
}
