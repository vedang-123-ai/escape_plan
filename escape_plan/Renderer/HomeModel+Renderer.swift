import Foundation

//  Renderer-side conveniences over the merged HomeModel (Models/Generated/HomeModel.swift).
//  HomeModel.swift stays a pure schema mirror; anything the renderer needs beyond the schema's
//  fields lives here instead.

extension Point2D {
    /// Labeled convenience initializer; the schema mirror only exposes positional `init(_:_:)`.
    init(x: Double, y: Double) {
        self.init(x, y)
    }
}

extension HomeModel {
    /// Floors sorted bottom-to-top by `level` — the stacking order the dollhouse builds in.
    /// (Array order in the JSON is not guaranteed to be level order.)
    var floorsByLevel: [Floor] {
        floors.sorted { $0.level < $1.level }
    }
}
