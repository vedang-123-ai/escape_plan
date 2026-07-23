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

enum ChatError: LocalizedError {
    /// 5xx from the backend — most likely ANTHROPIC_API_KEY isn't configured on the server
    /// (surfaces as 500; citation-grounding failure surfaces as 502).
    case aiUnavailable(statusCode: Int)
    /// 401 — bearer token missing/wrong (Settings tab).
    case unauthorized
    /// 422 or any other unexpected status.
    case unexpectedStatus(statusCode: Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .aiUnavailable:
            return "The assistant is unavailable right now — the server's AI isn't configured yet. Your escape routes on the Plan tab still work."
        case .unauthorized:
            return "The server didn't accept the access token — check it in Settings."
        case .unexpectedStatus(let code, let detail):
            return "The assistant request failed (HTTP \(code))\(detail.map { ": \($0)" } ?? "")."
        }
    }
}

extension APIClient {
    /// Sends the full conversation (ending with the user's latest message) grounded in `home`.
    /// Uses `URLSession.shared` directly — `APIClient.session` is private and this session's
    /// scope forbids editing APIClient.swift; the client's default session is `.shared` anyway.
    /// Generous timeout: the free-tier Render deploy cold-starts in multi-second territory.
    func chat(home: HomeModel, messages: [ChatMessage]) async throws -> ChatResponse {
        var request = try authenticatedRequest(path: "chat", method: "POST")
        request.timeoutInterval = 60
        request.httpBody = try HomeModel.encoder().encode(ChatRequest(home: home, messages: messages))

        let (data, response) = try await URLSession.shared.data(for: request)
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
