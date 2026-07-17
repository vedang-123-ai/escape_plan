// FixtureLoader.swift
// Loads the schema/fixtures/*.json test bed (bundled as app resources into escape_plan/Fixtures/,
// copied from the project-wide fixtures — see docs/decisions.md for why they're copies and not
// symlinks). Used by the Home screen (proof-of-decode) and by the round-trip test target.

import Foundation

enum HomeFixture: String, CaseIterable {
    case bungalow
    case apartment
    case twostory
}

enum FixtureLoaderError: Error {
    case missingResource(String)
}

enum FixtureLoader {
    /// Resolves to the app bundle even when called from the test target, since
    /// escape_planTests does `@testable import escape_plan` and this type is compiled
    /// into the app module.
    private final class BundleToken {}
    static let bundle = Bundle(for: BundleToken.self)

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
