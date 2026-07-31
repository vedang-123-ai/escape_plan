//  RenderOrder.swift
//
//  The one ledger for SceneKit `renderingOrder` values. The see-through dollhouse depends on
//  draw order (translucent surfaces don't write depth), so scattered magic numbers were an
//  accident waiting to happen — every band lives here, spaced so new content slots in between
//  without renumbering.

enum RenderOrder {
    /// Opaque interior: room slabs, the base plate. Drawn first so translucency blends over it.
    static let opaque = 0
    /// Furniture/object prisms (S-revamp B2) — above slabs, below the translucent shell.
    static let objects = 5
    /// Opaque fixture detail: door frames and leaves, window frames, stair treads and rails.
    /// Draws before the translucent shell so walls still blend over fixtures behind them.
    static let fixtures = 6
    /// Translucent walls and opening panels.
    static let walls = 10
    /// Window glass — translucent and depth-write-off like the walls, drawn just after them
    /// so a pane blends over the wall segments that surround it.
    static let glass = 12
    /// Exit glow shells and other additive glows around geometry.
    static let glow = 20
    /// Route tubes — drawn after the shell so escape paths read through walls and floors.
    static let routes = 30
    /// Billboarded room labels (no depth test — UI, not geometry).
    static let labels = 100
    /// Warning badge discs.
    static let badges = 110
    /// Badge glyphs, on top of their discs.
    static let badgeGlyphs = 111
}
