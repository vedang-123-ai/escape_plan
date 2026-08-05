//  RenderOrder.swift
//
//  The one ledger for SceneKit `renderingOrder` values. Draw order matters here because the
//  translucent parts of the scene (ghosted floors, glass, route ghost passes) don't write
//  depth, so what lands on top is decided by this ordering — scattered magic numbers were an
//  accident waiting to happen. Every band lives here, spaced so new content slots in between
//  without renumbering.
//
//  White Model overhaul (Aug 2026): the active floor is now genuinely OPAQUE and draws first
//  with a normal depth test. Everything above `walls` is either an inactive floor's ghost
//  treatment or overlay content that must survive on top of it.

enum RenderOrder {
    /// Opaque interior: room slabs, the base plate, contact shadow.
    static let opaque = 0
    /// Furniture minis — above slabs, still fully opaque.
    static let objects = 2
    /// Opaque fixture detail: door frames and leaves, window frames, stair treads and rails.
    static let fixtures = 6
    /// Opaque walls of the ACTIVE floor.
    static let walls = 10
    /// Window glass — translucent, drawn after the solid structure it sits in.
    static let glass = 60
    /// Inactive floors' slabs. Heavier than their walls so jagged footprints read.
    static let ghostSlab = 80
    /// Inactive floors' walls and fixtures.
    static let ghostWall = 90
    /// Route tubes. Pass A depth-tests normally; the occluded ghost pass shares this band.
    static let routes = 100
    /// Exit marker pads and chevrons — always findable, over everything structural.
    static let exitMarkers = 110
    /// Billboarded room labels.
    static let labels = 120
    /// Warning badge discs.
    static let badges = 130
    /// Badge glyphs, on top of their discs.
    static let badgeGlyphs = 131
}
