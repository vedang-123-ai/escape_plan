//  WallFixture.swift
//  escape_plan
//
//  The default wall builder: a translucent shell with REAL holes where its openings live, so
//  door and window fixtures sit inside the wall instead of being pasted onto it. The wall is
//  composed from axis-aligned box segments (full-height piers between holes, sill and header
//  strips around them) — no path fill-rule tricks, crisp normals, and every edge lines up with
//  the fixture that fills the hole because both are cut from the same numbers.
//
//  Local frame per the FixtureKit contract: origin at wall center, +x along the wall, +y up,
//  +z through the thickness.

import SceneKit
import UIKit

struct StyledWallFixture: WallFixtureBuilding {

    func node(for spec: WallFixtureSpec) -> SCNNode {
        let container = SCNNode()

        // One white for every wall, interior and exterior alike. Exterior walls are thicker
        // (the scene builder picks the thickness), never differently colored — in a white model
        // it is mass that distinguishes the shell from a partition, not hue.
        let shellMaterial = FixtureStyle.white(DollhousePalette.wallWhite)

        let capHeight = min(FixtureStyle.wallCapHeightM, spec.height * 0.25)
        let bodyHeight = spec.height - capHeight

        // Segment the body around the (merged, clamped) holes.
        let holes = mergedHoles(spec: spec, bodyHeight: bodyHeight)
        var cursor = 0.0
        for hole in holes {
            addBody(from: cursor, to: hole.x0, spec: spec,
                    bodyHeight: bodyHeight, material: shellMaterial, into: container)
            // Sill strip below the hole (windows; doors have sill 0 and skip it).
            if hole.sill > 0.03 {
                addStrip(x0: hole.x0, x1: hole.x1, y0: 0, y1: hole.sill,
                         spec: spec, material: shellMaterial, into: container)
            }
            // Header strip above the hole.
            if hole.top < bodyHeight - 0.03 {
                addStrip(x0: hole.x0, x1: hole.x1, y0: hole.top, y1: bodyHeight,
                         spec: spec, material: shellMaterial, into: container)
            }
            cursor = hole.x1
        }
        addBody(from: cursor, to: spec.length, spec: spec,
                bodyHeight: bodyHeight, material: shellMaterial, into: container)

        // The cut cap runs the full length regardless of holes — it is the slice line of the
        // dollhouse, and over a full-height opening it reads as a lintel. It is the BRIGHTEST
        // surface in the scene (pure white against the walls' F7F6F3), which is what makes the
        // model read as deliberately sectioned. The chamfer catches the key light along the
        // whole run and draws the fine contour line seen in the reference render.
        let capMaterial = FixtureStyle.white(DollhousePalette.wallTopCut, roughness: 0.8)
        let cap = SCNBox(width: CGFloat(spec.length), height: CGFloat(capHeight),
                         length: CGFloat(spec.thickness),
                         chamferRadius: CGFloat(min(FixtureStyle.chamferM, capHeight / 2)))
        cap.firstMaterial = capMaterial
        let capNode = SCNNode(geometry: cap)
        capNode.position = SCNVector3(0, Float(spec.height / 2 - capHeight / 2), 0)
        decorate(capNode)
        container.addChildNode(capNode)

        return container
    }

    // MARK: - Hole bookkeeping

    private struct Hole {
        var x0: Double
        var x1: Double
        var sill: Double
        var top: Double
    }

    /// Cutouts → sorted, clamped, merged hole intervals in wall-local x (0 at the wall's `a`
    /// end). Overlapping cutouts (bad data) merge into one hole spanning both, so the wall
    /// never double-cuts.
    private func mergedHoles(spec: WallFixtureSpec, bodyHeight: Double) -> [Hole] {
        let margin = 0.01
        let holes: [Hole] = spec.cutouts.compactMap { cut in
            let x0 = max(cut.centerAlong - cut.width / 2, margin)
            let x1 = min(cut.centerAlong + cut.width / 2, spec.length - margin)
            guard x1 - x0 > 0.02 else { return nil }
            let sill = min(max(cut.sill, 0), bodyHeight)
            let top = min(sill + cut.height, bodyHeight)
            return Hole(x0: x0, x1: x1, sill: sill, top: top)
        }
        .sorted { $0.x0 < $1.x0 }

        var merged: [Hole] = []
        for hole in holes {
            if var last = merged.last, hole.x0 < last.x1 - 1e-6 {
                last.x1 = max(last.x1, hole.x1)
                last.sill = min(last.sill, hole.sill)
                last.top = max(last.top, hole.top)
                merged[merged.count - 1] = last
            } else {
                merged.append(hole)
            }
        }
        return merged
    }

    // MARK: - Pieces

    /// Full-height pier between holes (or a whole uncut wall).
    private func addBody(from x0: Double, to x1: Double, spec: WallFixtureSpec,
                         bodyHeight: Double, material: SCNMaterial, into container: SCNNode) {
        guard x1 - x0 > 0.015 else { return }
        let box = SCNBox(width: CGFloat(x1 - x0), height: CGFloat(bodyHeight),
                         length: CGFloat(spec.thickness), chamferRadius: 0)
        box.firstMaterial = material
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(Float((x0 + x1) / 2 - spec.length / 2),
                                   Float(bodyHeight / 2 - spec.height / 2), 0)
        decorate(node)
        container.addChildNode(node)
    }

    /// Horizontal strip spanning a hole (sill below, header above). y measured from the wall's
    /// bottom.
    private func addStrip(x0: Double, x1: Double, y0: Double, y1: Double,
                          spec: WallFixtureSpec, material: SCNMaterial, into container: SCNNode) {
        guard y1 - y0 > 0.015, x1 - x0 > 0.015 else { return }
        let box = SCNBox(width: CGFloat(x1 - x0), height: CGFloat(y1 - y0),
                         length: CGFloat(spec.thickness), chamferRadius: 0)
        box.firstMaterial = material
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(Float((x0 + x1) / 2 - spec.length / 2),
                                   Float((y0 + y1) / 2 - spec.height / 2), 0)
        decorate(node)
        container.addChildNode(node)
    }

    // MARK: - Shared setup

    private func decorate(_ node: SCNNode) {
        node.renderingOrder = RenderOrder.walls
        // Walls are opaque now, so they CAST — and that is the point. You see inside the house
        // because the top is open and the camera is above it, not because the walls are ghosts.
        // Real shadows off real walls are where the model gets its weight; the old translucent
        // shell could not cast at all, which is why the floors used to float.
        node.castsShadow = true
    }
}
