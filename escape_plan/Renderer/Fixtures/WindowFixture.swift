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
        let frameMaterial = FixtureStyle.white(DollhousePalette.frameWhite, roughness: 0.75)

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

        let paneY = Float(-0.0225 + section / 2)

        // A center mullion only once the opening is wide enough to need one; narrow windows
        // read cleaner as a single light.
        if spec.width > 1.1 {
            let vertical = FixtureStyle.detailBox(width: 0.024, height: innerHeight, length: 0.03,
                                                  chamfer: 0.002, material: mullionMaterial)
            vertical.position.y = paneY
            container.addChildNode(vertical)
        }

        let horizontal = FixtureStyle.detailBox(width: innerWidth, height: 0.024, length: 0.03,
                                                chamfer: 0.002, material: mullionMaterial)
        horizontal.position.y = paneY
        container.addChildNode(horizontal)

        // The pane is all but invisible: 8% white at very low roughness. A window in a white
        // model reads by its bright frame and a specular glint off the glazing, never by a blue
        // tint — the old pale-blue pane was one more hue competing with the routes.
        let glass = SCNBox(width: CGFloat(innerWidth), height: CGFloat(innerHeight),
                           length: 0.012, chamferRadius: 0)
        let glassMaterial = FixtureStyle.material(DollhousePalette.glassWhite, roughness: 0.05)
        glassMaterial.transparency = DollhousePalette.glassTransparency
        glassMaterial.isDoubleSided = true
        glassMaterial.writesToDepthBuffer = false
        glass.firstMaterial = glassMaterial

        let pane = SCNNode(geometry: glass)
        pane.position.y = paneY
        pane.renderingOrder = RenderOrder.glass
        pane.castsShadow = false
        container.addChildNode(pane)

        return container
    }
}
