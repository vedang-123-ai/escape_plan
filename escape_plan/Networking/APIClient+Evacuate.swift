// APIClient+Evacuate.swift
// POST /evacuate — fire-origin simulation. Follows the APIClient+<Endpoint>.swift pattern
// established by APIClient+Score.swift and APIClient+Routes.swift: APIClient.swift stays a
// thin core (config + authenticatedRequest), and each endpoint gets its own extension file.
//
// Like /routes, this is the ONLY source of an evacuation timeline. The app never simulates a
// fire, never re-times an escape, and never fabricates a timeline when the network is down —
// an offline ignition fails honestly through `BackendFailure` instead. Faking one would be
// exactly the invented-safety-claim failure the whole architecture exists to prevent.

import Foundation

/// POST /evacuate body.
///
/// `profile_set_id` is omitted from the JSON entirely rather than sent as `null` when nil,
/// matching how `RoutesRequest` handles its optional fields.
struct EvacuateRequest: Encodable {
    var home: HomeModel
    /// Must be a room id that exists in `home` — the backend answers 404 otherwise.
    var origin_room_id: String
    var profile_set_id: String?

    private enum CodingKeys: String, CodingKey {
        case home, origin_room_id, profile_set_id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(home, forKey: .home)
        try container.encode(origin_room_id, forKey: .origin_room_id)
        try container.encodeIfPresent(profile_set_id, forKey: .profile_set_id)
    }
}

extension APIClient {

    /// Asks the deterministic engine to re-solve every escape route around a fire starting in
    /// `originRoomID`, and returns the resulting `EvacuationTimeline`.
    ///
    /// Errors are raised as `APIClientError.forStatus(_:body:)` so callers run
    /// them through `BackendFailure` — the one classifier — rather than growing a second catch
    /// ladder. Notably 502 (an operator must act; no Retry offered) stays distinct from 503
    /// (busy; Retry is the right move), and a 404 here means the origin room is not in the
    /// home we sent, which is a client bug rather than something a user can retry away.
    func evacuate(home: HomeModel,
                  originRoomID: String,
                  profileSetID: String? = nil) async throws -> EvacuationTimeline {
        var request = try authenticatedRequest(path: "evacuate", method: "POST")
        request.httpBody = try HomeModel.encoder().encode(
            EvacuateRequest(home: home,
                            origin_room_id: originRoomID,
                            profile_set_id: profileSetID)
        )
        // Same 90 s as /routes: Render's free tier spins the service down when idle and a cold
        // start comfortably exceeds URLSession's 60 s default.
        request.timeoutInterval = 90
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.unexpectedResponse(statusCode: -1)
        }
        guard http.statusCode == 200 else {
            throw APIClientError.forStatus(http.statusCode, body: data)
        }
        // Tolerant by construction: `EvacuationTimeline` decodes every optional field with
        // `decodeIfPresent`, ignores keys this build has never heard of, and degrades an
        // unknown `gait` to a walking figure — one unexpected field must never cost the whole
        // timeline.
        return try HomeModel.decoder.decode(EvacuationTimeline.self, from: data)
    }
}
