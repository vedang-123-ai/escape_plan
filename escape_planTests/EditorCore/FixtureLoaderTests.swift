// FixtureLoaderTests.swift — the loader itself, in BOTH runners.
//
// Until 2026-09-24 `FixtureLoader` resolved its bundle only with `Bundle(for:)`, which in a
// SwiftPM test run is the xctest bundle — so no package test could load a fixture, and every
// fixture-based test in this folder was `#if !SWIFT_PACKAGE`. The package now declares
// `escape_plan/Fixtures` as a resource and the loader uses `Bundle.module` there. This test
// is the canary: if either the `resources:` rule or the bundle switch regresses, it fails in
// `swift test` instead of the fixture tests silently being gated again.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class FixtureLoaderTests: XCTestCase {
    func testEveryHomeFixtureLoadsAndDecodes() throws {
        for fixture in HomeFixture.allCases {
            let home = try FixtureLoader.load(fixture)
            XCTAssertFalse(home.floors.isEmpty, "\(fixture.rawValue): decoded with no floors")
            XCTAssertEqual(home.schema_version, HomeModel.currentSchemaVersion,
                           "\(fixture.rawValue): bundled fixture is on an old schema_version")
        }
    }

    /// Known answer, not self-consistency: what the loader returns from its bundle must be
    /// byte-identical to the canonical `schema/fixtures` file read off the source tree. Catches
    /// a stale bundled copy AND any resource rule that transforms the JSON on the way in.
    func testLoaderBytesMatchCanonicalSchemaFixtures() throws {
        for fixture in HomeFixture.allCases {
            XCTAssertEqual(try FixtureLoader.data(for: fixture), try Fixtures.data(fixture.rawValue),
                           "\(fixture.rawValue): bundled bytes differ from schema/fixtures")
        }
    }
}
