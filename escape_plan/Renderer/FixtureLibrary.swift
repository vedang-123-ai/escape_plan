import Foundation

/// The three project-wide test homes from `schema/fixtures/`, bundled so the renderer demo can
/// load them without a backend.
///
/// The copies in `escape_plan/Fixtures/` are verbatim duplicates of `schema/fixtures/` because
/// the app bundle can't reach out of its own resources at runtime; `FixtureLibraryTests` fails
/// if they drift from the originals. Since S2.4 (persistence) landed, real homes come from disk
/// and these are demo-only seeds — used by the renderer demo and by S4.1's onboarding seeder.
enum Fixture: String, CaseIterable, Identifiable {
    case bungalow
    case apartment
    case twostory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bungalow: return "Bungalow"
        case .apartment: return "Apartment"
        case .twostory: return "Two-Story"
        }
    }
}

enum FixtureLoadError: LocalizedError {
    case notFound(String)
    case decodeFailed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Fixture '\(name).json' is not in the app bundle."
        case .decodeFailed(let name, let underlying):
            return "Fixture '\(name).json' did not match the HomeModel schema: \(underlying)"
        }
    }
}

enum FixtureLibrary {
    static func load(_ fixture: Fixture, from bundle: Bundle = .main) throws -> HomeModel {
        guard let url = bundle.url(forResource: fixture.rawValue, withExtension: "json") else {
            throw FixtureLoadError.notFound(fixture.rawValue)
        }
        let data = try Data(contentsOf: url)
        do {
            return try HomeModel.decoder.decode(HomeModel.self, from: data)
        } catch {
            throw FixtureLoadError.decodeFailed(fixture.rawValue, underlying: error)
        }
    }
}
