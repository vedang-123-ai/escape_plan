//  HomeModelCodableTests.swift — the schema mirror actually mirrors the schema.
//
//  This is the S2.1 lane's stand-in for S0.3's round-trip gate. When S0.3's real Models/ layer
//  lands, these tests should be pointed at it and this file's `replace-with-S0.3` counterpart
//  deleted — the assertions themselves stay valid either way.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class HomeModelCodableTests: XCTestCase {

    /// decode -> encode -> decode must be a fixed point. Catches any field the mirror drops.
    func testFixturesRoundTripSemantically() throws {
        for name in Fixtures.validNames {
            let original = try Fixtures.load(name)
            let reencoded = try HomeModel.encoder().encode(original)
            let again = try HomeModel.decoder.decode(HomeModel.self, from: reencoded)
            XCTAssertEqual(original, again, "\(name).json did not survive a round trip")
        }
    }

    /// Stronger than the Swift-level round trip: compares the re-encoded JSON against the
    /// original JSON key by key, so a field this mirror never modelled at all is caught.
    /// (Absent-vs-default is normalised: the schema defaults `stairs`/`profiles`/`reasons` to
    /// `[]` and `address_optional` to null, so those are compared as equivalent.)
    func testFixturesRoundTripAtTheJSONLevel() throws {
        for name in Fixtures.validNames {
            let originalJSON = try JSONSerialization.jsonObject(with: try Fixtures.data(name))
            let model = try Fixtures.load(name)
            let roundTripped = try JSONSerialization.jsonObject(
                with: try HomeModel.encoder().encode(model))

            let a = normalize(originalJSON)
            let b = normalize(roundTripped)
            XCTAssertEqual(a as? NSDictionary, b as? NSDictionary,
                           "\(name).json changed shape through the Swift mirror")
        }
    }

    func testFixturesAreValidPerTheEditorsOwnRules() throws {
        // The fixtures are pydantic-valid by construction (S0.2). If the editor's client-side
        // validator disagrees with any of them, it's the validator that's wrong — this test is
        // what keeps the Swift mirror honest against backend/app/models.py.
        for name in Fixtures.validNames {
            XCTAssertModelValid(try Fixtures.load(name), "fixture \(name)")
        }
    }

    func testInvalidFixturesAreRejected() throws {
        let files = try Fixtures.invalidNames()
        XCTAssertFalse(files.isEmpty, "expected fixtures in schema/fixtures/invalid/")

        for file in files {
            // Some invalid fixtures fail at decode (shape), others only at the structural
            // checks JSON Schema can't express. Either counts as caught; being silently
            // accepted does not.
            do {
                let model = try Fixtures.loadInvalid(file)
                let issues = EditorValidation.validate(model)
                XCTAssertFalse(issues.isEmpty,
                               "invalid fixture \(file) was accepted by EditorValidation")
            } catch {
                // Rejected at decode — also correct.
            }
        }
    }

    func testPointEncodesAsATwoElementArray() throws {
        let data = try JSONEncoder().encode(Point(1.5, -2.25))
        let json = try JSONSerialization.jsonObject(with: data) as? [Double]
        XCTAssertEqual(json, [1.5, -2.25])
    }

    func testStairsUsesTheReservedFromKey() throws {
        let stairs = Stairs(id: "s1",
                            from: StairEnd(floor_id: "f1", room_id: "r1"),
                            to: StairEnd(floor_id: "f2", room_id: "r2"),
                            footprint: Geometry.rectangle(origin: Point(0, 0),
                                                          width: 1, height: 3),
                            kind: .straight, source: .manual, confidence: nil)
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(stairs)) as? [String: Any]
        XCTAssertNotNil(json?["from"], "the JSON key must be 'from', not 'from'")
        XCTAssertNotNil(json?["to"])
    }

    func testExteriorIsNotAValidRoomType() throws {
        // EXTERIOR is a pseudo-room: it may appear in room_ids and nowhere else.
        var model = try Fixtures.load("bungalow")
        model.floors[0].rooms[0].id = EXTERIOR_ID
        let issues = EditorValidation.validate(model)
        XCTAssertTrue(issues.contains { $0.kind == .reservedId })
    }

    // MARK: - Helpers

    /// Fills in the schema's documented defaults so "absent" and "default" compare equal.
    private func normalize(_ value: Any) -> Any {
        guard var dict = value as? [String: Any] else { return value }

        if dict["floors"] != nil {
            dict["stairs"] = dict["stairs"] ?? []
            dict["profiles"] = dict["profiles"] ?? []
        }
        // A floor: openings and (v1.1) objects both default to [].
        if dict["level"] != nil, dict["rooms"] != nil {
            dict["openings"] = dict["openings"] ?? []
            dict["objects"] = dict["objects"] ?? []
        }
        // An object: rotation_deg defaults to 0.
        if dict["category"] != nil, dict["size_m"] != nil {
            dict["rotation_deg"] = dict["rotation_deg"] ?? 0
        }
        if dict["viable"] != nil {
            dict["reasons"] = dict["reasons"] ?? []
        }
        // The mirror omits a nil address rather than writing an explicit null; the schema
        // treats absent and null identically (default: null).
        if dict["created"] != nil, dict["address_optional"] is NSNull {
            dict["address_optional"] = nil
        }

        for (k, v) in dict {
            if let nested = v as? [String: Any] {
                dict[k] = normalize(nested)
            } else if let array = v as? [Any] {
                dict[k] = array.map { normalize($0) }
            }
        }
        return dict
    }
}
