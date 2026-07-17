//  ModelSupport.swift — editor/renderer-side conveniences over the S0.3 Models/ layer.
//
//  Models/ (HomeModel.swift, Geometry.swift, Enums.swift) is a pure schema mirror and must
//  stay that way ("never add a field there without a schema bump"). Everything the editor
//  core and renderer need beyond the schema's fields lives here instead: positional Point
//  construction for terse geometry code, id-based lookups, and the schema-version constant
//  the client-side validator checks against.
//
//  This file is compiled into both runners (the Xcode app target via the synchronized group,
//  the SwiftPM EditorCore harness via the tools/editorcore symlinks), so the extensions are
//  same-module in both.

import Foundation

extension Point {
    /// Positional convenience — geometry code reads better as `Point(x, y)`.
    init(_ x: Double, _ y: Double) {
        self.init(x: x, y: y)
    }
}

extension HomeModel {
    /// The schema version this build reads and writes (schema/homemodel.schema.json).
    static let currentSchemaVersion = "1.0"

    func floor(_ id: String) -> Floor? {
        floors.first { $0.id == id }
    }

    func floorIndex(_ id: String) -> Int? {
        floors.firstIndex { $0.id == id }
    }

    /// Finds a room anywhere in the home, with the floor it lives on.
    func locateRoom(_ roomId: String) -> (floorId: String, room: Room)? {
        for f in floors {
            if let r = f.room(roomId) { return (f.id, r) }
        }
        return nil
    }
}

extension Floor {
    func room(_ id: String) -> Room? {
        rooms.first { $0.id == id }
    }
}
