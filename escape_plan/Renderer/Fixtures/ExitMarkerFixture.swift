//  ExitMarkerFixture.swift
//  escape_plan
//
//  Exit markers (White Model overhaul, Aug 2026 — spec §5.6).
//
//  Exits used to be communicated by coloring the door leaf green and the exit window teal. In a
//  monochrome model that is exactly the wrong move: it puts saturated color on structure, which
//  competes with the escape route for the eye, and it means an exit is only visible if you can
//  see that particular door face-on.
//
//  Instead an exit gets a flat green pad on the ground OUTSIDE the wall, with chevrons pointing
//  away from the building. It reads from any angle, it reads at any zoom, it sits in the same
//  visual system as the route (the route tube terminates in it), and the door itself stays white.
//
//  Local frame: origin at the wall cutout's center, matching `OpeningFixtureSpec` — +x along the
//  wall, +y up, +z through the wall. The scene builder positions and rotates it exactly like the
//  opening it belongs to; `outwardZ` says which way is "outside".

import SceneKit
import UIKit

enum ExitMarkerFixture {

    private static let padWidthM = 0.5
    private static let padDepthM = 0.3

    /// - Parameters:
    ///   - sillY: how far the opening's center sits above its floor, so the pad can be dropped
    ///     back down to floor level regardless of where the opening is in the wall.
    ///   - outwardZ: +1 or −1 — the local z direction that points away from the building.
    ///   - animated: pulse on the plan view; static in the editor, where a throbbing marker
    ///     under a drag gesture is just noise.
    static func node(wallThickness: Double, sillY: Double, outwardZ: Double,
                     animated: Bool) -> SCNNode {
        let holder = SCNNode()
        let out = outwardZ >= 0 ? 1.0 : -1.0
        // Clear of the wall face, sitting on the plate.
        let z = out * (wallThickness / 2 + padDepthM / 2 + 0.06)

        let material = constantGreen(opacity: 1.0)

        let pad = SCNBox(width: CGFloat(padWidthM), height: 0.012,
                         length: CGFloat(padDepthM), chamferRadius: 0.006)
        pad.firstMaterial = material
        let padNode = SCNNode(geometry: pad)
        padNode.position = SCNVector3(0, Float(-sillY + 0.008), Float(z))
        decorate(padNode)
        holder.addChildNode(padNode)

        // Three chevrons marching away from the wall.
        for index in 0..<3 {
            let chevron = chevronNode(material: material)
            chevron.position = SCNVector3(
                0,
                Float(-sillY + 0.010),
                Float(z + out * (padDepthM / 2 + 0.10 + Double(index) * 0.13)))
            chevron.eulerAngles.y = out > 0 ? 0 : .pi
            decorate(chevron)
            holder.addChildNode(chevron)
        }

        if animated {
            let fade = SCNAction.sequence([
                .fadeOpacity(to: 0.75, duration: 0.8),
                .fadeOpacity(to: 1.0, duration: 0.8),
            ])
            fade.timingMode = .easeInEaseOut
            holder.runAction(.repeatForever(fade))
        }
        return holder
    }

    // MARK: - Pieces

    /// A chevron built from two angled bars — cheap, and it reads as an arrowhead from above,
    /// which is the angle this app is almost always viewed from.
    private static func chevronNode(material: SCNMaterial) -> SCNNode {
        let holder = SCNNode()
        let barLength = 0.16
        for side: Double in [-1, 1] {
            let bar = SCNBox(width: CGFloat(barLength), height: 0.010,
                             length: 0.036, chamferRadius: 0.005)
            bar.firstMaterial = material
            let node = SCNNode(geometry: bar)
            node.eulerAngles.y = Float(side * .pi / 4)
            node.position = SCNVector3(Float(side * barLength * 0.34), 0,
                                       Float(-barLength * 0.30))
            holder.addChildNode(node)
        }
        return holder
    }

    /// Constant lighting: the marker is signage, not architecture. It must not pick up the key
    /// light's falloff, and it must not go gray on the shadowed side of the house.
    private static func constantGreen(opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = DollhousePalette.exitGreen
        m.emission.contents = DollhousePalette.exitGreen
        m.lightingModel = .constant
        m.transparency = opacity
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }

    private static func decorate(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            child.renderingOrder = RenderOrder.exitMarkers
            child.castsShadow = false
        }
        node.renderingOrder = RenderOrder.exitMarkers
        node.castsShadow = false
    }
}
