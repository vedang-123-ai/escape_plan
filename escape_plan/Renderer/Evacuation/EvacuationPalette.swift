//  EvacuationPalette.swift
//  Renderer/Evacuation
//
//  The evacuation overlay has two semantic colour families and no others:
//
//    cool = the route / instruction
//    warm = the illustrative hazard / alarm
//
//  Hue is intentionally redundant with geometry and luminance. Routes remain solid/dashed
//  lines while the hazard remains an area wash, and the three principal colours have a
//  relative-luminance gap of at least 0.08. That keeps the systems distinct under common
//  colour-vision deficiencies and in a grayscale capture of the white model.

import UIKit

nonisolated enum EvacuationPalette {

    // MARK: - Cool instruction family

    /// Deep cobalt, relative luminance 0.0682. This is the route renderer's canonical primary
    /// ink, referenced rather than duplicated so ordinary and timeline routes cannot drift.
    @MainActor static let routePrimary = DollhousePalette.routePrimary
    /// Lighter cobalt, relative luminance 0.2132. Geometry still carries the backup-route
    /// distinction; the luminance step is a second, non-hue cue.
    @MainActor static let routeSecondary = DollhousePalette.routeSecondary

    // MARK: - Warm illustrative-hazard family

    /// The standalone hazard mass, relative luminance 0.3246. Its nearest route colour is
    /// separated by 0.1114 relative luminance, in addition to the warm/cool hue split.
    @MainActor static let hazardCore = DollhousePalette.hazardCore
    /// Only used as an edge touching `hazardCore`, never as a standalone warning line.
    @MainActor static let hazardEdge = DollhousePalette.hazardEdge
    /// Low-alpha falloff and abstract smoke particles. It is a wash, not an ink colour.
    @MainActor static let hazardHalo = DollhousePalette.hazardHalo

    /// Surface opacity stays low enough that room geometry and route tubes remain readable.
    static let maximumFloorWashOpacity: CGFloat = 0.46
    static let maximumWallWashOpacity: CGFloat = 0.24
    static let maximumEdgeOpacity: CGFloat = 0.82
    static let maximumSmokeOpacity: CGFloat = 0.34
}
