//  DoorFixture.swift
//  escape_plan
//
//  The default door: a jamb frame hugging the wall cutout, a leaf hung slightly ajar so a
//  door reads as a door from across the room, and a handle. Exits keep the palette's exit
//  green; interior doors the warm wood tone. Local frame per the FixtureKit contract: origin
//  at the cutout center.

import SceneKit

struct StyledDoorFixture: DoorFixtureBuilding {

    /// How far the leaf stands open. Enough to read "this swings", not so far that the leaf
    /// pokes deep into the room (the route overlay sizes exit glows off the fixture's bounds).
    private let ajarAngle: Float = 0.34  // ≈ 19°

    func node(for spec: OpeningFixtureSpec) -> SCNNode {
        let container = SCNNode()

        let jamb = FixtureStyle.frameSectionM
        let depth = spec.wallThickness + FixtureStyle.frameRevealM * 2
        // Frames are recessed, so they run a hair darker than the leaf they hold. Exits are NOT
        // colored here — a green door leaf was the old renderer's loudest "board game token"
        // tell. Exits are called out by their marker pad on the plate outside (ExitMarkerFixture).
        let frameMaterial = FixtureStyle.white(DollhousePalette.frameWhite, roughness: 0.8)

        // Side jambs and head — the frame the wall cutout was cut for.
        let left = FixtureStyle.detailBox(width: jamb, height: spec.height, length: depth,
                                          material: frameMaterial)
        left.position.x = Float(-spec.width / 2 + jamb / 2)
        container.addChildNode(left)

        let right = FixtureStyle.detailBox(width: jamb, height: spec.height, length: depth,
                                           material: frameMaterial)
        right.position.x = Float(spec.width / 2 - jamb / 2)
        container.addChildNode(right)

        let head = FixtureStyle.detailBox(width: spec.width, height: jamb, length: depth,
                                          material: frameMaterial)
        head.position.y = Float(spec.height / 2 - jamb / 2)
        container.addChildNode(head)

        // The leaf, hinged on the left jamb and standing ajar.
        let innerWidth = max(spec.width - jamb * 2, 0.05)
        let leafHeight = max(spec.height - jamb, 0.05)
        let leafThickness = 0.045
        // The leaf sits proud and catches light, so it runs a hair brighter than the frame.
        // Standing ajar is what makes it read instantly as a door in monochrome — and the swing
        // wedge quietly communicates circulation, which is what an escape-plan app is about.
        let leafMaterial = FixtureStyle.white(DollhousePalette.doorLeafWhite, roughness: 0.72)

        let hinge = SCNNode()
        hinge.position = SCNVector3(Float(-innerWidth / 2), Float(-jamb / 2), 0)
        hinge.eulerAngles.y = ajarAngle
        container.addChildNode(hinge)

        let leaf = FixtureStyle.detailBox(width: innerWidth - 0.008, height: leafHeight,
                                          length: leafThickness, chamfer: 0.01,
                                          material: leafMaterial)
        leaf.position.x = Float(innerWidth / 2)
        hinge.addChildNode(leaf)

        // Handle on each face, near the free edge, at hand height within the leaf.
        let handleMaterial = FixtureStyle.white(DollhousePalette.doorLeafWhite, roughness: 0.5)
        for side: Float in [1, -1] {
            let knob = SCNSphere(radius: 0.024)
            knob.firstMaterial = handleMaterial
            let node = SCNNode(geometry: knob)
            node.renderingOrder = RenderOrder.fixtures
            node.castsShadow = false
            node.position = SCNVector3(Float(innerWidth / 2 - 0.07),
                                       Float(-leafHeight * 0.04),
                                       side * Float(leafThickness / 2 + 0.014))
            leaf.addChildNode(node)
        }

        return container
    }
}
