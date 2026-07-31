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

        let topColor = DollhousePalette.accent(for: spec.roomType)
            .blended(with: DollhousePalette.slab, amount: 1 - DollhousePalette.roomAccentStrength)
        // SCNShape's elements are [front, back, extrusion sides]; after the −90° x-rotation
        // below, front faces up and back faces down.
        shape.materials = [
            FixtureStyle.material(topColor),
            FixtureStyle.material(DollhousePalette.slabUnderside),
            FixtureStyle.material(DollhousePalette.slabSide),
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

/// The diorama table: a chamfered plate under the ground floor that catches the key light's
/// shadow, so the house reads as a grounded model rather than floating in the backdrop.
enum BasePlateFixture {

    static func node(bounds: DollhouseGeometry.PlanBounds, groundSlabThickness: Double) -> SCNNode? {
        guard !bounds.isEmpty else { return nil }
        let margin = 1.1
        let thickness = 0.09
        let plate = SCNBox(width: CGFloat(bounds.width + margin * 2),
                           height: CGFloat(thickness),
                           length: CGFloat(bounds.depth + margin * 2),
                           chamferRadius: 0.045)
        plate.firstMaterial = FixtureStyle.material(DollhousePalette.basePlate, roughness: 0.95)

        let node = SCNNode(geometry: plate)
        node.name = "basePlate"
        // Top sits 5 mm INTO the ground slabs' underside — embedded, so no coplanar faces to
        // z-fight and no visible gap.
        let top = -groundSlabThickness + 0.005
        node.position = SCNVector3(Float(bounds.center.x),
                                   Float(top - thickness / 2),
                                   Float(-bounds.center.y))
        node.renderingOrder = RenderOrder.opaque
        node.castsShadow = false
        return node
    }
}
