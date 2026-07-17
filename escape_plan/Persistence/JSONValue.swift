//
//  JSONValue.swift
//  escape_plan — S2.4 persistence
//

import Foundation

/// A lossless, `Codable` representation of an arbitrary JSON document.
///
/// The document store keeps home documents as JSON trees rather than as decoded
/// `HomeModel` values so that persistence never becomes a second, drifting copy
/// of `schema/homemodel.schema.json`. A document written by a newer build (or a
/// schema version this build does not understand) round-trips byte-for-byte
/// instead of silently losing the fields this build happens not to know about.
indirect enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value is not valid JSON."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    // MARK: - Accessors

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// Returns a copy with `key` set on the top-level object, or `nil` if the
    /// receiver is not an object.
    func setting(_ key: String, to value: JSONValue) -> JSONValue? {
        guard var object = objectValue else { return nil }
        object[key] = value
        return .object(object)
    }
}
