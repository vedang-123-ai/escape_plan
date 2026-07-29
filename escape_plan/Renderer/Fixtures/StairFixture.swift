//  StairFixture.swift
//  escape_plan
//
//  The default stair flight: open treads with a nosing, closed risers, side stringers, and a
//  handrail — the airy architectural-model staircase, not a ziggurat of boxes. Still an honest
//  proxy: the schema stores a footprint and a rise, so L and U runs render as a straight
//  flight across the footprint's long axis, exactly like the renderer always has.
//
//  Local frame per the FixtureKit contract: origin at the footprint center at floor level,
//  ascending along +x, treads spanning z ∈ [−width/2, width/2].

import SceneKit

struct StyledStairFixture: StairFixtureBuilding {

    func node(for spec: StairFixtureSpec) -> SCNNode {
        let container = SCNNode()

        let stepCount = max(3, Int((spec.rise / FixtureStyle.targetRiserM).rounded()))
        let treadDepth = spec.runLength / Double(stepCount)
        let stepRise = spec.rise / Double(stepCount)
        let treadThickness = 0.05
        let stringerInset = 0.045
        let treadWidth = max(spec.width - stringerInset * 2, 0.2)

        let treadMaterial = FixtureStyle.material(DollhousePalette.stairTread, roughness: 0.8)
        let riserMaterial = FixtureStyle.material(DollhousePalette.stairRiser)
        let stringerMaterial = FixtureStyle.material(DollhousePalette.stairStringer)
        let railMaterial = FixtureStyle.material(DollhousePalette.stairRail, roughness: 0.6)

        for i in 0..<stepCount {
            // Tread: a thin slab with a 2 cm nosing overhanging the riser below it.
            let tread = FixtureStyle.detailBox(width: treadDepth + 0.02, height: treadThickness,
                                               length: treadWidth, chamfer: 0.008,
                                               material: treadMaterial)
            tread.position = SCNVector3(
                Float(-spec.runLength / 2 + (Double(i) + 0.5) * treadDepth - 0.01),
                Float(Double(i + 1) * stepRise - treadThickness / 2),
                0)
            container.addChildNode(tread)

            // Closed riser under the tread's front edge.
            let riser = FixtureStyle.detailBox(width: 0.018, height: stepRise,
                                               length: treadWidth, chamfer: 0.002,
                                               material: riserMaterial)
            riser.position = SCNVector3(
                Float(-spec.runLength / 2 + Double(i) * treadDepth + 0.009),
                Float(Double(i) * stepRise + stepRise / 2),
                0)
            container.addChildNode(riser)
        }

        // Stringers: one sloped beam per side, carrying the flight.
        let slope = atan2(spec.rise, spec.runLength)
        let slopeLength = (spec.runLength * spec.runLength + spec.rise * spec.rise).squareRoot()
        for side: Float in [-1, 1] {
            let stringer = FixtureStyle.detailBox(width: slopeLength, height: 0.15,
                                                  length: stringerInset - 0.005, chamfer: 0.01,
                                                  material: stringerMaterial)
            stringer.eulerAngles.z = Float(slope)
            stringer.position = SCNVector3(0, Float(spec.rise / 2 + 0.02),
                                           side * Float(spec.width / 2 - stringerInset / 2))
            container.addChildNode(stringer)
        }

        // Handrail on one side (both when the flight is generous) — rail plus a few posts.
        let railHeight = 0.85
        let railSides: [Float] = spec.width >= 0.95 ? [-1, 1] : [1]
        for side in railSides {
            let z = side * Float(spec.width / 2 - 0.02)

            let rail = FixtureStyle.detailBox(width: slopeLength * 0.96, height: 0.035,
                                              length: 0.04, chamfer: 0.012,
                                              material: railMaterial)
            rail.eulerAngles.z = Float(slope)
            rail.position = SCNVector3(0, Float(spec.rise / 2 + railHeight), z)
            container.addChildNode(rail)

            for fraction in [0.1, 0.5, 0.9] {
                let post = FixtureStyle.detailBox(width: 0.028, height: railHeight,
                                                  length: 0.028, chamfer: 0.004,
                                                  material: railMaterial)
                post.position = SCNVector3(
                    Float(-spec.runLength / 2 + fraction * spec.runLength),
                    Float(fraction * spec.rise + railHeight / 2),
                    z)
                container.addChildNode(post)
            }
        }

        return container
    }
}
