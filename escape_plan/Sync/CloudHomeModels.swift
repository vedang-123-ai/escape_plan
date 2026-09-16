//  CloudHomeModels.swift
//  escape_plan — S8.4 cloud sync
//
//  The wire shapes of the two S8.2 cloud endpoints, `GET /homes` and `POST /homes`.
//
//  Pure Foundation on purpose: this whole directory is symlinked into the `tools/editorcore`
//  SwiftPM package (`Sources/EditorCore/Sync`) so it compiles and TESTS on a machine with no
//  iOS simulator — the same arrangement `Auth/` uses. A SwiftUI or UIKit import here breaks
//  that and silently removes the only coverage this layer has.
//
//  Two details of the backend contract are load-bearing and both were verified against the
//  DEPLOYED service on 2026-09-16 (see BLOCKERS.md §2):
//
//  1. The id field on the wire is `id`, NOT Mongo's `_id`. `backend/app/api_auth.py` sets
//     `response_model_by_alias=False` on both routes precisely so this type needs no
//     `CodingKeys` mapping for a database detail. If that ever regresses, decoding fails
//     loudly here rather than silently producing empty ids.
//  2. `revision` is server-owned and increments on every accepted write, which is why
//     `HomeSyncRequestBody` has no revision field to send. A client-supplied counter is not
//     a counter anyone can trust.

import Foundation

/// One home as the server stores it: the `HomeModel` plus ownership and sync metadata.
///
/// Mirrors `StoredHomeModel` in `backend/app/cloud_models.py`. The embedded `home` is the
/// project's one law — the same `HomeModel` the editor mutates and the engine routes over —
/// so nothing here re-describes home geometry.
struct StoredHome: Decodable, Equatable, Identifiable, Sendable {
    /// The SERVER's id for this record. Distinct from `home.home_id`, which is the schema's
    /// per-home UUID and the id the app files documents under. Both are needed: the server id
    /// addresses `POST /homes?home_id=`, and `home.home_id` is what survives a round trip
    /// through another device.
    let id: String
    let user_id: String
    let home: HomeModel
    let revision: Int
    let created_at: Date
    let updated_at: Date

    /// The schema id of the embedded home — the key the app matches local and remote on.
    var localHomeID: String { home.home_id }
}

/// `POST /homes` request body. The backend's `HomeSyncRequest` sets `extra="forbid"`, so an
/// extra key here is a 422 rather than a warning.
///
/// `home_id` omitted creates a new record; supplied, it updates one you own (404 otherwise).
/// Swift's synthesised encoding omits a nil Optional rather than writing `null`, which is
/// exactly the create case.
struct HomeSyncRequestBody: Encodable, Sendable {
    let home: HomeModel
    let home_id: String?

    init(home: HomeModel, remoteID: String? = nil) {
        self.home = home
        self.home_id = remoteID
    }
}
