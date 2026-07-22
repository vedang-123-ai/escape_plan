import SceneKit
import XCTest
@testable import escape_plan

/// S2.3 tests: the RoutePlan wire mirror against the committed engine samples, the pure route
/// geometry (floor-run splitting, smoothing, tube meshing), and the overlay's scene-graph
/// contract. The animated/visual half of the acceptance is a device check, like S1.3.
final class RoutePlanTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // escape_planTests/
        .deletingLastPathComponent()  // repo root

    private func loadSample(_ name: String) throws -> RoutePlan {
        let url = Self.repoRoot.appendingPathComponent("docs/route-samples/\(name).routeplan.json")
        return try HomeModel.decoder.decode(RoutePlan.self, from: Data(contentsOf: url))
    }

    // MARK: - Decoding the committed samples

    func testAllRouteSamplesDecode() throws {
        for name in ["apartment", "bungalow", "twostory", "twostory.mobility-limited"] {
            let plan = try loadSample(name)
            XCTAssertFalse(plan.rooms.isEmpty, "\(name) has no rooms")
            XCTAssertNil(plan.profile_id, "\(name) predates profiles and should decode without one")
        }
    }

    func testApartmentSampleCarriesNoSecondaryEgressFindings() throws {
        let plan = try loadSample("apartment")
        for room in plan.rooms {
            XCTAssertNotNil(room.primary, "\(room.room_id) should still have a primary route")
            XCTAssertNil(room.secondary, "\(room.room_id) has only one exit — no secondary")
            XCTAssertTrue(room.findings.contains { $0.kind == .no_secondary_egress },
                          "\(room.room_id) should be flagged no_secondary_egress")
        }
        XCTAssertFalse(plan.bottlenecks.isEmpty, "the single entry door is a bottleneck")
    }

    func testMobilityLimitedSampleCarriesNoViableRouteFindings() throws {
        let plan = try loadSample("twostory.mobility-limited")
        let trapped = plan.rooms.filter { room in
            room.findings.contains { $0.kind == .no_viable_route }
        }
        XCTAssertFalse(trapped.isEmpty, "avoid_stairs upstairs should strand at least one room")
        for room in trapped {
            XCTAssertNil(room.primary, "\(room.room_id): no_viable_route means no primary")
            XCTAssertNil(room.secondary, "\(room.room_id): no_viable_route means no secondary")
        }
    }

    func testDecodesWhenBackendDefaultedKeysAreOmitted() throws {
        // findings, bottlenecks, and the S3.4 penalty constraints all default server-side;
        // a payload omitting them must still decode.
        let json = """
        {
          "home_id": "h", "home_name": "H",
          "constraints": {"avoid_stairs": false, "avoid_windows": false, "max_sill_height_m": null},
          "rooms": [{
            "room_id": "r1", "room_name": "Room", "floor_id": "f1",
            "primary": null, "secondary": null
          }]
        }
        """
        let plan = try HomeModel.decoder.decode(RoutePlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.bottlenecks, [])
        XCTAssertEqual(plan.rooms[0].findings, [])
        XCTAssertNil(plan.constraints.stair_penalty_m)
    }

    func testRoutesRequestOmitsNilConstraintsAndProfile() throws {
        let home = try FixtureLibrary.load(.bungalow)
        let data = try HomeModel.encoder().encode(RoutesRequest(home: home))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["home"])
        // The backend 422s when constraints and profile_id arrive together; nil must mean
        // "key absent", not "key: null".
        XCTAssertFalse(object.keys.contains("constraints"))
        XCTAssertFalse(object.keys.contains("profile_id"))
    }

    // MARK: - Floor runs

    private func waypoint(_ x: Double, _ y: Double, floor: String, node: String,
                          kind: WaypointKind) -> Waypoint {
        Waypoint(x: x, y: y, floor_id: floor, node_id: node, kind: kind)
    }

    private var crossingRoute: Route {
        // The twostory shape: bedroom (f2) → stairs → hall (f1) → front door.
        Route(waypoints: [
            waypoint(2.0, 4.0, floor: "f2", node: "r_bed", kind: .room),
            waypoint(5.0, 6.0, floor: "f2", node: "s_main", kind: .stair),
            waypoint(5.0, 6.0, floor: "f1", node: "s_main", kind: .stair),
            waypoint(5.0, 4.0, floor: "f1", node: "r_hall", kind: .room),
            waypoint(5.0, 0.0, floor: "f1", node: "d_front", kind: .opening),
            waypoint(5.0, 0.0, floor: "f1", node: "EXTERIOR", kind: .exterior),
        ], length_m: 13.0, uses_stairs: true, uses_window: false, exit_id: "d_front")
    }

    func testFloorRunsSplitAtStairCrossing() {
        let (runs, dropped) = RouteGeometry.floorRuns(for: crossingRoute,
                                                     knownFloorIDs: ["f1", "f2"])
        XCTAssertEqual(dropped, [])
        XCTAssertEqual(runs.count, 2)

        XCTAssertEqual(runs[0].floorID, "f2")
        XCTAssertFalse(runs[0].startsAtStair)
        XCTAssertTrue(runs[0].endsAtStair)

        XCTAssertEqual(runs[1].floorID, "f1")
        XCTAssertTrue(runs[1].startsAtStair)
        XCTAssertFalse(runs[1].endsAtStair)

        // The crossing point appears in both runs, at the same plan position (floor-local y).
        let top = runs[0].points.last!
        let bottom = runs[1].points.first!
        XCTAssertEqual(top.x, bottom.x, accuracy: 1e-5)
        XCTAssertEqual(top.z, bottom.z, accuracy: 1e-5)

        // The duplicate exterior waypoint dedupes away: f1 keeps stair, hall, door.
        XCTAssertEqual(runs[1].points.count, 3)
    }

    func testFloorRunsDropUnknownFloors() {
        let (runs, dropped) = RouteGeometry.floorRuns(for: crossingRoute, knownFloorIDs: ["f1"])
        XCTAssertEqual(dropped, ["f2"])
        XCTAssertEqual(runs.map(\.floorID), ["f1"])
    }

    // MARK: - Smoothing & arc length

    func testCatmullRomPassesThroughControlPoints() {
        let control = [SCNVector3(0, 0, 0), SCNVector3(2, 0, 0), SCNVector3(2, 0, -3)]
        let smoothed = RouteGeometry.catmullRom(control, samplesPerSegment: 8)
        XCTAssertEqual(smoothed.count, 17)

        func contains(_ p: SCNVector3) -> Bool {
            smoothed.contains { abs($0.x - p.x) < 1e-4 && abs($0.y - p.y) < 1e-4 && abs($0.z - p.z) < 1e-4 }
        }
        for p in control {
            XCTAssertTrue(contains(p), "smoothed curve must pass through (\(p.x), \(p.y), \(p.z))")
        }
    }

    func testArcLengthsAreMonotoneAndDedupeDropsCoincidentPoints() {
        let points = [SCNVector3(0, 0, 0), SCNVector3(1, 0, 0),
                      SCNVector3(1, 0, 0), SCNVector3(1, 0, -2)]
        let deduped = RouteGeometry.dedupe(points)
        XCTAssertEqual(deduped.count, 3)

        let arcs = RouteGeometry.arcLengths(deduped)
        XCTAssertEqual(arcs.first, 0)
        XCTAssertEqual(arcs.last!, 3, accuracy: 1e-5)
        for i in 1..<arcs.count {
            XCTAssertGreaterThan(arcs[i], arcs[i - 1])
        }
    }

    func testPointAtDistanceInterpolatesAndClamps() {
        let points = [SCNVector3(0, 0, 0), SCNVector3(4, 0, 0)]
        let arcs = RouteGeometry.arcLengths(points)
        XCTAssertEqual(RouteGeometry.point(at: 1, along: points, arcs: arcs).x, 1, accuracy: 1e-5)
        XCTAssertEqual(RouteGeometry.point(at: -5, along: points, arcs: arcs).x, 0, accuracy: 1e-5)
        XCTAssertEqual(RouteGeometry.point(at: 99, along: points, arcs: arcs).x, 4, accuracy: 1e-5)
    }

    // MARK: - Tube mesh

    func testTubeMeshCountsAndDirectionalUVs() throws {
        let points = [SCNVector3(0, 0, 0), SCNVector3(1, 0, 0),
                      SCNVector3(2, 0, 0), SCNVector3(3, 0, 0)]
        let mesh = try XCTUnwrap(RouteGeometry.tubeMesh(points: points, radius: 0.06,
                                                        radialSegments: 8))
        XCTAssertEqual(mesh.positions.count, 4 * 8)
        XCTAssertEqual(mesh.normals.count, mesh.positions.count)
        XCTAssertEqual(mesh.uvs.count, mesh.positions.count)
        // 3 spans × 8 quads × 2 triangles × 3 indices.
        XCTAssertEqual(mesh.indices.count, 3 * 8 * 6)

        // u runs 0 → 1 along the tube and never decreases: the pulse shader's direction.
        XCTAssertEqual(mesh.uvs.first!.x, 0)
        XCTAssertEqual(mesh.uvs.last!.x, 1)
        for ring in 0..<3 {
            XCTAssertLessThanOrEqual(mesh.uvs[ring * 8].x, mesh.uvs[(ring + 1) * 8].x)
        }
    }

    func testTubeMeshRejectsDegenerateInput() {
        XCTAssertNil(RouteGeometry.tubeMesh(points: [SCNVector3(0, 0, 0)], radius: 0.06))
        XCTAssertNil(RouteGeometry.tubeMesh(points: [SCNVector3(0, 0, 0), SCNVector3(0, 0, 0)],
                                            radius: 0.06))
    }

    // MARK: - Overlay scene-graph contract

    @MainActor
    func testOverlayParentsRoutesPerFloorAndClearsCompletely() throws {
        let home = try FixtureLibrary.load(.twostory)
        let built = DollhouseSceneBuilder.build(home)
        let plan = try loadSample("twostory")

        func nodeCount() -> Int {
            var count = 0
            built.dollhouse.scene.rootNode.enumerateHierarchy { _, _ in count += 1 }
            return count
        }
        let baseline = nodeCount()

        let overlay = RouteOverlay(dollhouse: built.dollhouse)
        let issues = overlay.show(rooms: plan.rooms, home: home)
        XCTAssertEqual(issues, [], "twostory sample should draw cleanly on its own fixture")

        for floorID in ["f1", "f2"] {
            let floorNode = try XCTUnwrap(built.dollhouse.scene.rootNode
                .childNode(withName: "floor:\(floorID)", recursively: false))
            XCTAssertNotNil(floorNode.childNode(withName: "routes:\(floorID)", recursively: false),
                            "route container for \(floorID) must live under its floor node so explode/hide apply")
        }

        overlay.clear()
        XCTAssertEqual(nodeCount(), baseline, "clear() must restore the scene exactly")
    }

    @MainActor
    func testOverlayBadgesFlaggedRooms() throws {
        let home = try FixtureLibrary.load(.apartment)
        let built = DollhouseSceneBuilder.build(home)
        let plan = try loadSample("apartment")

        let overlay = RouteOverlay(dollhouse: built.dollhouse)
        overlay.show(rooms: plan.rooms, home: home)

        for room in plan.rooms where !room.findings.isEmpty {
            XCTAssertNotNil(
                built.dollhouse.scene.rootNode.childNode(withName: "badge:\(room.room_id)",
                                                         recursively: true),
                "\(room.room_id) is flagged by the engine and must carry a warning badge"
            )
        }
    }
}
