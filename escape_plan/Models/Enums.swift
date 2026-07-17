// Enums.swift
// Mirrors the enum $defs in schema/homemodel.schema.json.

import Foundation

enum RoomType: String, Codable, Equatable, CaseIterable {
    case bedroom, living, kitchen, hall, bath, garage, other
}

enum OpeningKind: String, Codable, Equatable, CaseIterable {
    case door, window
}

enum Source: String, Codable, Equatable, CaseIterable {
    case scan, manual
}

enum StairKind: String, Codable, Equatable, CaseIterable {
    case straight, L, U
}

enum ProfileTag: String, Codable, Equatable, CaseIterable {
    case child, elderly, mobility_limited, pet
}
