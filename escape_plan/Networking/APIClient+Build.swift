// APIClient+Build.swift
// POST /build (revamp C2): the LLM house builder. Sends a text description and/or a
// floor-plan image; receives a DRAFT HomeModel in which every element carries
// source=ai_plan + low confidence. The app then forces editor review before any routes
// are fetched (HomeModel.hasAIDraftContent gates /routes in HouseScreen) — the AI drafts,
// the human confirms, the deterministic engine routes.

import Foundation

struct BuildRequest: Codable, Equatable {
    var description: String?
    var image_b64: String?
    var image_media_type: String = "image/png"
}

/// Mirror of the backend's BuildResult, minus the tool trace (which the app doesn't
/// render; JSONDecoder ignores the extra key).
struct BuildResponse: Codable, Equatable {
    var home: HomeModel?
    var truncated: Bool
    var issues: [String]

    private enum CodingKeys: String, CodingKey { case home, truncated, issues }

    init(home: HomeModel?, truncated: Bool, issues: [String] = []) {
        self.home = home
        self.truncated = truncated
        self.issues = issues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        home = try container.decodeIfPresent(HomeModel.self, forKey: .home)
        truncated = try container.decode(Bool.self, forKey: .truncated)
        issues = try container.decodeIfPresent([String].self, forKey: .issues) ?? []
    }
}

extension APIClient {
    /// Builds a draft home from a description and/or floor-plan image. The construction
    /// loop is capped server-side (~40 tool calls); generous timeout to match.
    func build(description: String?, imageData: Data?,
               imageMediaType: String = "image/png") async throws -> BuildResponse {
        var request = try authenticatedRequest(path: "build", method: "POST")
        request.httpBody = try HomeModel.encoder().encode(BuildRequest(
            description: description,
            image_b64: imageData?.base64EncodedString(),
            image_media_type: imageMediaType
        ))
        request.timeoutInterval = 180
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        guard http.statusCode == 200 else {
            throw APIClientError.unexpectedResponse(statusCode: http.statusCode)
        }
        return try HomeModel.decoder.decode(BuildResponse.self, from: data)
    }
}
