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
//
//  ## The non-colour cue (accessibility pass)
//
//  The marker used to depend on being green. That was survivable while the route was the only
//  other colour in the scene; it stopped being survivable when the hazard system arrived,
//  because green-versus-orange is the pair deuteranopia collapses and the two are on screen
//  together the moment the fire simulation runs. `DollhousePalette.exitGreen` was darkened to
//  open a real luminance gap, and this fixture adds the cue that does not depend on hue at
//  all:
//
//    * a **white rim** around the pad — a luminance-encoded frame, 4.96:1 against the pad
//      itself, so the marker is a bright-edged plate even in greyscale; and
//    * a **white chevron knocked into the pad**, pointing away from the building, so the
//      marker states its direction as a SHAPE. The three green chevrons marching outward stay
//      as they were.
//
//  Desaturate the frame completely and an exit still reads as "framed plate with an arrow
//  pointing out"; a hazard mass reads as nothing of the kind.

import SceneKit
import UIKit

enum ExitMarkerFixture {

    private static let padWidthM = 0.5
    private static let padDepthM = 0.3
    /// How far the rim extends past the pad on every side.
    private static let rimInsetM = 0.035

    /// The non-colour cue's ink. Pure white on purpose: it is the maximum luminance step
    /// available against the pad, which is what makes the cue survive greyscale, a monochrome
    /// accessibility filter, and every form of colour blindness at once.
    static let cueInk = UIColor.white

    /// Node names, so `A11yHouseSceneTests` can assert the cue exists rather than trusting a
    /// comment that says it does.
    enum NodeName {
        static let pad = "exitMarker:pad"
        static let rim = "exitMarker:rim"
        static let cueChevron = "exitMarker:cueChevron"
        static let chevron = "exitMarker:chevron"
    }

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

        let material = constantInk(DollhousePalette.exitGreen)
        let cueMaterial = constantInk(cueInk)

        // The white rim sits a hair BELOW the pad and a hair wider, so it reads as a frame
        // around the plate rather than a second plate. Luminance, not hue, is doing the work.
        let rim = SCNBox(width: CGFloat(padWidthM + rimInsetM * 2), height: 0.010,
                         length: CGFloat(padDepthM + rimInsetM * 2), chamferRadius: 0.006)
        rim.firstMaterial = cueMaterial
        let rimNode = SCNNode(geometry: rim)
        rimNode.name = NodeName.rim
        rimNode.position = SCNVector3(0, Float(-sillY + 0.004), Float(z))
        decorate(rimNode)
        holder.addChildNode(rimNode)

        let pad = SCNBox(width: CGFloat(padWidthM), height: 0.012,
                         length: CGFloat(padDepthM), chamferRadius: 0.006)
        pad.firstMaterial = material
        let padNode = SCNNode(geometry: pad)
        padNode.name = NodeName.pad
        padNode.position = SCNVector3(0, Float(-sillY + 0.008), Float(z))
        decorate(padNode)
        holder.addChildNode(padNode)

        // The shape cue: one white chevron ON the pad, pointing out. This is the piece that
        // makes the marker directional with colour removed entirely.
        let cue = chevronNode(material: cueMaterial, barLength: 0.20)
        cue.name = NodeName.cueChevron
        cue.position = SCNVector3(0, Float(-sillY + 0.016), Float(z))
        cue.eulerAngles.y = out > 0 ? 0 : .pi
        decorate(cue)
        holder.addChildNode(cue)

        // Three chevrons marching away from the wall.
        for index in 0..<3 {
            let chevron = chevronNode(material: material)
            chevron.name = "\(NodeName.chevron):\(index)"
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
    private static func chevronNode(material: SCNMaterial, barLength: Double = 0.16) -> SCNNode {
        let holder = SCNNode()
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
    /// light's falloff, and it must not go gray on the shadowed side of the house — which is
    /// also what guarantees the pad↔rim luminance step stays the measured 4.96:1 from every
    /// orbit angle, instead of drifting with the lighting.
    private static func constantInk(_ color: UIColor, opacity: CGFloat = 1.0) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.emission.contents = color
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
