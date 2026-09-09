//  FurnitureFixture.swift
//  escape_plan
//
//  White clay furniture (White Model overhaul, Aug 2026 — spec §5.3).
//
//  The schema only stores a box footprint plus a category, so every piece is built
//  parametrically from those numbers into a simplified white miniature: a bed with a duvet and
//  pillows, a sofa with a back and arms, a table with legs. The old renderer drew one tinted
//  prism per object, which is what made a room read as a patchwork of pastel rectangles.
//
//  All pieces share `furnitureWhite` — the SAME white as the walls. That shared material
//  identity is the whole point: the model looks like one object carved from one block, and the
//  only thing that isn't white is the escape route.
//
//  Local frame: origin at the footprint center on the floor (y = 0), +x along the object's
//  width, +z along its depth. The scene builder owns rotation and placement.

import SceneKit
import UIKit

/// Builds one furniture mini for a `FloorObject`.
///
/// IMPORTANT: the scene builder names the returned node `object:<id>` and the editor's
/// hit-testing and drag both key off that name, so a mini must stay ONE node with its parts as
/// children — never a loose collection added to the floor.
enum FurnitureFixture {

    /// Chamfer for furniture. Larger than the architectural `FixtureStyle.chamferM` because
    /// soft-edged furniture is what stops a room reading as a pile of CAD boxes.
    private static let chamferM = 0.02

    static func node(category: ObjectCategory, width: Double, depth: Double,
                     height: Double) -> SCNNode {
        let w = max(width, 0.05)
        let d = max(depth, 0.05)
        let h = max(height, 0.05)

        switch category {
        case .bed:       return bed(w: w, d: d, h: h)
        case .sofa:      return sofa(w: w, d: d, h: h)
        case .table:     return table(w: w, d: d, h: h)
        case .wardrobe,
             .storage,
             // Placeholder geometry, S7.1. A bookcase reads as a tall seamed volume, which is
             // close enough to be honest and wrong enough to be worth replacing — S7.6 gives
             // these four real fixtures. They are here now only because this switch is
             // exhaustive over ObjectCategory and the app would not compile without them.
             .bookcase:  return seamedBox(w: w, d: d, h: h)
        case .appliance,
             .water_heater: return appliance(w: w, d: d, h: h)
        case .other,
             .tv,
             .heat_source: return plainBox(w: w, d: d, h: h)
        }
    }

    // MARK: - Shared

    private static var material: SCNMaterial {
        FixtureStyle.white(DollhousePalette.furnitureWhite)
    }

    /// A box sitting on the floor, centered in x/z, in the objects band.
    private static func box(_ w: Double, _ h: Double, _ d: Double,
                            x: Double = 0, yBottom: Double = 0, z: Double = 0,
                            chamfer: Double = chamferM,
                            material m: SCNMaterial? = nil) -> SCNNode {
        let node = FixtureStyle.detailBox(width: w, height: h, length: d,
                                          chamfer: chamfer, material: m ?? material)
        node.renderingOrder = RenderOrder.objects
        node.position = SCNVector3(Float(x), Float(yBottom + h / 2), Float(z))
        return node
    }

    // MARK: - Categories

    /// Base slab + an inset duvet with a big soft chamfer + pillows at the head. The head end is
    /// the −z side of the local frame; the scene builder's rotation puts it against a wall.
    private static func bed(w: Double, d: Double, h: Double) -> SCNNode {
        let holder = SCNNode()
        let baseH = h * 0.35
        holder.addChildNode(box(w, baseH, d))

        let duvetInset = 0.05
        let duvetH = h * 0.25
        holder.addChildNode(box(max(w - duvetInset * 2, 0.05), duvetH,
                                max(d - duvetInset * 2, 0.05),
                                yBottom: baseH, z: duvetInset, chamfer: 0.04))

        // One pillow on a single, two side by side on anything wider.
        let pillowW = w > 1.3 ? (w - 0.18) / 2 : w * 0.7
        let pillowD = min(d * 0.22, 0.42)
        let pillowH = h * 0.16
        let pillowZ = -d / 2 + pillowD / 2 + 0.06
        let offsets: [Double] = w > 1.3 ? [-(pillowW / 2 + 0.03), pillowW / 2 + 0.03] : [0]
        for x in offsets {
            holder.addChildNode(box(pillowW, pillowH, pillowD,
                                    x: x, yBottom: baseH, z: pillowZ, chamfer: 0.045))
        }
        return holder
    }

    /// Seat + a back along the −z long edge + arms at each end.
    private static func sofa(w: Double, d: Double, h: Double) -> SCNNode {
        let holder = SCNNode()
        let armW = min(w * 0.12, 0.18)
        let backD = min(d * 0.22, 0.22)
        let seatH = h * 0.45

        holder.addChildNode(box(w, seatH, d, chamfer: 0.03))
        holder.addChildNode(box(w, h - seatH, backD,
                                yBottom: seatH, z: -d / 2 + backD / 2, chamfer: 0.03))
        for side: Double in [-1, 1] {
            holder.addChildNode(box(armW, h * 0.75 - seatH, d - backD,
                                    x: side * (w / 2 - armW / 2), yBottom: seatH,
                                    z: backD / 2, chamfer: 0.03))
        }
        return holder
    }

    /// Top slab plus legs — or a center pedestal when the footprint is too small for legs to read.
    private static func table(w: Double, d: Double, h: Double) -> SCNNode {
        let holder = SCNNode()
        let topH = min(0.06, h * 0.25)
        holder.addChildNode(box(w, topH, d, yBottom: h - topH, chamfer: 0.012))

        if min(w, d) < 0.7 {
            holder.addChildNode(box(min(w, d) * 0.35, h - topH, min(w, d) * 0.35, chamfer: 0.02))
            return holder
        }
        let legS = 0.07
        let inset = 0.08
        for sx: Double in [-1, 1] {
            for sz: Double in [-1, 1] {
                holder.addChildNode(box(legS, h - topH, legS,
                                        x: sx * (w / 2 - inset - legS / 2),
                                        z: sz * (d / 2 - inset - legS / 2), chamfer: 0.008))
            }
        }
        return holder
    }

    /// Two stacked halves with a 10 mm gap: the recessed seam keeps a tall featureless volume
    /// from reading as a blank monolith once everything is the same white.
    private static func seamedBox(w: Double, d: Double, h: Double) -> SCNNode {
        let holder = SCNNode()
        let gap = 0.01
        let half = (h - gap) / 2
        holder.addChildNode(box(w, half, d, chamfer: 0.012))
        holder.addChildNode(box(w, half, d, yBottom: half + gap, chamfer: 0.012))
        return holder
    }

    /// Lower roughness so it reads as enamel rather than plaster.
    private static func appliance(w: Double, d: Double, h: Double) -> SCNNode {
        box(w, h, d, chamfer: 0.015,
            material: FixtureStyle.white(DollhousePalette.furnitureWhite, roughness: 0.6))
    }

    private static func plainBox(w: Double, d: Double, h: Double) -> SCNNode {
        box(w, h, d)
    }
}
