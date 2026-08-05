//  FloorFixture.swift
//  escape_plan
//
//  The default floor slab, plus the base plate the whole model sits on.
//
//  The slab keeps the extruded-polygon approach but gives each face its own material — accent
//  blend on top, darker cut edge on the sides — so stacked floors read as crisp diorama
//  slices. Per the FixtureKit contract, the returned node is in FLOOR space: the plan → scene
//  mapping (x, y) → (x, −z) is baked in and the top surface sits at y = 0.

import SceneKit
import UIKit

struct StyledFloorSlabFixture: FloorSlabBuilding {

    func node(for spec: SlabFixtureSpec) -> SCNNode? {
        guard let path = DollhouseGeometry.path(for: spec.polygon) else { return nil }
        let shape = SCNShape(path: UIBezierPath(cgPath: path),
                             extrusionDepth: CGFloat(spec.thickness))

        // No per-room-type tinting any more: rooms are separated by their walls and named by
        // their labels, not by pastel floor patches. `spec.roomType` stays in the contract for
        // custom builders that want it.
        //
        // SCNShape's elements are [front, back, extrusion sides]; after the −90° x-rotation
        // below, front faces up and back faces down.
        shape.materials = [
            FixtureStyle.white(DollhousePalette.floorWhite),
            FixtureStyle.white(DollhousePalette.slabEdge),
            FixtureStyle.white(DollhousePalette.slabEdge),
        ]

        let node = SCNNode(geometry: shape)
        // SCNShape lays its path out in local XY and extrudes along local z, centered on 0.
        // Rotating −90° about x maps plan (x, y) → scene (x, −z) and the extrusion axis to +y,
        // so the slab ends up flat with its top face at the floor's base height.
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, Float(-spec.thickness / 2), 0)
        node.renderingOrder = RenderOrder.opaque
        return node
    }
}

/// The plinth the model sits on: a chamfered plate that catches the key light's shadow, so the
/// house reads as a grounded maquette rather than floating in the backdrop, plus a soft
/// contact shadow that grounds it the way a studio photo does.
///
/// It sizes to the UNION of every floor's footprint and sits at the LOWEST floor's base — so a
/// small basement pushes the plate down and the wide ground floor visibly overhangs it, exactly
/// like a model on a plinth showing its foundation pit.
enum BasePlateFixture {

    /// Apron of bare plate around the widest footprint.
    private static let marginM = 0.8
    private static let thicknessM = 0.09

    static func node(bounds: DollhouseGeometry.PlanBounds,
                     lowestBaseY: Double,
                     slabThickness: Double) -> SCNNode? {
        guard !bounds.isEmpty else { return nil }
        let holder = SCNNode()
        holder.name = "basePlate"

        let plate = SCNBox(width: CGFloat(bounds.width + marginM * 2),
                           height: CGFloat(thicknessM),
                           length: CGFloat(bounds.depth + marginM * 2),
                           chamferRadius: 0.045)
        plate.firstMaterial = FixtureStyle.white(DollhousePalette.basePlate, roughness: 0.95)

        // Top sits 5 mm INTO the lowest slabs' underside — embedded, so there are no coplanar
        // faces to z-fight and no visible gap.
        let top = lowestBaseY - slabThickness + 0.005
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(Float(bounds.center.x),
                                        Float(top - thicknessM / 2),
                                        Float(-bounds.center.y))
        plateNode.renderingOrder = RenderOrder.opaque
        plateNode.castsShadow = false
        holder.addChildNode(plateNode)

        if let shadow = contactShadow(bounds: bounds, y: top) {
            holder.addChildNode(shadow)
        }
        return holder
    }

    /// A blurred dark ellipse painted on the plate under the model. The key light's real shadow
    /// map handles the crisp part; this is the soft ambient darkening that a shadow map alone
    /// never produces, and it is cheap.
    private static func contactShadow(bounds: DollhouseGeometry.PlanBounds, y: Double) -> SCNNode? {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                DollhousePalette.contactShadow
                    .withAlphaComponent(DollhousePalette.contactShadowAlpha).cgColor,
                DollhousePalette.contactShadow.withAlphaComponent(0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0.0, 1.0]) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: size.width / 2,
                                  options: .drawsAfterEndLocation)
        }

        let plane = SCNPlane(width: CGFloat(bounds.width + marginM * 1.4),
                             height: CGFloat(bounds.depth + marginM * 1.4))
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .constant
        material.isDoubleSided = false
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        // 3 mm above the plate so it paints ON the plate rather than z-fighting with it.
        node.position = SCNVector3(Float(bounds.center.x), Float(y + 0.003),
                                   Float(-bounds.center.y))
        node.renderingOrder = RenderOrder.opaque + 1
        node.castsShadow = false
        return node
    }
}
