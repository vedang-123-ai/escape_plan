//  FixtureKit.swift
//  escape_plan
//
//  The parametric fixture layer of the dollhouse renderer (UI revamp, Jul 2026). Every
//  architectural element — wall, door, window, stair flight, floor slab — is built by a
//  swappable fixture builder from a pure spec, so:
//
//  1. every home renders with the SAME component vocabulary (consistent look across scans,
//     like a driving-visualization that always draws the same car model), and
//  2. any builder can be replaced wholesale — hand-modeled .usdz/.scn assets plug in through
//     `AssetFixture` without touching the scene builder.
//
//  ## The local-frame contract (what a custom builder must honor)
//
//  All dimensions are meters. `DollhouseSceneBuilder` owns node NAMES and world PLACEMENT;
//  fixtures own geometry in a local frame:
//
//  - **Wall**: origin at the wall's center (mid-length, mid-height, mid-thickness).
//    Local +x runs along the wall, +y up, +z through the wall. Geometry spans
//    x ∈ [−length/2, length/2], y ∈ [−height/2, height/2]. `cutouts` are holes the wall must
//    leave open; door/window fixtures are placed into those holes by the scene builder.
//  - **Door / Window**: origin at the CENTER of the wall cutout it fills (x along wall, y up,
//    z through the wall, centered). Geometry spans x ∈ [−width/2, width/2],
//    y ∈ [−height/2, height/2]; z may exceed the wall thickness slightly (frame reveal).
//  - **Stairs**: origin at the center of the footprint at floor level (y = 0). The flight
//    ascends along local +x from −runLength/2 to +runLength/2, treads spanning
//    z ∈ [−width/2, width/2].
//  - **Floor slab**: built in FLOOR space (the plan → scene mapping baked in: plan (x, y) →
//    scene (x, −z)), top surface at y = 0, extruding `thickness` downward. Returns nil for a
//    degenerate polygon — the scene builder reports that as a BuildIssue.
//
//  Translucency rules (see RenderOrder.swift): the dollhouse is see-through by design.
//  Opaque fixture detail belongs in `RenderOrder.fixtures`; anything that does not write
//  depth (wall panels, glass) must draw in a later band.

import SceneKit
import UIKit

// MARK: - Specs

/// A hole an opening punches through a wall, in wall-local terms.
struct WallCutout {
    /// Center of the hole measured along the wall from its `a` endpoint.
    var centerAlong: Double
    var width: Double
    /// Bottom of the hole above the floor (0 for doors).
    var sill: Double
    var height: Double
}

struct WallFixtureSpec {
    var length: Double
    var height: Double
    var thickness: Double
    /// Exterior shell walls render with more body than interior partitions.
    var isExterior: Bool
    var cutouts: [WallCutout] = []
}

/// One spec serves doors and windows — `kind`/`isExit` pick the styling; the geometry contract
/// (fill a wall cutout, centered) is identical.
struct OpeningFixtureSpec {
    var width: Double
    var height: Double
    var wallThickness: Double
    var kind: OpeningKind
    var isExit: Bool
}

struct StairFixtureSpec {
    /// Horizontal run of the flight.
    var runLength: Double
    /// Tread width (across the flight).
    var width: Double
    /// Total vertical rise to the floor above.
    var rise: Double
}

struct SlabFixtureSpec {
    var polygon: [Point]
    var thickness: Double
    var roomType: RoomType
}

// MARK: - Builder protocols

protocol WallFixtureBuilding {
    func node(for spec: WallFixtureSpec) -> SCNNode
}

protocol DoorFixtureBuilding {
    func node(for spec: OpeningFixtureSpec) -> SCNNode
}

protocol WindowFixtureBuilding {
    func node(for spec: OpeningFixtureSpec) -> SCNNode
}

protocol StairFixtureBuilding {
    func node(for spec: StairFixtureSpec) -> SCNNode
}

protocol FloorSlabBuilding {
    func node(for spec: SlabFixtureSpec) -> SCNNode?
}

// MARK: - Catalog

/// The swap point. `DollhouseSceneBuilder` builds every element through `FixtureCatalog.shared`;
/// replacing a builder here (at app startup, before the first render) restyles every home in
/// the app at once. That single-vocabulary property is the point — do not style elements
/// ad hoc in the scene builder.
struct FixtureCatalog {
    var wall: WallFixtureBuilding = StyledWallFixture()
    var door: DoorFixtureBuilding = StyledDoorFixture()
    var window: WindowFixtureBuilding = StyledWindowFixture()
    var stair: StairFixtureBuilding = StyledStairFixture()
    var slab: FloorSlabBuilding = StyledFloorSlabFixture()

    /// Swap builders at startup only — the scene rebuilds on every edit, and a mid-session
    /// swap would restyle the house under the user's fingers.
    nonisolated(unsafe) static var shared = FixtureCatalog()
}

// MARK: - Asset adapter

/// Wraps a hand-modeled `.usdz`/`.scn` asset as a door, window, or stair fixture: the asset is
/// loaded once, then bounding-box-fitted to each spec's dimensions. Author assets facing +z
/// (the "out of the wall" axis), widest along x — the fit is a non-uniform scale to the target
/// box, so a door modeled at real-world proportions lands exactly in its cutout.
///
///     FixtureCatalog.shared.door = AssetFixture(named: "OakDoor")   // OakDoor.usdz in bundle
struct AssetFixture: DoorFixtureBuilding, WindowFixtureBuilding, StairFixtureBuilding {
    private let template: SCNNode?

    init(named name: String, in bundle: Bundle = .main) {
        if let url = bundle.url(forResource: name, withExtension: "usdz")
            ?? bundle.url(forResource: name, withExtension: "scn"),
           let scene = try? SCNScene(url: url, options: [.checkConsistency: true]) {
            let holder = SCNNode()
            for child in scene.rootNode.childNodes { holder.addChildNode(child.clone()) }
            template = holder
        } else {
            template = nil
        }
    }

    func node(for spec: OpeningFixtureSpec) -> SCNNode {
        fitted(width: spec.width, height: spec.height,
               depth: spec.wallThickness + FixtureStyle.frameRevealM * 2)
    }

    func node(for spec: StairFixtureSpec) -> SCNNode {
        fitted(width: spec.runLength, height: spec.rise, depth: spec.width,
               floorOrigin: true)
    }

    /// Clone the template and scale its bounding box onto the target dimensions. A missing or
    /// unreadable asset yields a loud magenta box of the right size — visible, never silent.
    private func fitted(width: Double, height: Double, depth: Double,
                        floorOrigin: Bool = false) -> SCNNode {
        guard let template else {
            let box = SCNBox(width: CGFloat(width), height: CGFloat(height),
                             length: CGFloat(depth), chamferRadius: 0)
            box.firstMaterial = FixtureStyle.material(.magenta)
            let node = SCNNode(geometry: box)
            if floorOrigin { node.position.y = Float(height / 2) }
            node.renderingOrder = RenderOrder.fixtures
            return node
        }

        let clone = template.clone()
        let (minB, maxB) = clone.boundingBox
        let size = SCNVector3(max(maxB.x - minB.x, 1e-4),
                              max(maxB.y - minB.y, 1e-4),
                              max(maxB.z - minB.z, 1e-4))
        clone.scale = SCNVector3(Float(width) / size.x,
                                 Float(height) / size.y,
                                 Float(depth) / size.z)
        // Re-center the scaled bounds on the local origin (or sit them on y = 0 for stairs).
        let cx = (minB.x + maxB.x) / 2 * clone.scale.x
        let cy = floorOrigin ? minB.y * clone.scale.y : (minB.y + maxB.y) / 2 * clone.scale.y
        let cz = (minB.z + maxB.z) / 2 * clone.scale.z
        clone.position = SCNVector3(-cx, -cy, -cz)

        let holder = SCNNode()
        holder.addChildNode(clone)
        holder.enumerateHierarchy { child, _ in
            if child.geometry != nil { child.renderingOrder = RenderOrder.fixtures }
        }
        return holder
    }
}

// MARK: - Shared style constants & helpers

/// Dimensions and material helpers shared by the styled fixtures, so joints line up: the door
/// frame's reveal, the window frame's section, and the wall's cutouts all reference the same
/// numbers. Colors live in `DollhousePalette` — fixtures never invent their own.
enum FixtureStyle {
    /// How far frames protrude past each wall face — the "reveal" that makes an inserted
    /// fixture read as trim rather than z-fight with the wall it fills.
    static let frameRevealM = 0.016
    /// Frame/jamb section for doors and windows.
    static let frameSectionM = 0.055
    /// The bright cut-top strip along the top of every sliced wall. 12 mm: thin enough to read
    /// as a cut line rather than a coping, thick enough to catch the key light. This is the
    /// biggest single depth cue in the White Model look — do not thicken it casually.
    static let wallCapHeightM = 0.012
    /// Micro-chamfer on white geometry. Catches a specular highlight along every edge, which is
    /// what draws the fine white-on-white contour lines in the reference render.
    static let chamferM = 0.008
    /// Target riser height for stairs; the flight rounds to a whole step count near this.
    static let targetRiserM = 0.185

    static func material(_ color: UIColor,
                         roughness: CGFloat = 0.85,
                         lighting: SCNMaterial.LightingModel = .physicallyBased) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = lighting
        if lighting == .physicallyBased {
            m.roughness.contents = roughness
            m.metalness.contents = 0.0
        }
        return m
    }

    /// The White Model default: matte, unsaturated, non-metallic. Roughness 0.88 is what makes
    /// the face-orientation value ramp (top faces brightest, away faces darkest) happen for
    /// free under the key/fill rig — never hand-tint faces to fake it.
    static func white(_ color: UIColor, roughness: CGFloat = 0.88) -> SCNMaterial {
        material(color, roughness: roughness)
    }

    /// The material an INACTIVE floor swaps to (spec §4.2). Flat and unlit on purpose: lighting
    /// variation across a 12%-alpha surface is noise, and front-face culling means each wall
    /// contributes exactly one translucent layer instead of two — which is what stops a stack of
    /// ghosted floors from multiplying into gray murk the way the old always-translucent walls did.
    static func ghost(opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = DollhousePalette.ghostWhite
        m.lightingModel = .constant
        m.transparency = opacity
        m.isDoubleSided = false
        m.cullMode = .back
        m.writesToDepthBuffer = false
        return m
    }

    /// A box node in the fixture band with fixture defaults applied.
    ///
    /// `castsShadow` now defaults to true: the White Model's structure is opaque, and shadow is
    /// how it communicates depth. (It was forced off when everything lived inside a translucent
    /// shell and stray shadows read as clutter.)
    static func detailBox(width: Double, height: Double, length: Double,
                          chamfer: Double = 0.006, material: SCNMaterial,
                          castsShadow: Bool = true) -> SCNNode {
        let box = SCNBox(width: CGFloat(width), height: CGFloat(height),
                         length: CGFloat(length),
                         chamferRadius: CGFloat(min(chamfer, min(width, min(height, length)) / 2)))
        box.firstMaterial = material
        let node = SCNNode(geometry: box)
        node.renderingOrder = RenderOrder.fixtures
        node.castsShadow = castsShadow
        return node
    }
}
