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

    func testExplodedViewSeparatesFloorsAndReturnsToRest() throws {
        let home = try FixtureLibrary.load(.twostory)
        let dollhouse = DollhouseSceneBuilder.build(home).dollhouse
        let upper = try XCTUnwrap(dollhouse.floors.first { $0.level == 1 })
        let ground = try XCTUnwrap(dollhouse.floors.first { $0.level == 0 })

        dollhouse.setExplode(0)
        XCTAssertEqual(upper.node.position.y, Float(upper.baseY), accuracy: 1e-4)

        dollhouse.setExplode(1)
        XCTAssertGreaterThan(upper.node.position.y, Float(upper.baseY),
                             "the upper floor must lift when exploded")
        XCTAssertEqual(ground.node.position.y, Float(ground.baseY), accuracy: 1e-4,
                       "the bottom floor stays put — everything separates upward from it")

        dollhouse.setExplode(0)
        XCTAssertEqual(upper.node.position.y, Float(upper.baseY), accuracy: 1e-4)
    }

    func testExplodeAmountIsClamped() throws {
        let home = try FixtureLibrary.load(.twostory)
        let dollhouse = DollhouseSceneBuilder.build(home).dollhouse
        let upper = try XCTUnwrap(dollhouse.floors.first { $0.level == 1 })

        dollhouse.setExplode(1)
        let atMax = upper.node.position.y
        dollhouse.setExplode(9)
        XCTAssertEqual(upper.node.position.y, atMax, accuracy: 1e-4)

        dollhouse.setExplode(0)
        let atRest = upper.node.position.y
        dollhouse.setExplode(-5)
        XCTAssertEqual(upper.node.position.y, atRest, accuracy: 1e-4)
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
        let knownBands: Set<Int> = [RenderOrder.opaque, RenderOrder.objects, RenderOrder.fixtures,
                                    RenderOrder.walls, RenderOrder.glass,
                                    RenderOrder.glow, RenderOrder.routes, RenderOrder.labels,
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
        let box = try XCTUnwrap(node.geometry as? SCNBox)
        XCTAssertEqual(Double(box.width), 2.0, accuracy: 1e-6)
        XCTAssertEqual(Double(box.length), 0.9, accuracy: 1e-6)
        XCTAssertEqual(Double(box.height), 0.8, accuracy: 1e-6)
        // Sitting ON the slab: center at half height; plan (2.5, 2.0) → scene (2.5, _, -2.0).
        XCTAssertEqual(node.position.y, 0.4, accuracy: 1e-4)
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
