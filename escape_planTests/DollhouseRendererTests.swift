import SceneKit
import XCTest
@testable import escape_plan

/// S1.3 renderer tests. The acceptance criterion is visual ("renders correctly and legibly"), so
/// these cover the part a screenshot can't: that every fixture decodes, that every opening's
/// parametric wall reference actually resolves, and that the floor controls do what they claim.
final class DollhouseRendererTests: XCTestCase {

    // MARK: - Fixtures

    func testAllFixturesDecode() throws {
        for fixture in Fixture.allCases {
            let home = try FixtureLibrary.load(fixture)
            XCTAssertEqual(home.schema_version, "1.1", "\(fixture.rawValue) is not schema v1.1")
            XCTAssertFalse(home.floors.isEmpty, "\(fixture.rawValue) has no floors")
        }
    }

    /// The bundled copies exist only because an app bundle can't read `schema/fixtures/`. If they
    /// drift from the originals, the renderer is being validated against a home nobody else has.
    func testBundledFixturesMatchSchemaFixtures() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // escape_planTests/
            .deletingLastPathComponent()  // repo root

        for fixture in Fixture.allCases {
            let canonical = repoRoot
                .appendingPathComponent("schema/fixtures/\(fixture.rawValue).json")
            let bundled = repoRoot
                .appendingPathComponent("escape_plan/Fixtures/\(fixture.rawValue).json")

            let a = try Data(contentsOf: canonical)
            let b = try Data(contentsOf: bundled)
            XCTAssertEqual(a, b, """
                escape_plan/Fixtures/\(fixture.rawValue).json has drifted from \
                schema/fixtures/\(fixture.rawValue).json. Re-copy it.
                """)
        }
    }

    // MARK: - Geometry

    func testPointOnEdgeFollowsSchemaEdgeConvention() {
        // Edge i runs vertex i → vertex (i+1) % n. Edge 1 of this square is (4,0) → (4,8).
        let square: [Point] = [Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 4, y: 8), Point(x: 0, y: 8)]

        let start = DollhouseGeometry.pointOnEdge(square, edgeIndex: 1, t: 0)
        XCTAssertEqual(start?.x ?? .nan, 4, accuracy: 1e-9)
        XCTAssertEqual(start?.y ?? .nan, 0, accuracy: 1e-9)

        let mid = DollhouseGeometry.pointOnEdge(square, edgeIndex: 1, t: 0.5)
        XCTAssertEqual(mid?.x ?? .nan, 4, accuracy: 1e-9)
        XCTAssertEqual(mid?.y ?? .nan, 4, accuracy: 1e-9)

        // The closing edge (last → first) is implicit and must be indexable.
        let closing = DollhouseGeometry.pointOnEdge(square, edgeIndex: 3, t: 0.5)
        XCTAssertEqual(closing?.x ?? .nan, 0, accuracy: 1e-9)
        XCTAssertEqual(closing?.y ?? .nan, 4, accuracy: 1e-9)

        XCTAssertNil(DollhouseGeometry.pointOnEdge(square, edgeIndex: 4, t: 0.5),
                     "edge_index past the vertex count must not resolve")
    }

    func testPlanToSceneMapsYToNegativeZ() {
        let v = DollhouseGeometry.scenePoint(Point(x: 3, y: 5), y: 2)
        XCTAssertEqual(v.x, 3, accuracy: 1e-6)
        XCTAssertEqual(v.y, 2, accuracy: 1e-6)
        XCTAssertEqual(v.z, -5, accuracy: 1e-6)
    }

    func testCentroidOfSquare() {
        let square: [Point] = [Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 4, y: 8), Point(x: 0, y: 8)]
        let c = DollhouseGeometry.centroid(square)
        XCTAssertEqual(c.x, 2, accuracy: 1e-9)
        XCTAssertEqual(c.y, 4, accuracy: 1e-9)
    }

    func testCentroidOfDegeneratePolygonFallsBackInsteadOfProducingNaN() {
        // Zero-area polygon: the area-weighted formula divides by zero.
        let line: [Point] = [Point(x: 0, y: 0), Point(x: 2, y: 0), Point(x: 4, y: 0)]
        let c = DollhouseGeometry.centroid(line)
        XCTAssertFalse(c.x.isNaN)
        XCTAssertFalse(c.y.isNaN)
        XCTAssertEqual(c.x, 2, accuracy: 1e-9)
    }

    func testSharedWallsAreDeduplicated() throws {
        // twostory's ground floor is three rooms in a row sharing two walls: 3 × 4 edges = 12,
        // minus 2 shared duplicates = 10 distinct walls.
        let home = try FixtureLibrary.load(.twostory)
        let ground = try XCTUnwrap(home.floors.first { $0.level == 0 })
        let walls = DollhouseGeometry.walls(for: ground)
        XCTAssertEqual(walls.count, 10, "coplanar duplicate walls would z-fight")
    }

    func testFloorsStackByLevelNotArrayOrder() throws {
        let home = try FixtureLibrary.load(.twostory)
        let heights = DollhouseGeometry.floorBaseHeights(of: home)
        let ground = try XCTUnwrap(home.floors.first { $0.level == 0 })
        let upper = try XCTUnwrap(home.floors.first { $0.level == 1 })
        XCTAssertEqual(heights[ground.id] ?? .nan, 0, accuracy: 1e-9)
        XCTAssertEqual(heights[upper.id] ?? .nan, ground.height_m, accuracy: 1e-9,
                       "the upper floor must sit on the ground floor's ceiling")
    }

    // MARK: - Opening placement

    /// The whole point of parametric placement: every opening in every fixture must resolve from
    /// (room, edge_index, t) alone. A nil here means the renderer would be dropping a door.
    func testEveryOpeningInEveryFixtureResolvesParametrically() throws {
        for fixture in Fixture.allCases {
            let home = try FixtureLibrary.load(fixture)
            for floor in home.floors {
                for opening in floor.openings {
                    XCTAssertNotNil(
                        DollhouseGeometry.placement(for: opening, on: floor),
                        "\(fixture.rawValue): opening '\(opening.id)' failed to resolve"
                    )
                }
            }
        }
    }

    func testOpeningIsCenteredOnItsTRangeAndSizedByWidth() throws {
        let home = try FixtureLibrary.load(.twostory)
        let ground = try XCTUnwrap(home.floors.first { $0.level == 0 })
        // d_front: hall edge 0 runs (4,0) → (6,0), t0 0.28 / t1 0.73 → midpoint t = 0.505.
        let front = try XCTUnwrap(ground.openings.first { $0.id == "d_front" })
        let p = try XCTUnwrap(DollhouseGeometry.placement(for: front, on: ground))

        XCTAssertEqual(p.center.x, 4 + 2 * 0.505, accuracy: 1e-9)
        XCTAssertEqual(p.center.y, 0, accuracy: 1e-9)
        // width_m is authoritative for size — not the t-span, which is placement.
        XCTAssertEqual(p.width, front.width_m, accuracy: 1e-9)
        XCTAssertEqual(p.sill, 0, accuracy: 1e-9)
    }

    func testOpeningWiderThanItsWallIsClampedRatherThanOverhanging() throws {
        let home = try FixtureLibrary.load(.twostory)
        let ground = try XCTUnwrap(home.floors.first { $0.level == 0 })
        var absurd = try XCTUnwrap(ground.openings.first { $0.id == "d_front" })
        absurd.width_m = 99  // hall edge 0 is only 2 m long

        let p = try XCTUnwrap(DollhouseGeometry.placement(for: absurd, on: ground))
        XCTAssertEqual(p.width, 2, accuracy: 1e-9, "marker must not be wider than its wall")
        XCTAssertGreaterThanOrEqual(p.center.x, 4 - 1e-9)
        XCTAssertLessThanOrEqual(p.center.x, 6 + 1e-9)
    }

    func testDanglingWallSegmentReferenceIsReportedNotSilentlyPlaced() throws {
        let home = try FixtureLibrary.load(.twostory)
        var ground = try XCTUnwrap(home.floors.first { $0.level == 0 })
        ground.openings[0].wall_segment = WallSegmentRef(room_id: "r_does_not_exist", edge_index: 0, t0: 0.1, t1: 0.2)

        XCTAssertNil(DollhouseGeometry.placement(for: ground.openings[0], on: ground))
    }

    // MARK: - Scene building

    func testAllFixturesBuildWithoutGeometryIssues() throws {
        for fixture in Fixture.allCases {
            let home = try FixtureLibrary.load(fixture)
            let built = DollhouseSceneBuilder.build(home)
            XCTAssertTrue(built.issues.isEmpty,
                          "\(fixture.rawValue): \(built.issues.map(\.message).joined(separator: "; "))")
            XCTAssertEqual(built.dollhouse.floors.count, home.floors.count)
        }
    }

    func testSceneContainsANodeForEveryRoomAndOpening() throws {
        let home = try FixtureLibrary.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)

        for floor in home.floors {
            for room in floor.rooms {
                XCTAssertNotNil(built.dollhouse.scene.rootNode.childNode(withName: "room:\(room.id)",
                                                                        recursively: true),
                                "no slab for room \(room.id)")
            }
            for opening in floor.openings {
                XCTAssertNotNil(built.dollhouse.scene.rootNode.childNode(withName: "opening:\(opening.id)",
                                                                        recursively: true),
                                "no marker for opening \(opening.id)")
            }
        }
        XCTAssertNotNil(built.dollhouse.scene.rootNode.childNode(withName: "stairs:s_main", recursively: true))
    }

    /// The flagship interaction: exactly one floor is solid and every other floor ghosts.
    /// Replaces the exploded-view tests — floors no longer move at all.
    func testActiveFloorIsSolidAndOthersGhost() throws {
        let home = try FixtureLibrary.load(.twostory)
        let dollhouse = DollhouseSceneBuilder.build(home).dollhouse
        let upper = try XCTUnwrap(dollhouse.floors.first { $0.level == 1 })
        let ground = try XCTUnwrap(dollhouse.floors.first { $0.level == 0 })

        dollhouse.setActiveFloor(ground.id, animated: false)
        XCTAssertEqual(dollhouse.activeFloorID, ground.id)

        // Nothing translates: the house is one object, always.
        XCTAssertEqual(upper.node.position.y, Float(upper.baseY), accuracy: 1e-4)
        XCTAssertEqual(ground.node.position.y, Float(ground.baseY), accuracy: 1e-4)

        let groundWall = try XCTUnwrap(ground.entries.first { $0.part == .structure })
        XCTAssertEqual(groundWall.node.geometry?.firstMaterial?.transparency ?? 0, 1.0,
                       accuracy: 1e-6, "the active floor must be fully opaque")

        let upperWall = try XCTUnwrap(upper.entries.first { $0.part == .structure })
        XCTAssertEqual(upperWall.node.geometry?.firstMaterial?.transparency ?? 0,
                       DollhousePalette.ghostOpacityAbove, accuracy: 1e-6,
                       "a floor ABOVE the active one ghosts to the 'above' opacity")
        XCTAssertFalse(upperWall.node.castsShadow, "ghosted geometry must not cast")

        // …and flipping focus flips the treatment.
        dollhouse.setActiveFloor(upper.id, animated: false)
        let groundWallAfter = try XCTUnwrap(ground.entries.first { $0.part == .structure })
        XCTAssertEqual(groundWallAfter.node.geometry?.firstMaterial?.transparency ?? 0,
                       DollhousePalette.ghostOpacityBelow, accuracy: 1e-6,
                       "a floor BELOW the active one ghosts less — you look down through the top")
    }

    /// Slabs ghost heavier than walls (their silhouette is what communicates a jagged
    /// footprint), and the outline that makes a ghosted footprint legible only shows while
    /// ghosted.
    func testGhostSlabsAreHeavierThanGhostWallsAndOutlinesOnlyShowWhenGhosted() throws {
        let home = try FixtureLibrary.load(.jagged)
        let dollhouse = DollhouseSceneBuilder.build(home).dollhouse
        let basement = try XCTUnwrap(dollhouse.floors.first { $0.level == -1 })
        let ground = try XCTUnwrap(dollhouse.floors.first { $0.level == 0 })

        dollhouse.setActiveFloor(ground.id, animated: false)

        let slab = try XCTUnwrap(basement.entries.first { $0.part == .slab })
        let wall = try XCTUnwrap(basement.entries.first { $0.part == .structure })
        XCTAssertGreaterThan(slab.node.geometry?.firstMaterial?.transparency ?? 0,
                             wall.node.geometry?.firstMaterial?.transparency ?? 0)
        XCTAssertLessThanOrEqual(slab.node.geometry?.firstMaterial?.transparency ?? 0,
                                 DollhousePalette.ghostSlabOpacityCap)

        let outline = try XCTUnwrap(basement.entries.first { $0.part == .outline })
        XCTAssertFalse(outline.node.isHidden, "a ghosted floor shows its slab outline")
        let label = try XCTUnwrap(basement.entries.first { $0.part == .hidden })
        XCTAssertTrue(label.node.isHidden, "ghosted floors hide labels, glass and markers")

        dollhouse.setActiveFloor(basement.id, animated: false)
        XCTAssertTrue(outline.node.isHidden, "the active floor hides the outline again")
        XCTAssertFalse(label.node.isHidden)
    }

    /// The tour flies at eye level through the whole stack, so it must not fly through fog.
    func testTourSolidifiesEveryFloor() throws {
        let home = try FixtureLibrary.load(.twostory)
        let dollhouse = DollhouseSceneBuilder.build(home).dollhouse
        let ground = try XCTUnwrap(dollhouse.floors.first { $0.level == 0 })
        dollhouse.setActiveFloor(ground.id, animated: false)

        dollhouse.setAllFloorsSolid()
        for floor in dollhouse.floors {
            for entry in floor.entries where entry.part == .structure {
                XCTAssertEqual(entry.node.geometry?.firstMaterial?.transparency ?? 0, 1.0,
                               accuracy: 1e-6)
            }
        }
    }

    /// The jagged stack is the acceptance model: three levels whose footprints do not line up.
    func testJaggedFixtureBuildsThreeMisalignedFloors() throws {
        let home = try FixtureLibrary.load(.jagged)
        let built = DollhouseSceneBuilder.build(home)
        XCTAssertTrue(built.issues.isEmpty,
                      "jagged fixture must build clean: \(built.issues.map(\.message))")
        XCTAssertEqual(built.dollhouse.floors.count, 3)
        XCTAssertEqual(built.dollhouse.floors.map(\.level), [-1, 0, 1],
                       "floors stack by level, so the basement is first")
        // The base plate sizes to the UNION and sits at the LOWEST floor's base, which is
        // below zero once a basement exists.
        let plate = try XCTUnwrap(built.dollhouse.scene.rootNode.childNode(withName: "basePlate",
                                                                           recursively: true))
        let plateBox = try XCTUnwrap(plate.childNodes.first?.geometry as? SCNBox)
        XCTAssertGreaterThan(Double(plateBox.width), 20.0, "plate spans the widest floor + apron")
        XCTAssertLessThan(plate.childNodes.first?.position.y ?? 0, 0,
                          "a basement pushes the plinth below the ground floor")
    }

    func testFloorVisibilityToggles() throws {
        let home = try FixtureLibrary.load(.twostory)
        let dollhouse = DollhouseSceneBuilder.build(home).dollhouse
        let upper = try XCTUnwrap(dollhouse.floors.first { $0.level == 1 })

        XCTAssertTrue(dollhouse.isFloorVisible(upper.id))
        dollhouse.setFloor(upper.id, visible: false)
        XCTAssertFalse(dollhouse.isFloorVisible(upper.id))
        XCTAssertTrue(upper.node.isHidden)
        dollhouse.setFloor(upper.id, visible: true)
        XCTAssertTrue(dollhouse.isFloorVisible(upper.id))
    }

    /// The see-through look depends on draw order (translucent surfaces don't write depth), so
    /// every geometry node must sit in a RenderOrder band — and translucency must line up with
    /// order: anything that doesn't write depth must draw after the opaque interior. A stray
    /// hand-set renderingOrder is the kind of regression that only shows up as "walls look
    /// wrong from some angles".
    func testEveryNodeSitsInItsRenderOrderBand() throws {
        let knownBands: Set<Int> = [RenderOrder.opaque, RenderOrder.opaque + 1,
                                    RenderOrder.objects, RenderOrder.fixtures,
                                    RenderOrder.walls, RenderOrder.glass,
                                    RenderOrder.ghostSlab, RenderOrder.ghostSlab + 1,
                                    RenderOrder.ghostWall,
                                    RenderOrder.routes, RenderOrder.routes - 1,
                                    RenderOrder.routes + 1,
                                    RenderOrder.exitMarkers, RenderOrder.labels,
                                    RenderOrder.badges, RenderOrder.badgeGlyphs]
        for fixture in Fixture.allCases {
            let home = try FixtureLibrary.load(fixture)
            let built = DollhouseSceneBuilder.build(home)
            built.dollhouse.scene.rootNode.enumerateHierarchy { node, _ in
                guard let geometry = node.geometry else { return }
                XCTAssertTrue(knownBands.contains(node.renderingOrder),
                              "\(fixture.rawValue): geometry node '\(node.name ?? "unnamed")' has renderingOrder \(node.renderingOrder), which is not a RenderOrder band")
                // Depth-write-off translucency only works when the node draws after opaque.
                if let material = geometry.firstMaterial, !material.writesToDepthBuffer {
                    XCTAssertGreaterThan(node.renderingOrder, RenderOrder.opaque,
                                         "\(fixture.rawValue): '\(node.name ?? "unnamed")' is translucent (no depth write) but draws in the opaque band")
                }
            }
        }
    }

    func testObjectRendersAsARotatedPrismInItsBand() throws {
        var home = try FixtureLibrary.load(.bungalow)
        home.floors[0].objects.append(FloorObject(
            id: "o_test", category: .sofa, center: Point(x: 2.5, y: 2.0),
            size_m: [2.0, 0.9], height_m: 0.8, rotation_deg: 90, source: .manual))
        let built = DollhouseSceneBuilder.build(home)
        XCTAssertTrue(built.issues.isEmpty)

        let node = try XCTUnwrap(built.dollhouse.scene.rootNode.childNode(withName: "object:o_test",
                                                                          recursively: true))
        XCTAssertEqual(node.renderingOrder, RenderOrder.objects)
        // Furniture is a white mini assembled from several parts now (seat + back + arms for a
        // sofa), not one prism — but it must still be ONE node with that name, because the
        // editor's selection and drag key off it.
        XCTAssertNil(node.geometry, "the mini is a container; its parts are children")
        XCTAssertFalse(node.childNodes.isEmpty)
        let (minB, maxB) = node.boundingBox
        XCTAssertEqual(Double(maxB.x - minB.x), 2.0, accuracy: 0.12)
        XCTAssertEqual(Double(maxB.z - minB.z), 0.9, accuracy: 0.12)
        XCTAssertEqual(Double(maxB.y - minB.y), 0.8, accuracy: 0.12)
        // Sitting ON the slab: the mini's origin is at floor level, not at half height.
        XCTAssertEqual(node.position.y, 0.0, accuracy: 1e-4)
        XCTAssertEqual(node.position.z, -2.0, accuracy: 1e-4)
        XCTAssertEqual(Double(node.eulerAngles.y), .pi / 2, accuracy: 1e-6)
    }

    func testMalformedObjectIsSurfacedAsABuildIssueNotACrash() throws {
        var home = try FixtureLibrary.load(.bungalow)
        home.floors[0].objects.append(FloorObject(
            id: "o_bad", category: .other, center: Point(x: 1, y: 1),
            size_m: [2.0], height_m: 0.8, source: .manual))
        let built = DollhouseSceneBuilder.build(home)
        XCTAssertTrue(built.issues.contains { $0.entityID == "o_bad" })
        XCTAssertNil(built.dollhouse.scene.rootNode.childNode(withName: "object:o_bad",
                                                              recursively: true))
    }

    func testSingleFloorFixturesHaveExactlyOneFloor() throws {
        for fixture in [Fixture.bungalow, .apartment] {
            let home = try FixtureLibrary.load(fixture)
            XCTAssertEqual(home.floors.count, 1, "\(fixture.rawValue) is expected to be single-storey")
        }
    }
}
