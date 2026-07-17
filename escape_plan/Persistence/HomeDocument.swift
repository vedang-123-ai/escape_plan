//
//  HomeDocument.swift
//  escape_plan — S2.4 persistence
//

import Foundation

/// The persisted unit: one home, stored on disk as exactly the HomeModel JSON
/// defined by `schema/homemodel.schema.json`.
///
/// The stored bytes and the exported bytes are the same document — there is no
/// wrapper envelope — so an exported file is by construction a schema-valid
/// HomeModel and there is nothing to keep in sync.
struct HomeDocument: Equatable, Sendable {
    /// The full HomeModel JSON tree.
    var body: JSONValue

    init(body: JSONValue) {
        self.body = body
    }

    init(data: Data) throws {
        self.body = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Encodes any Codable HomeModel (S2.1's type, once it lands) into a document.
    init<Model: Encodable>(model: Model) throws {
        let data = try JSONEncoder().encode(model)
        try self.init(data: data)
    }

    /// Decodes the document into a Codable HomeModel.
    func decode<Model: Decodable>(as type: Model.Type) throws -> Model {
        try JSONDecoder().decode(type, from: serialized())
    }

    /// Canonical on-disk / export bytes: pretty-printed, key-sorted, stable.
    func serialized() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(body)
    }

    // MARK: - Schema fields this layer is allowed to know about

    /// `home_id` — the schema's stable per-home UUID and this store's file key.
    var homeID: String? { body["home_id"]?.stringValue }

    /// `schema_version` — checked on load by `SchemaMigrator`.
    var schemaVersion: String? { body["schema_version"]?.stringValue }

    var name: String? { body["name"]?.stringValue }

    var floorCount: Int { body["floors"]?.arrayValue?.count ?? 0 }

    var roomCount: Int {
        let floors: [JSONValue] = body["floors"]?.arrayValue ?? []
        var total = 0
        for floor in floors {
            total += floor["rooms"]?.arrayValue?.count ?? 0
        }
        return total
    }

    /// `meta.modified` — ISO-8601 per the schema.
    var modified: Date? {
        guard let raw = body["meta"]?["modified"]?.stringValue else { return nil }
        return ISO8601DateFormatter.homeModel.date(from: raw)
    }

    /// Returns a copy with `home_id`, `name` and `meta.modified` replaced.
    /// Everything else — including fields this build does not model — is preserved.
    func reidentified(homeID: String, name: String, modified: Date) -> HomeDocument {
        var object = body.objectValue ?? [:]
        object["home_id"] = .string(homeID)
        object["name"] = .string(name)
        var meta = object["meta"]?.objectValue ?? [:]
        meta["modified"] = .string(ISO8601DateFormatter.homeModel.string(from: modified))
        if meta["created"] == nil {
            meta["created"] = .string(ISO8601DateFormatter.homeModel.string(from: modified))
        }
        object["meta"] = .object(meta)
        return HomeDocument(body: .object(object))
    }

    func touched(at date: Date) -> HomeDocument {
        reidentified(homeID: homeID ?? UUID().uuidString.lowercased(),
                     name: name ?? "Untitled Home",
                     modified: date)
    }
}

/// Lightweight row for the home list — derived from the document, never stored
/// separately (a cached index would be one more thing that can go stale).
struct HomeSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let floorCount: Int
    let roomCount: Int
    let modified: Date
}

extension ISO8601DateFormatter {
    /// The schema's `date-time` format (e.g. `2026-07-10T12:00:00Z`).
    static let homeModel: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
