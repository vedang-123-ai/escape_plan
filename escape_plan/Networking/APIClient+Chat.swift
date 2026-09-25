//  APIClient+Chat.swift
//  escape_plan — S3.3 iOS half
//
//  /chat wire types + endpoint call, kept out of APIClient.swift per the session scope.
//  The backend is stateless: every call resends the full turn history, which must end with
//  a user message. Request/response bodies mirror backend/app/api_chat.py exactly — the
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
    /// Sends the full conversation (ending with the user's latest message) grounded in `home`.
    /// Generous timeout: the free-tier Render deploy cold-starts in multi-second territory.
    func chat(home: HomeModel, messages: [ChatMessage]) async throws -> ChatResponse {
        var request = try authenticatedRequest(path: "chat", method: "POST")
        request.timeoutInterval = 60
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
