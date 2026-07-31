//  WindowFixture.swift
//  escape_plan
//
//  The default window: a frame with a protruding sill ledge, cross mullions, and a translucent
//  pane. Egress-exit windows keep the palette's bright teal frame so they stay findable. Local
//  frame per the FixtureKit contract: origin at the cutout center.

import SceneKit

struct StyledWindowFixture: WindowFixtureBuilding {

    func node(for spec: OpeningFixtureSpec) -> SCNNode {
        let container = SCNNode()

        let section = FixtureStyle.frameSectionM * 0.85
        let depth = spec.wallThickness + FixtureStyle.frameRevealM * 2
        let frameMaterial = FixtureStyle.material(
            DollhousePalette.openingFrame(kind: .window, isExit: spec.isExit), roughness: 0.75)

        // Frame: two uprights, a head, and a sill ledge that stands proud of the wall faces.
        for side: Float in [-1, 1] {
            let upright = FixtureStyle.detailBox(width: section, height: spec.height,
                                                 length: depth, material: frameMaterial)
            upright.position.x = side * Float(spec.width / 2 - section / 2)
            container.addChildNode(upright)
        }

        let head = FixtureStyle.detailBox(width: spec.width, height: section, length: depth,
                                          material: frameMaterial)
        head.position.y = Float(spec.height / 2 - section / 2)
        container.addChildNode(head)

        let sill = FixtureStyle.detailBox(width: spec.width + 0.05, height: 0.045,
                                          length: depth + 0.05, material: frameMaterial)
        sill.position.y = Float(-spec.height / 2 + 0.0225)
        container.addChildNode(sill)

        // Cross mullions — the detail that makes a pane read as a window at dollhouse scale.
        let innerWidth = max(spec.width - section * 2, 0.04)
        let innerHeight = max(spec.height - section - 0.045, 0.04)
        let mullionMaterial = frameMaterial

        let vertical = FixtureStyle.detailBox(width: 0.024, height: innerHeight, length: 0.03,
                                              chamfer: 0.002, material: mullionMaterial)
        vertical.position.y = Float(-0.0225 + section / 2)
        container.addChildNode(vertical)

        let horizontal = FixtureStyle.detailBox(width: innerWidth, height: 0.024, length: 0.03,
                                                chamfer: 0.002, material: mullionMaterial)
        horizontal.position.y = vertical.position.y
        container.addChildNode(horizontal)

        // The pane: translucent, low-roughness, depth-write-off like the walls, drawn in the
        // glass band so it blends over the wall segments that surround it.
        let glass = SCNBox(width: CGFloat(innerWidth), height: CGFloat(innerHeight),
                           length: 0.012, chamferRadius: 0)
        let glassMaterial = FixtureStyle.material(DollhousePalette.windowGlass, roughness: 0.08)
        glassMaterial.transparency = 0.42
        glassMaterial.isDoubleSided = true
        glassMaterial.writesToDepthBuffer = false
        glass.firstMaterial = glassMaterial

        let pane = SCNNode(geometry: glass)
        pane.position.y = vertical.position.y
        pane.renderingOrder = RenderOrder.glass
        pane.castsShadow = false
        container.addChildNode(pane)

        return container
    }
}
