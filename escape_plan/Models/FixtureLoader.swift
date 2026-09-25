// FixtureLoader.swift
// Loads the schema/fixtures/*.json test bed (bundled as app resources into escape_plan/Fixtures/,
// copied from the project-wide fixtures — see docs/decisions.md for why they're copies and not
// symlinks). Used by the Home screen (proof-of-decode) and by the round-trip test target.

import Foundation

enum HomeFixture: String, CaseIterable {
    case bungalow
    case apartment
    case twostory
    /// Three levels with deliberately mismatched footprints (4×5 m basement in one corner,
    /// 20×20 m ground floor, 12×8 m upper offset to the opposite corner). This is the
    /// acceptance model for floor stacking: it is the fixture that proves ghosted floors,
    /// slab outlines and the union-sized base plate all read correctly when the stack is
    /// jagged rather than a tidy tower.
    case jagged
}

enum FixtureLoaderError: Error {
    case missingResource(String)
}

enum FixtureLoader {
    #if SWIFT_PACKAGE
    /// In the Foundation-only EditorCore package (tools/editorcore) this file is compiled into
    /// the `EditorCore` module, whose `Package.swift` declares `escape_plan/Fixtures` as a
    /// processed resource. `Bundle(for:)` would return the xctest bundle there and find
    /// nothing, which is why no package test could load a fixture before 2026-09-24.
    static let bundle = Bundle.module
    #else
    /// Resolves to the app bundle even when called from the test target, since
    /// escape_planTests does `@testable import escape_plan` and this type is compiled
    /// into the app module.
    private final class BundleToken {}
    static let bundle = Bundle(for: BundleToken.self)
    #endif

    static func data(for fixture: HomeFixture) throws -> Data {
        guard let url = bundle.url(forResource: fixture.rawValue, withExtension: "json") else {
            throw FixtureLoaderError.missingResource(fixture.rawValue)
        }
        return try Data(contentsOf: url)
    }

    static func load(_ fixture: HomeFixture) throws -> HomeModel {
        try HomeModel.decoder.decode(HomeModel.self, from: data(for: fixture))
    }
}
