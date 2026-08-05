//  PersonFixture.swift
//  Renderer/Fixtures — a household member standing in their bedroom.
//
//  The design handoff asked for per-person ROUTE colours here. That was rejected on purpose:
//  the White Model's governing rule is that the escape route is the only hot colour in the
//  frame, and four people would have meant four saturated hues competing with each other and
//  with the exit green — exactly the "10 hues in one view" problem the overhaul removed.
//
//  So the people are made of the same white as everything else, and identity comes from the
//  name pill above each figure. Whose route is on screen is answered by selecting the person,
//  not by memorising a colour key. The selected figure takes the accent green, which is the
//  same signal the selection ring uses everywhere else in the app.

import SceneKit
import UIKit

enum PersonFixture {

    /// Roughly a person at dollhouse scale. Deliberately abstract — a recognisable human form
    /// would read as a character in a game; a capsule reads as "someone is here".
    static let heightM = 1.5

    private static let bodyRadius = 0.15
    private static let headRadius = 0.135
    /// Pill floats clear of the head so it never intersects it at a low camera pitch.
    private static let pillHeight = 0.26

    /// `id` becomes the node name as `person:<id>`, which is how a tap resolves back to a
    /// profile — the same naming convention `object:<id>` uses for furniture.
    static func node(id: String, name: String, highlighted: Bool) -> SCNNode {
        let container = SCNNode()
        container.name = "person:\(id)"

        let material = highlighted
            ? FixtureStyle.white(DollhousePalette.selectionTint, roughness: 0.55)
            : FixtureStyle.white(DollhousePalette.furnitureWhite)

        let bodyHeight = heightM - headRadius * 2
        let body = SCNCapsule(capRadius: bodyRadius, height: bodyHeight)
        body.materials = [material]
        let bodyNode = SCNNode(geometry: body)
        // SCNCapsule is centred on its origin; lift it so the figure stands on the slab.
        bodyNode.position.y = Float(bodyHeight / 2)
        bodyNode.castsShadow = true
        bodyNode.renderingOrder = RenderOrder.fixtures
        container.addChildNode(bodyNode)

        let head = SCNSphere(radius: headRadius)
        head.materials = [material]
        let headNode = SCNNode(geometry: head)
        headNode.position.y = Float(bodyHeight + headRadius * 0.55)
        headNode.castsShadow = true
        headNode.renderingOrder = RenderOrder.fixtures
        container.addChildNode(headNode)

        container.addChildNode(pill(name: name, highlighted: highlighted))
        return container
    }

    /// Billboarded name chip — the same capsule the room labels use, so the model has one
    /// label vocabulary rather than two.
    private static func pill(name: String, highlighted: Bool) -> SCNNode {
        let sprite = RoomLabelSprite.make(name: name)
        let plane = SCNPlane(width: pillHeight * sprite.aspect, height: pillHeight)
        let material = SCNMaterial()
        material.diffuse.contents = sprite.image
        material.lightingModel = .constant
        material.isDoubleSided = true
        // Depth-tested like the room labels: a name that x-rays through a wall reads as UI
        // floating over the scene instead of a chip standing in it.
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = false
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.position.y = Float(heightM + pillHeight)
        node.renderingOrder = RenderOrder.labels
        node.castsShadow = false
        node.opacity = highlighted ? 1.0 : 0.75
        node.constraints = [SCNBillboardConstraint()]
        return node
    }
}
