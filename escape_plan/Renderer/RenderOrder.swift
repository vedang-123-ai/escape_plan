//  RenderOrder.swift
//
//  The one ledger for SceneKit `renderingOrder` values. The see-through dollhouse depends on
//  draw order (translucent surfaces don't write depth), so scattered magic numbers were an
//  accident waiting to happen — every band lives here, spaced so new content slots in between
//  without renumbering.

enum RenderOrder {
    /// Opaque interior: room slabs, stair treads. Drawn first so translucency blends over it.
    static let opaque = 0
    /// Furniture/object prisms (S-revamp B2) — above slabs, below the translucent shell.
    static let objects = 5
    /// Translucent walls and opening panels.
    static let walls = 10
    /// Exit glow shells and other additive glows around geometry.
    static let glow = 20
    /// Route tubes — drawn after the shell so escape paths read through walls and floors.
    static let routes = 30
    /// Billboarded room labels (no depth test — UI, not geometry).
    static let labels = 100
    /// The label's backing plate, then its glyphs. Both are depth-independent, so their
    /// stacking is decided here rather than by position.
    static let labelPlate = 100
    static let labelText = 101
    /// Warning badge discs.
    static let badges = 110
    /// Badge glyphs, on top of their discs.
    static let badgeGlyphs = 111
}
