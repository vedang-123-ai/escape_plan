// Geometry.swift
// Mirrors $defs/point and $defs/polygon in schema/homemodel.schema.json.

import Foundation

/// A 2D point [x, y] in meters, floor-local coordinate frame.
/// Encodes/decodes as a bare 2-element JSON array to match the schema exactly.
struct Point: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

/// An ordered vertex list, CCW, non-self-intersecting (invariant enforced server-side by
/// backend/app/models.py — the Swift layer mirrors shape only, not geometry validation).
typealias Polygon = [Point]
