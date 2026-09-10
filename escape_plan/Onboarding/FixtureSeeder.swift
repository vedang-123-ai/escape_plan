// FixtureSeeder.swift
// S4.1: seeds the bundled twostory fixture as a starter home so the onboarding flow can run
// end-to-end before real device scans exist (S1.4/S1.5). A few items are re-marked as
// scan-derived with low confidence — exactly what the converter emits for uncertain surfaces —
// so the "N items need review" step exercises the real review path. The fixture file itself
// is never modified; the seeded copy is an ordinary home document under a fresh home_id.

import Foundation

enum FixtureSeeder {
    /// Confidence given to the flagged items — comfortably under
    /// `HitTesting.needsReviewThreshold` (0.5).
    static let flaggedConfidence = 0.4

    /// How many items `flagAsScanned` re-marks (first room of the top floor, then the first
    /// openings encountered until the budget is spent).
    static let flaggedItemBudget = 3

    /// Pure transform: fresh `home_id`, demo name, and up to `flaggedItemBudget` items
    /// re-marked `source: .scan` with low confidence. Deterministic apart from the UUID.
    static func flagAsScanned(_ model: HomeModel,
                              homeID: String = UUID().uuidString.lowercased()) -> HomeModel {
        var seeded = model
        seeded.home_id = homeID
        seeded.name = "Demo Home (scanned)"

        var remaining = flaggedItemBudget

        // Highest floor first so the flagged room is the one the demo talks about (bedrooms
        // are upstairs in twostory).
        if let floorIndex = seeded.floors.indices.max(by: {
            seeded.floors[$0].level < seeded.floors[$1].level
        }), !seeded.floors[floorIndex].rooms.isEmpty, remaining > 0 {
            seeded.floors[floorIndex].rooms[0].source = .scan
            seeded.floors[floorIndex].rooms[0].confidence = flaggedConfidence
            remaining -= 1
        }

        for floorIndex in seeded.floors.indices where remaining > 0 {
            for openingIndex in seeded.floors[floorIndex].openings.indices where remaining > 0 {
                seeded.floors[floorIndex].openings[openingIndex].source = .scan
                seeded.floors[floorIndex].openings[openingIndex].confidence = flaggedConfidence
                remaining -= 1
            }
        }

        return seeded
    }

    /// Loads the twostory fixture, flags it, and saves it only into an empty library.
    /// Fully local — works with no network and no backend.
    @discardableResult
    static func seedDemoHome(into store: HomeDocumentStore) throws -> HomeModel? {
        guard store.list().isEmpty else { return nil }
        let seeded = flagAsScanned(try FixtureLoader.load(.twostory))
        try store.save(model: seeded)
        return seeded
    }

    // MARK: - Starter library

    /// Set once the three starter homes have been installed, so a home the user
    /// deleted on purpose is never resurrected on the next launch.
    static let starterSeedDefaultsKey = "fixtures.starterHomesSeeded.v1"

    /// Installs Bungalow, Apartment 4B, and Two-Story House verbatim on a fresh
    /// install, so the demo path exists without anyone hand-building it.
    ///
    /// Seeded verbatim on purpose — each fixture keeps its own `home_id`, which
    /// makes a re-run overwrite the same three documents instead of piling up
    /// copies (the failure mode that left this simulator with fourteen homes all
    /// called "New Home"). The names the app shows are the fixtures' own, so the
    /// screenshot drivers and the demo script can address them by name.
    ///
    /// Separate from `seedDemoHome`: that one deliberately degrades a copy to
    /// look scan-derived so onboarding's review step has something to review.
    /// These three are the clean article.
    @discardableResult
    static func seedStarterHomes(
        into store: HomeDocumentStore,
        defaults: UserDefaults = .standard
    ) throws -> [HomeModel] {
        guard !defaults.bool(forKey: starterSeedDefaultsKey) else { return [] }
        var seeded: [HomeModel] = []
        for fixture in HomeFixture.allCases {
            let model = try FixtureLoader.load(fixture)
            try store.save(model: model)
            seeded.append(model)
        }
        defaults.set(true, forKey: starterSeedDefaultsKey)
        return seeded
    }
}

// MARK: - Review rows

/// One item the review step lists — built with the same `HitTesting.needsReview` predicate
/// the editor's pulsing badges use, so onboarding and editor always agree on N.
struct ReviewItem: Identifiable, Equatable {
    enum Kind: String {
        case room = "Room"
        case opening = "Opening"
        case stairs = "Stairs"
    }

    var id: String
    var kind: Kind
    var name: String
    var floorName: String
    var confidence: Double?
}

extension ReviewItem {
    /// Every low-confidence scan item in the model, floor by floor.
    static func items(in model: HomeModel) -> [ReviewItem] {
        var items: [ReviewItem] = []
        for floor in model.floors {
            for room in floor.rooms
            where HitTesting.needsReview(source: room.source, confidence: room.confidence) {
                items.append(ReviewItem(id: room.id, kind: .room, name: room.name,
                                        floorName: floor.name, confidence: room.confidence))
            }
            for opening in floor.openings
            where HitTesting.needsReview(source: opening.source, confidence: opening.confidence) {
                let name = opening.kind.rawValue.replacingOccurrences(of: "_", with: " ")
                    .capitalized
                items.append(ReviewItem(id: opening.id, kind: .opening, name: name,
                                        floorName: floor.name, confidence: opening.confidence))
            }
        }
        let floorNames = Dictionary(uniqueKeysWithValues: model.floors.map { ($0.id, $0.name) })
        for stair in model.stairs
        where HitTesting.needsReview(source: stair.source, confidence: stair.confidence) {
            items.append(ReviewItem(id: stair.id, kind: .stairs, name: "Stairs",
                                    floorName: floorNames[stair.from.floor_id] ?? "",
                                    confidence: stair.confidence))
        }
        return items
    }
}
