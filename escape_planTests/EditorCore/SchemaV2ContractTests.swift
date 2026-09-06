//  SchemaV2ContractTests.swift — pins the v2.0 additions that nothing else can see.
//
//  Lives in the shared EditorCore directory so it runs in BOTH the SwiftPM package and the
//  iOS test target. Two of these cover behaviour the fixture round-trip is structurally
//  blind to: no committed fixture carries a fractional-second timestamp, and no committed
//  fixture is malformed, so a regression in either would be silent.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class SchemaV2ContractTests: XCTestCase {

    // MARK: - Date strategy

    private func decodeMeta(_ raw: String) throws -> Meta {
        let json = #"{"created":"\#(raw)","modified":"\#(raw)"}"#
        return try HomeModel.decoder.decode(Meta.self, from: Data(json.utf8))
    }

    func testWholeAndFractionalSecondsBothDecode() throws {
        let whole = try decodeMeta("2026-01-05T09:30:00Z")
        let fractional = try decodeMeta("2026-01-05T09:30:00.123456Z")
        // Same instant to the second; the fractional form must not be rejected, which is the
        // form pydantic emits for meta.last_scanned and /convert's timestamps.
        XCTAssertEqual(whole.created.timeIntervalSince1970,
                       fractional.created.timeIntervalSince1970, accuracy: 1.0)
    }

    func testAnExplicitOffsetDecodes() throws {
        XCTAssertNoThrow(try decodeMeta("2026-01-05T09:30:00.123456+00:00"))
    }

    func testMalformedTimestampsFailLoudly() {
        // The strategy must never invent a date. A naive timestamp with no offset is
        // deliberately in this list: inventing a timezone is worse than refusing.
        for bad in ["2026-01-05T09:30:00", "2026-01-05", "not-a-date", "2026-13-45T99:99:99Z", ""] {
            XCTAssertThrowsError(try decodeMeta(bad), "\(bad) should not decode") { error in
                guard case DecodingError.dataCorrupted = error else {
                    return XCTFail("\(bad) threw \(error), expected .dataCorrupted")
                }
            }
        }
    }

    func testLastScannedIsOptionalAndDistinctFromStale() throws {
        let never = try HomeModel.decoder.decode(
            Meta.self, from: Data(#"{"created":"2026-01-05T09:30:00Z","modified":"2026-01-05T09:30:00Z"}"#.utf8))
        XCTAssertNil(never.last_scanned, "absent last_scanned means never scanned")

        let explicitNull = try HomeModel.decoder.decode(
            Meta.self, from: Data(#"{"created":"2026-01-05T09:30:00Z","modified":"2026-01-05T09:30:00Z","last_scanned":null}"#.utf8))
        XCTAssertNil(explicitNull.last_scanned, "explicit null is the same state as absent")
    }

    // MARK: - EditorValidation must match the pydantic invariants

    private func homeWithSafetyPoint(id: String) throws -> HomeModel {
        var model = try Fixtures.load("twostory")
        model.floors[0].safety_points = [
            SafetyPoint(id: id, kind: .gas_shutoff, position: Point(9.4, 0.6),
                        source: .manual, confidence: nil)
        ]
        return model
    }

    func testASafetyPointIdCollidingWithARoomIsRejected() throws {
        // backend/app/models.py claims safety_point ids in the GLOBAL uniqueness pass, so a
        // collision with a room id is a 422. The Swift validator has to agree, or the editor
        // accepts a home the server will refuse.
        let roomID = try Fixtures.load("twostory").floors[0].rooms[0].id
        let issues = EditorValidation.validate(try homeWithSafetyPoint(id: roomID))
        XCTAssertTrue(issues.contains { $0.kind == .idUniqueness },
                      "a safety point colliding with a room id must be caught client-side")
    }

    func testASafetyPointMayNotBeCalledEXTERIOR() throws {
        let issues = EditorValidation.validate(try homeWithSafetyPoint(id: EXTERIOR_ID))
        XCTAssertTrue(issues.contains { $0.kind == .reservedId })
    }

    func testWellFormedSafetyPointsAreAccepted() throws {
        XCTAssertTrue(EditorValidation.validate(try homeWithSafetyPoint(id: "sp_new")).isEmpty)
    }

    // MARK: - Absent-field decoding (the backward-compatibility ruling)

    func testA1Point1DocumentDecodesWithEveryNewFieldDefaulted() throws {
        let json = """
        {"schema_version":"1.1","home_id":"h1","name":"Old","floors":[{"id":"f1","level":0,
        "name":"G","height_m":2.4,"rooms":[{"id":"r1","name":"R","type":"hall",
        "polygon":[[0,0],[3,0],[3,3],[0,3]],"source":"manual"}]}],
        "meta":{"created":"2026-01-05T09:30:00Z","modified":"2026-01-05T09:30:00Z"}}
        """
        let home = try HomeModel.decoder.decode(HomeModel.self, from: Data(json.utf8))
        XCTAssertNil(home.household)
        XCTAssertNil(home.meta.last_scanned)
        XCTAssertEqual(home.floors[0].safety_points, [])
        XCTAssertEqual(home.floors[0].objects, [])
    }
}
