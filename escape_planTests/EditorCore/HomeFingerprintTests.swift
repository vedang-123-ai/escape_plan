//  HomeFingerprintTests.swift — the dirty-check that must not see a round trip as an edit.
//
//  The defect this file exists to prevent, measured on 2026-09-16 and recorded in
//  BLOCKERS.md §2: a home that has been through the server differs from the local one BY BYTES
//  but not BY VALUE. pydantic serialises absent optionals as explicit `null` and fills
//  `objects: []`. A dirty-check that hashed the stored or received JSON would therefore see
//  every synced home as permanently modified, and the app would re-upload the user's entire
//  library on every single sync, forever, with no edit anywhere.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class HomeFingerprintTests: XCTestCase {

    /// The REAL bytes `GET /homes` returns for `schema/fixtures/bungalow.json`, produced by
    /// the backend's own models rather than written by hand:
    ///
    ///     backend/.venv/bin/python -c "import json,sys; sys.path.insert(0,'backend'); \
    ///       from app.models import HomeModel; \
    ///       print(HomeModel.model_validate(json.load(open('schema/fixtures/bungalow.json'))).model_dump_json())"
    ///
    /// wrapped in the `StoredHomeModel` envelope the route returns. Captured 2026-09-16. If
    /// pydantic's serialisation ever changes shape, this test is where it surfaces.
    private static let serverShapedBungalow = #"""
    {"id":"srv-rec-1","user_id":"u-1","home":{"schema_version":"2.1","home_id":"5d3f2a10-6b7c-4d8e-9f01-23456789abc1","name":"Bungalow","floors":[{"id":"f1","level":0,"name":"Ground Floor","height_m":2.7,"rooms":[{"source":"manual","confidence":null,"id":"r_living","name":"Living Room","type":"living","polygon":[[0.0,0.0],[5.0,0.0],[5.0,4.0],[0.0,4.0]]},{"source":"manual","confidence":null,"id":"r_kitchen","name":"Kitchen","type":"kitchen","polygon":[[5.0,0.0],[10.0,0.0],[10.0,4.0],[5.0,4.0]]},{"source":"manual","confidence":null,"id":"r_bedroom","name":"Bedroom","type":"bedroom","polygon":[[0.0,4.0],[5.0,4.0],[5.0,8.0],[0.0,8.0]]},{"source":"manual","confidence":null,"id":"r_bath","name":"Bathroom","type":"bath","polygon":[[5.0,4.0],[10.0,4.0],[10.0,8.0],[5.0,8.0]]}],"openings":[{"source":"manual","confidence":null,"id":"d_front","kind":"door","room_ids":["r_living","EXTERIOR"],"wall_segment":{"room_id":"r_living","edge_index":0,"t0":0.4,"t1":0.58},"width_m":0.9,"height_m":2.0,"sill_height_m":0.0,"egress":null},{"source":"manual","confidence":null,"id":"d_living_kitchen","kind":"door","room_ids":["r_living","r_kitchen"],"wall_segment":{"room_id":"r_living","edge_index":1,"t0":0.3,"t1":0.525},"width_m":0.9,"height_m":2.0,"sill_height_m":0.0,"egress":null},{"source":"manual","confidence":null,"id":"d_living_bedroom","kind":"door","room_ids":["r_living","r_bedroom"],"wall_segment":{"room_id":"r_living","edge_index":2,"t0":0.4,"t1":0.58},"width_m":0.9,"height_m":2.0,"sill_height_m":0.0,"egress":null},{"source":"manual","confidence":null,"id":"d_kitchen_bath","kind":"door","room_ids":["r_kitchen","r_bath"],"wall_segment":{"room_id":"r_kitchen","edge_index":2,"t0":0.4,"t1":0.58},"width_m":0.9,"height_m":2.0,"sill_height_m":0.0,"egress":null},{"source":"manual","confidence":null,"id":"w_bedroom","kind":"window","room_ids":["r_bedroom","EXTERIOR"],"wall_segment":{"room_id":"r_bedroom","edge_index":2,"t0":0.4,"t1":0.6},"width_m":1.0,"height_m":1.2,"sill_height_m":0.8,"egress":null},{"source":"manual","confidence":null,"id":"w_living","kind":"window","room_ids":["r_living","EXTERIOR"],"wall_segment":{"room_id":"r_living","edge_index":3,"t0":0.35,"t1":0.6},"width_m":1.0,"height_m":1.2,"sill_height_m":0.8,"egress":null},{"source":"manual","confidence":null,"id":"w_bath","kind":"window","room_ids":["r_bath","EXTERIOR"],"wall_segment":{"room_id":"r_bath","edge_index":2,"t0":0.4,"t1":0.52},"width_m":0.6,"height_m":0.6,"sill_height_m":1.3,"egress":null}],"objects":[],"safety_points":[]}],"stairs":[],"profiles":[],"meta":{"created":"2026-07-10T12:00:00Z","modified":"2026-07-10T12:00:00Z","address_optional":null,"last_scanned":null},"household":null},"revision":3,"created_at":"2026-09-16T05:33:58.567000Z","updated_at":"2026-09-16T06:01:02Z"}
    """#

    // MARK: - The trap

    func testAServerRoundTripDoesNotLookLikeAnEdit() throws {
        let local = try Fixtures.load("bungalow")
        let stored = try HomeModel.decoder.decode(
            StoredHome.self, from: Data(Self.serverShapedBungalow.utf8))

        XCTAssertEqual(HomeFingerprint.of(local), HomeFingerprint.of(stored.home),
                       "a home that only went to the server and back must not read as modified")
    }

    /// The premise of the test above: the two documents really are different bytes. Without
    /// this, `testAServerRoundTripDoesNotLookLikeAnEdit` would pass trivially if someone
    /// replaced the payload with a copy of the fixture.
    func testTheServerShapeGenuinelyDiffersFromTheFixtureBytes() throws {
        let fixtureBytes = try Fixtures.data("bungalow")
        let stored = try HomeModel.decoder.decode(
            StoredHome.self, from: Data(Self.serverShapedBungalow.utf8))
        let serverHomeBytes = try XCTUnwrap(
            Self.serverShapedBungalow.data(using: .utf8))

        XCTAssertNotEqual(fixtureBytes, serverHomeBytes)
        // And specifically: the explicit nulls and the filled-in `objects` array are present.
        XCTAssertTrue(Self.serverShapedBungalow.contains(#""confidence":null"#),
                      "the captured payload has lost the explicit nulls this test is about")
        XCTAssertTrue(Self.serverShapedBungalow.contains(#""objects":[]"#),
                      "the captured payload has lost the filled-in objects array")
        XCTAssertEqual(stored.home, try Fixtures.load("bungalow"),
                       "the round trip must still decode to an EQUAL model")
    }

    /// The wire contract this whole session depends on: `id`, not Mongo's `_id`.
    func testTheStoredHomeEnvelopeDecodesWithAPlainID() throws {
        let stored = try HomeModel.decoder.decode(
            StoredHome.self, from: Data(Self.serverShapedBungalow.utf8))
        XCTAssertEqual(stored.id, "srv-rec-1")
        XCTAssertEqual(stored.user_id, "u-1")
        XCTAssertEqual(stored.revision, 3)
        XCTAssertEqual(stored.localHomeID, stored.home.home_id)
    }

    // MARK: - Ordinary properties

    func testEqualModelsFingerprintIdentically() throws {
        for name in Fixtures.validNames {
            let a = try Fixtures.load(name)
            let b = try Fixtures.load(name)
            XCTAssertEqual(HomeFingerprint.of(a), HomeFingerprint.of(b), name)
        }
    }

    func testFingerprintIsStableAcrossRepeatedCalls() throws {
        let home = try Fixtures.load("twostory")
        let first = HomeFingerprint.of(home)
        for _ in 0..<20 { XCTAssertEqual(HomeFingerprint.of(home), first) }
    }

    func testDifferentHomesFingerprintDifferently() throws {
        let prints = try Fixtures.validNames.map { HomeFingerprint.of(try Fixtures.load($0)) }
        XCTAssertEqual(Set(prints).count, prints.count)
    }

    /// The point of a dirty check: a real edit must be visible. One renamed room is the
    /// smallest change the editor can make.
    func testARenamedRoomChangesTheFingerprint() throws {
        var home = try Fixtures.load("bungalow")
        let before = HomeFingerprint.of(home)
        home.floors[0].rooms[0].name = "Front Room"
        XCTAssertNotEqual(HomeFingerprint.of(home), before)
    }

    /// `meta.modified` is what settles a conflict, so a change to it alone must be seen.
    func testATouchedModifiedDateChangesTheFingerprint() throws {
        var home = try Fixtures.load("bungalow")
        let before = HomeFingerprint.of(home)
        home.meta.modified = home.meta.modified.addingTimeInterval(1)
        XCTAssertNotEqual(HomeFingerprint.of(home), before)
    }

    /// Sorted keys are not cosmetic: without them the digest would depend on the declaration
    /// order of `HomeModel`'s properties, so reordering two `var`s would invalidate every
    /// stored fingerprint on every device and trigger a full re-upload of every library.
    func testCanonicalJSONHasSortedKeys() throws {
        let json = try HomeFingerprint.canonicalJSON(of: Fixtures.load("bungalow"))
        let text = String(decoding: json, as: UTF8.self)
        let topLevelOrder = [#""floors""#, #""home_id""#, #""meta""#, #""name""#,
                             #""profiles""#, #""schema_version""#, #""stairs""#]
        var cursor = text.startIndex
        for key in topLevelOrder {
            let found = try XCTUnwrap(text.range(of: key, range: cursor..<text.endIndex),
                                      "\(key) not found in sorted order")
            cursor = found.upperBound
        }
    }

    func testFingerprintIsSixteenHexCharacters() throws {
        let print = HomeFingerprint.of(try Fixtures.load("apartment"))
        XCTAssertEqual(print.count, 16)
        XCTAssertTrue(print.allSatisfy { $0.isHexDigit }, print)
    }
}
