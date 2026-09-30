//  HomeSizeBoundsTests.swift — S11.25 (AUD-004): residential size bounds.
//
//  Two jobs:
//
//  1. **Lockstep.** `HomeSizeBounds` is a hand-written mirror of the `MAX_*` constants in
//     `backend/app/models.py`. A mirror that drifts is worse than no mirror: the editor would
//     cheerfully build a home the server answers 422 to, and the user would find out at save
//     time. `testEveryBoundMatchesTheBackendConstant` parses the Python source off the source
//     tree and compares every value, so drift fails here rather than on a phone.
//
//  2. **Behaviour.** Each bound rejects an over-bound home and accepts one at the bound, with
//     `.sizeBounds` as the issue kind so the editor can point at the offending entity.
//
//  Pure Foundation, so it runs in `swift test --package-path tools/editorcore` with no simulator.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class HomeSizeBoundsTests: XCTestCase {

    // MARK: - Lockstep with backend/app/models.py

    /// Every Swift bound, paired with the Python constant it mirrors.
    private static let mirrored: [(name: String, swift: Double)] = [
        ("MAX_COORD_M", HomeSizeBounds.maxCoordM),
        ("MAX_POLYGON_VERTICES", Double(HomeSizeBounds.maxPolygonVertices)),
        ("MAX_ROOM_SPAN_M", HomeSizeBounds.maxRoomSpanM),
        ("MAX_ROOM_AREA_M2", HomeSizeBounds.maxRoomAreaM2),
        ("MAX_ROOM_GRID_CELLS", Double(HomeSizeBounds.maxRoomGridCells)),
        ("MAX_TOTAL_GRID_CELLS", Double(HomeSizeBounds.maxTotalGridCells)),
        ("MAX_FLOORS", Double(HomeSizeBounds.maxFloors)),
        ("MAX_ROOMS", Double(HomeSizeBounds.maxRooms)),
        ("MAX_OPENINGS_PER_FLOOR", Double(HomeSizeBounds.maxOpeningsPerFloor)),
        ("MAX_OBJECTS_PER_FLOOR", Double(HomeSizeBounds.maxObjectsPerFloor)),
        ("MAX_SAFETY_POINTS_PER_FLOOR", Double(HomeSizeBounds.maxSafetyPointsPerFloor)),
        ("MAX_STAIRS", Double(HomeSizeBounds.maxStairs)),
        ("MAX_PROFILES", Double(HomeSizeBounds.maxProfiles)),
        ("MAX_FLOOR_HEIGHT_M", HomeSizeBounds.maxFloorHeightM),
        ("MAX_OPENING_DIM_M", HomeSizeBounds.maxOpeningDimM),
        ("MAX_OBJECT_SIZE_M", HomeSizeBounds.maxObjectSizeM),
        ("MAX_OBJECT_HEIGHT_M", HomeSizeBounds.maxObjectHeightM),
        ("MAX_OBJECT_ELEVATION_M", HomeSizeBounds.maxObjectElevationM),
    ]

    /// Every `MAX_NAME = ...` assignment in the source, at any indentation.
    ///
    /// The value is nil when the right-hand side is not a bare number (an expression such as
    /// `MAX_X = 2 * 50`, say). Those are reported as names with no value rather than skipped:
    /// an earlier version required column 0 AND a parsable number, so an indented or computed
    /// bound fell through both this dictionary and the `unmirrored` check and was invisible to
    /// the whole test — exactly the drift it exists to catch.
    private func pythonConstants(in source: String) -> [String: Double?] {
        var found: [String: Double?] = [:]
        for raw in source.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("MAX_"), let eq = line.firstIndex(of: "=") else { continue }
            // Skip comparisons and augmented assignment (`MAX_X == y`, `MAX_X >= y`).
            let next = line.index(after: eq)
            if next < line.endIndex, line[next] == "=" { continue }
            let name = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            guard !name.contains(" "), !name.contains("[") else { continue }
            let rhs = String(line[next...])
                .components(separatedBy: "#")[0]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "_", with: "")
            found[name] = Double(rhs)
        }
        return found
    }

    func testEveryBoundMatchesTheBackendConstant() throws {
        let modelsPath = Fixtures.repoRoot.appendingPathComponent("backend/app/models.py")
        let source = try String(contentsOf: modelsPath, encoding: .utf8)
        let python = pythonConstants(in: source)

        XCTAssertFalse(python.isEmpty, "parsed no MAX_* constants out of backend/app/models.py")
        for (name, swiftValue) in Self.mirrored {
            guard let entry = python[name] else {
                XCTFail("\(name) is missing from backend/app/models.py — was it renamed?")
                continue
            }
            guard let pythonValue = entry else {
                XCTFail("\(name) in backend/app/models.py is no longer a bare number, so this "
                        + "test can no longer compare it. Compare it by hand or keep it literal.")
                continue
            }
            XCTAssertEqual(pythonValue, swiftValue, accuracy: 1e-9,
                           "\(name) has drifted: Python \(pythonValue), Swift \(swiftValue). "
                           + "The editor would now build homes the server rejects.")
        }
        // Nothing new on the Python side that Swift has not mirrored. This is the direction
        // that matters most: a server bound the editor does not know about is a 422 the user
        // meets at save time.
        let unmirrored = Set(python.keys).subtracting(Self.mirrored.map(\.name))
        XCTAssertTrue(unmirrored.isEmpty,
                      "backend/app/models.py has bounds the editor does not enforce: "
                      + unmirrored.sorted().joined(separator: ", "))
        XCTAssertEqual(python.count, Self.mirrored.count,
                       "the two sides no longer have the same NUMBER of bounds: Python "
                       + "\(python.count), mirrored \(Self.mirrored.count)")
    }

    func testCellSizeMatchesTheRoutingEngine() throws {
        let navGrid = Fixtures.repoRoot.appendingPathComponent("backend/app/routing/nav_grid.py")
        let source = try String(contentsOf: navGrid, encoding: .utf8)
        let line = try XCTUnwrap(source.components(separatedBy: .newlines)
            .first { $0.hasPrefix("CELL_M") })
        let rhs = try XCTUnwrap(line.components(separatedBy: "=").last)
        XCTAssertEqual(Double(rhs.trimmingCharacters(in: .whitespaces)), HomeSizeBounds.cellM)
    }

    // MARK: - gridCellCount

    /// Known-answer: 4.3 m x 2.7 m at 10 cm cells is 43 x 27, same as the backend's
    /// `build_room_grid` and `bbox_cell_count`.
    func testGridCellCountIsAKnownAnswer() {
        let polygon = [Point(0, 0), Point(4.3, 0), Point(4.3, 2.7), Point(0, 2.7)]
        XCTAssertEqual(HomeSizeBounds.gridCellCount(polygon), 43 * 27)
    }

    /// Saturates instead of trapping, for a NaN in ANY vertex — `max()`/`min()` skip a
    /// non-leading NaN, so the extent can look finite. `bbox_cell_count` in
    /// `backend/app/models.py` returns `sys.maxsize` for the same inputs.
    func testGridCellCountIsTotalForANonFinitePolygon() {
        for position in 0..<3 {
            var polygon = [Point(0, 0), Point(4, 0), Point(4, 3)]
            polygon[position] = Point(.nan, polygon[position].y)
            XCTAssertEqual(HomeSizeBounds.gridCellCount(polygon), Int.max,
                           "NaN at vertex \(position) should saturate, not trap")
        }
        for bad in [Double.infinity, -Double.infinity] {
            XCTAssertEqual(
                HomeSizeBounds.gridCellCount([Point(0, 0), Point(bad, 0), Point(4, 3)]),
                Int.max)
        }
    }

    /// The whole reason the bound is on cells and not area: a 30 m² sliver, 90,000 cells.
    func testASliverCostsItsWholeBoundingBox() {
        let sliver = [Point(0, 0), Point(60, 14.5), Point(60, 15), Point(0, 0.5)]
        XCTAssertEqual(HomeSizeBounds.gridCellCount(sliver), 600 * 150)
        XCTAssertLessThan(abs(Geometry.signedArea(sliver)), HomeSizeBounds.maxRoomAreaM2)
    }

    // MARK: - Helpers

    private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ d: Double) -> [Point] {
        [Point(x, y), Point(x + w, y), Point(x + w, y + d), Point(x, y + d)]
    }

    private func home(rooms: [Room], floors: [Floor]? = nil,
                      objects: [FloorObject] = [],
                      safetyPoints: [SafetyPoint] = [],
                      openings: [Opening] = [],
                      height: Double = 2.7,
                      profiles: [Profile] = [],
                      stairs: [Stairs] = []) -> HomeModel {
        HomeModel(schema_version: HomeModel.currentSchemaVersion, home_id: "h_bounds",
                  name: "Bounds", floors: floors ?? [
                      Floor(id: "f0", level: 0, name: "Ground", height_m: height,
                            rooms: rooms, openings: openings, objects: objects,
                            safety_points: safetyPoints)
                  ],
                  stairs: stairs, profiles: profiles,
                  meta: Meta(created: stamp, modified: stamp))
    }

    private func sizeIssues(_ model: HomeModel) -> [ValidationIssue] {
        EditorValidation.validate(model).filter { $0.kind == .sizeBounds }
    }

    private func assertNoSizeIssues(_ model: HomeModel, _ note: String,
                                    line: UInt = #line) {
        let issues = sizeIssues(model)
        XCTAssertTrue(issues.isEmpty,
                      "\(note) should be inside the bounds, got: \(issues)",
                      line: line)
    }

    private func room(_ id: String, _ polygon: [Point]) -> Room {
        Room(id: id, name: id, type: .bedroom, polygon: polygon, source: .manual,
             confidence: nil)
    }

    // MARK: - Per-room bounds

    func testRoomSpanAtAndOverTheBound() {
        assertNoSizeIssues(home(rooms: [room("r1", rect(0, 0, 60, 1))]), "a 60 m x 1 m room")

        let over = home(rooms: [room("r1", rect(0, 0, 60.1, 1))])
        let issues = sizeIssues(over)
        XCTAssertTrue(issues.contains { $0.message.contains("spans") },
                      "expected a span issue, got \(issues)")
        XCTAssertEqual(issues.first?.entityId, "r1")
    }

    func testRoomAreaAtAndOverTheBound() {
        // 50 m x 10 m = 500 m2 exactly, and 50,000 cells.
        assertNoSizeIssues(home(rooms: [room("r1", rect(0, 0, 50, 10))]), "a 500 m2 room")

        let over = home(rooms: [room("r1", rect(0, 0, 50, 10.5))])
        XCTAssertTrue(sizeIssues(over).contains { $0.message.contains("the maximum for one room") },
                      "expected an area issue, got \(sizeIssues(over))")
    }

    /// Only a sliver can reach the per-room cell bound: for a rectangle the 500 m² area cap
    /// always binds first. Both polygons here are 30 m² with a legal span.
    func testRoomGridCellsAtAndOverTheBound() {
        let at = [Point(0, 0), Point(60, 14.5), Point(60, 15), Point(0, 0.5)]
        XCTAssertEqual(HomeSizeBounds.gridCellCount(at), HomeSizeBounds.maxRoomGridCells)
        assertNoSizeIssues(home(rooms: [room("r1", at)]), "a 90,000-cell sliver")

        let over = [Point(0, 0), Point(60, 15.5), Point(60, 16), Point(0, 0.5)]
        XCTAssertGreaterThan(HomeSizeBounds.gridCellCount(over), HomeSizeBounds.maxRoomGridCells)
        XCTAssertTrue(sizeIssues(home(rooms: [room("r1", over)]))
                        .contains { $0.message.contains("navigation cells") },
                      "expected a per-room cell issue")
    }

    func testPolygonVerticesAtAndOverTheBound() {
        func ngon(_ n: Int, radius: Double = 6) -> [Point] {
            (0..<n).map { i in
                let a = 2 * Double.pi * Double(i) / Double(n)
                return Point((radius * cos(a) * 1e4).rounded() / 1e4,
                             (radius * sin(a) * 1e4).rounded() / 1e4)
            }
        }
        assertNoSizeIssues(home(rooms: [room("r1", ngon(HomeSizeBounds.maxPolygonVertices))]),
                           "a 64-gon room")
        XCTAssertTrue(sizeIssues(home(rooms: [room("r1", ngon(HomeSizeBounds.maxPolygonVertices + 1))]))
                        .contains { $0.message.contains("vertices") },
                      "expected a vertex-count issue")
    }

    func testCoordinateRangeAndNonFiniteValues() {
        assertNoSizeIssues(home(rooms: [room("r1", rect(195, 0, 5, 4))]), "a room at +200 m")

        XCTAssertTrue(sizeIssues(home(rooms: [room("r1", rect(195.1, 0, 5, 4))]))
                        .contains { $0.message.contains("outside the supported range") })

        for bad in [Double.infinity, -Double.infinity, Double.nan] {
            let poly: [Point] = [Point(0, 0), Point(5, 0), Point(bad, 4), Point(0, 4)]
            XCTAssertTrue(sizeIssues(home(rooms: [room("r1", poly)]))
                            .contains { $0.message.contains("finite") },
                          "a \(bad) coordinate should be reported as non-finite")
        }
    }

    // MARK: - Whole-home bounds

    /// n rooms of w x d in a staggered grid, each well inside the per-room bounds.
    private func rooms(_ n: Int, _ w: Double, _ d: Double) -> [Room] {
        (0..<n).map { i in
            let col = Double(i % 12), row = Double(i / 12)
            return room("r\(i)", rect(col * (w + 1), row * (d + 1), w, d))
        }
    }

    func testTotalGridCellsAtAndOverTheBound() {
        // 100 rooms of 5 m x 5 m = 2,500 cells each = 250,000 exactly.
        let at = home(rooms: rooms(100, 5, 5))
        XCTAssertEqual(at.floors[0].rooms.reduce(0) { $0 + HomeSizeBounds.gridCellCount($1.polygon) },
                       HomeSizeBounds.maxTotalGridCells)
        assertNoSizeIssues(at, "a home at exactly 250,000 cells")

        let over = home(rooms: rooms(101, 5, 5))
        for r in over.floors[0].rooms {
            XCTAssertLessThanOrEqual(HomeSizeBounds.gridCellCount(r.polygon),
                                     HomeSizeBounds.maxRoomGridCells,
                                     "each room must be legal on its own")
        }
        XCTAssertTrue(sizeIssues(over).contains { $0.message.contains("too large to route") },
                      "expected a whole-home cell issue, got \(sizeIssues(over))")
    }

    func testRoomCountCountsTheWholeHomeNotOneFloor() {
        // 120 rooms per floor passes any per-floor reading; 240 across two floors does not.
        let lower = Floor(id: "f0", level: 0, name: "Ground", height_m: 2.7,
                          rooms: rooms(120, 1, 1))
        let upper = Floor(id: "f1", level: 1, name: "Upper", height_m: 2.7,
                          rooms: rooms(120, 1, 1).map {
                              room($0.id + "_u", $0.polygon)
                          })
        let model = home(rooms: [], floors: [lower, upper])
        XCTAssertTrue(sizeIssues(model).contains { $0.message.contains("rooms across 2 floors") },
                      "expected a whole-home room-count issue, got \(sizeIssues(model))")
    }

    func testFloorCountOverTheBound() {
        let floors = (0...HomeSizeBounds.maxFloors).map { level in
            Floor(id: "f\(level)", level: level, name: "F\(level)", height_m: 2.7,
                  rooms: [room("r\(level)", rect(0, 0, 4, 4))])
        }
        XCTAssertTrue(sizeIssues(home(rooms: [], floors: floors))
                        .contains { $0.message.contains("floors; the maximum is 8") })
    }

    func testProfileAndStairCountsOverTheBound() {
        let base = rect(0, 0, 4, 4)
        let profiles = (0...HomeSizeBounds.maxProfiles).map {
            Profile(id: "p\($0)", name: "P\($0)", tags: [], bedroom_room_id: "r1")
        }
        XCTAssertTrue(sizeIssues(home(rooms: [room("r1", base)], profiles: profiles))
                        .contains { $0.message.contains("people; the maximum is 50") })

        let stairs = (0...HomeSizeBounds.maxStairs).map {
            Stairs(id: "st\($0)", from: StairEnd(floor_id: "f0", room_id: "r1"),
                   to: StairEnd(floor_id: "f1", room_id: "r2"),
                   footprint: rect(0, 0, 1, 3), kind: .straight, source: .manual,
                   confidence: nil)
        }
        let two = [
            Floor(id: "f0", level: 0, name: "G", height_m: 2.7, rooms: [room("r1", base)]),
            Floor(id: "f1", level: 1, name: "U", height_m: 2.7, rooms: [room("r2", base)]),
        ]
        XCTAssertTrue(sizeIssues(home(rooms: [], floors: two, stairs: stairs))
                        .contains { $0.message.contains("stairs; the maximum is 50") })
    }

    // MARK: - Per-floor collections and scalars

    func testFloorHeightOverTheBound() {
        assertNoSizeIssues(home(rooms: [room("r1", rect(0, 0, 4, 4))], height: 20),
                           "a 20 m floor")
        XCTAssertTrue(sizeIssues(home(rooms: [room("r1", rect(0, 0, 4, 4))], height: 20.1))
                        .contains { $0.message.contains("height_m") })
    }

    func testObjectAndLandmarkCountsOverTheBound() {
        let r = room("r1", rect(0, 0, 4, 4))
        let objects = (0...HomeSizeBounds.maxObjectsPerFloor).map {
            FloorObject(id: "ob\($0)", category: .bookcase, center: Point(1, 1),
                        size_m: [0.5, 0.3], height_m: 1.8, rotation_deg: 0,
                        source: .manual, confidence: nil, secured: false,
                        elevation_m: 0, mounted: false)
        }
        XCTAssertTrue(sizeIssues(home(rooms: [r], objects: objects))
                        .contains { $0.message.contains("objects; the maximum is 500") })

        let points = (0...HomeSizeBounds.maxSafetyPointsPerFloor).map {
            SafetyPoint(id: "sp\($0)", kind: .gas_shutoff, position: Point(1, 1),
                        source: .manual, confidence: nil)
        }
        XCTAssertTrue(sizeIssues(home(rooms: [r], safetyPoints: points))
                        .contains { $0.message.contains("landmarks; the maximum is 100") })
    }

    func testObjectDimensionsOverTheBound() {
        let r = room("r1", rect(0, 0, 4, 4))
        func object(size: [Double] = [0.5, 0.3], height: Double = 1.8,
                    elevation: Double = 0, rotation: Double = 0,
                    centre: Point = Point(1, 1)) -> FloorObject {
            FloorObject(id: "ob1", category: .bookcase, center: centre, size_m: size,
                        height_m: height, rotation_deg: rotation, source: .manual,
                        confidence: nil, secured: false, elevation_m: elevation,
                        mounted: false)
        }
        assertNoSizeIssues(home(rooms: [r], objects: [object()]), "an ordinary bookcase")

        XCTAssertTrue(sizeIssues(home(rooms: [r], objects: [object(size: [51, 0.3])]))
                        .contains { $0.message.contains("footprint") })
        XCTAssertTrue(sizeIssues(home(rooms: [r], objects: [object(height: 21)]))
                        .contains { $0.message.contains("object height") })
        XCTAssertTrue(sizeIssues(home(rooms: [r], objects: [object(elevation: 101)]))
                        .contains { $0.message.contains("elevation") })
        XCTAssertTrue(sizeIssues(home(rooms: [r], objects: [object(rotation: .nan)]))
                        .contains { $0.message.contains("rotation") })
        XCTAssertTrue(sizeIssues(home(rooms: [r], objects: [object(centre: Point(201, 1))]))
                        .contains { $0.message.contains("outside the supported range") })
    }

    // MARK: - Real data is unaffected

    /// EVERY fixture in `schema/fixtures/`, enumerated off disk — not `Fixtures.validNames`,
    /// which is the hardcoded S0.2 trio and omits `jagged.json`, the fixture that sits closest
    /// to these bounds (51,600 of 250,000 cells). A test named "every shipped fixture" that
    /// checked three of seven would not have caught a tightening that clipped `jagged`.
    func testEveryShippedFixtureIsInsideEveryBound() throws {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: Fixtures.directory.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
        XCTAssertGreaterThanOrEqual(names.count, 7,
                                    "expected at least the 7 committed fixtures, found \(names)")

        var worstCells = 0
        for name in names {
            let model = try Fixtures.load(name)
            XCTAssertTrue(sizeIssues(model).isEmpty,
                          "\(name).json must stay inside the bounds, got \(sizeIssues(model))")
            worstCells = max(worstCells, model.floors.reduce(0) { sum, floor in
                sum + floor.rooms.reduce(0) { $0 + HomeSizeBounds.gridCellCount($1.polygon) }
            })
        }
        // Records the headroom so a future tightening has to face the number.
        XCTAssertLessThanOrEqual(worstCells, HomeSizeBounds.maxTotalGridCells / 4,
                                 "the largest fixture now needs \(worstCells) cells, under 4x "
                                 + "headroom below maxTotalGridCells")
    }
}
