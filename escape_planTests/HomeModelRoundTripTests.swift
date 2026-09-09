//  HomeModelRoundTripTests.swift
//  escape_planTests
//
//  S0.3 acceptance: decode -> encode -> decode -> compare. The comparison is semantic
//  (Equatable equality on the decoded model graph), not a literal byte diff of the two JSON
//  blobs, because JSONEncoder key order / whitespace isn't guaranteed to match the original
//  file's formatting even when the content is identical.

import XCTest
@testable import escape_plan

final class HomeModelRoundTripTests: XCTestCase {

    func testAllFixturesRoundTrip() throws {
        for fixture in HomeFixture.allCases {
            let originalData = try FixtureLoader.data(for: fixture)
            let decodedOnce = try HomeModel.decoder.decode(HomeModel.self, from: originalData)

            let reEncoded = try HomeModel.encoder().encode(decodedOnce)
            let decodedTwice = try HomeModel.decoder.decode(HomeModel.self, from: reEncoded)

            XCTAssertEqual(
                decodedOnce, decodedTwice,
                "\(fixture.rawValue): decode -> encode -> decode changed the model"
            )
        }
    }

    func testTwostoryDecodesExpectedStructure() throws {
        let home = try FixtureLoader.load(.twostory)

        XCTAssertEqual(home.schema_version, HomeModel.currentSchemaVersion)
        XCTAssertEqual(home.floors.count, 2)
        XCTAssertEqual(home.floors.map(\.name).sorted(), ["Ground Floor", "Upstairs"])

        let kidsRoom = home.floors
            .flatMap(\.rooms)
            .first { $0.id == "r_bed_kids" }
        XCTAssertEqual(kidsRoom?.type, .bedroom)

        // Planted issue in this fixture: the kids' window is undersized for egress.
        let kidsWindow = home.floors
            .flatMap(\.openings)
            .first { $0.id == "w_kids" }
        XCTAssertNotNil(kidsWindow)
        XCTAssertEqual(kidsWindow?.width_m, 0.4)

        XCTAssertEqual(home.profiles.map(\.name).sorted(), ["Grandpa", "Maya"])
        
        // S6.1 happy path
        XCTAssertNotNil(home.household)
        XCTAssertEqual(home.household?.tenure, .rent)
        XCTAssertEqual(home.household?.existing_equipment, [])
        
        let safetyPoints = home.floors.first { $0.id == "f1" }?.safety_points ?? []
        XCTAssertEqual(safetyPoints.count, 2)
        XCTAssertEqual(safetyPoints.first?.id, "sp_gas")
        XCTAssertEqual(safetyPoints.first?.kind, .gas_shutoff)
    }

    func testApartmentDecodesS6_1Fields() throws {
        let home = try FixtureLoader.load(.apartment)
        
        let allObjects = home.floors.flatMap(\.objects)
        let securedObjects = allObjects.filter(\.secured)
        
        XCTAssertGreaterThan(securedObjects.count, 0)
        XCTAssertEqual(securedObjects.first?.id, "obj_wardrobe_1")
    }

    func testPointRoundTripsAsTwoElementArray() throws {
        let point = Point(x: 1.5, y: -2.25)
        let data = try JSONEncoder().encode(point)
        XCTAssertEqual(String(data: data, encoding: .utf8), "[1.5,-2.25]")

        let decoded = try JSONDecoder().decode(Point.self, from: data)
        XCTAssertEqual(decoded, point)
    }

    func testStairsFromKeywordDecodesWithoutCollision() throws {
        // "from" is a valid Swift identifier (unlike Python's "from"), so Stairs.from
        // mirrors the JSON key directly with no alias/CodingKeys needed.
        let home = try FixtureLoader.load(.twostory)
        let stair = try XCTUnwrap(home.stairs.first)
        XCTAssertEqual(stair.from.floor_id, "f1")
        XCTAssertEqual(stair.to.floor_id, "f2")
    }
}
