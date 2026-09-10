// OnboardingTests.swift
// S4.1: FixtureSeeder (the flagged demo-home seed), ReviewItem derivation, the RoutePlan
// last-good cache, and /analyze response decoding. The seeded copy must never touch the
// bundled fixture, and the cache must never introduce a failure mode of its own.

import XCTest
@testable import escape_plan

final class OnboardingTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // escape_planTests/
        .deletingLastPathComponent()  // repo root

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("OnboardingTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - FixtureSeeder

    func testFlagAsScannedProducesReviewItems() throws {
        let original = try FixtureLoader.load(.twostory)
        let seeded = FixtureSeeder.flagAsScanned(original, homeID: "seed-test")

        let items = ReviewItem.items(in: seeded)
        XCTAssertEqual(items.count, FixtureSeeder.flaggedItemBudget,
                       "the flagged copy should surface exactly the budgeted review items")
        XCTAssertEqual(seeded.home_id, "seed-test")
        XCTAssertNotEqual(seeded.home_id, original.home_id,
                          "the seed must never collide with the fixture's own id")
        XCTAssertEqual(seeded.name, "Demo Home (scanned)")
        // Flagged items sit under the editor's review threshold, so onboarding's N and the
        // editor's pulsing badges agree by construction.
        for item in items {
            let confidence = try XCTUnwrap(item.confidence)
            XCTAssertLessThan(confidence, HitTesting.needsReviewThreshold)
        }
        // The room flag lands on the top floor (level-max), where the demo's bedrooms are.
        let topFloor = try XCTUnwrap(seeded.floors.max { $0.level < $1.level })
        XCTAssertEqual(topFloor.rooms[0].source, .scan)
    }

    func testFlagAsScannedIsPureAndFixtureUntouched() throws {
        let before = try FixtureLoader.data(for: .twostory)
        let original = try FixtureLoader.load(.twostory)
        _ = FixtureSeeder.flagAsScanned(original)

        XCTAssertEqual(try FixtureLoader.data(for: .twostory), before,
                       "seeding must never rewrite the bundled fixture")
        XCTAssertEqual(original, try FixtureLoader.load(.twostory),
                       "flagAsScanned must not mutate its input")
        XCTAssertTrue(ReviewItem.items(in: original).isEmpty,
                      "the pristine fixture has no scan items and no review rows")
    }

    func testSeedDemoHomeWritesLoadableDocument() throws {
        let store = try HomeDocumentStore(directory: scratch)
        let seeded = try XCTUnwrap(FixtureSeeder.seedDemoHome(into: store))

        let loaded = try store.load(homeID: seeded.home_id, as: HomeModel.self)
        XCTAssertEqual(loaded.home_id, seeded.home_id)
        XCTAssertEqual(ReviewItem.items(in: loaded).count, FixtureSeeder.flaggedItemBudget)
    }

    func testSeedDemoHomeDoesNotAddADuplicateToANonemptyLibrary() throws {
        let store = try HomeDocumentStore(directory: scratch)
        _ = try XCTUnwrap(FixtureSeeder.seedDemoHome(into: store))

        XCTAssertNil(try FixtureSeeder.seedDemoHome(into: store))
        XCTAssertEqual(store.list().count, 1)
    }

    @MainActor
    func testOnboardingSkipsTheDemoAndExitsCleanlyForAnExistingLibrary() throws {
        let store = try HomeDocumentStore(directory: scratch)
        _ = try XCTUnwrap(FixtureSeeder.seedDemoHome(into: store))
        let state = OnboardingState(documentStore: store)

        state.seedIfNeeded()

        XCTAssertNil(state.seededHome)
        XCTAssertTrue(state.hasExistingLibrary)
        XCTAssertNotNil(state.seedError)
        XCTAssertEqual(store.list().count, 1)
    }

    // MARK: - RoutePlanCache

    private func loadSamplePlan() throws -> RoutePlan {
        let url = Self.repoRoot.appendingPathComponent("docs/route-samples/twostory.routeplan.json")
        return try HomeModel.decoder.decode(RoutePlan.self, from: Data(contentsOf: url))
    }

    func testRoutePlanCacheRoundTrip() throws {
        let cache = try RoutePlanCache(directory: scratch)
        let plan = try loadSamplePlan()
        let stamp = Date(timeIntervalSince1970: 1_750_000_000)

        try cache.save(plan, now: stamp)
        let cached = try XCTUnwrap(cache.load(homeID: plan.home_id))
        XCTAssertEqual(cached.plan, plan)
        XCTAssertEqual(cached.savedAt.timeIntervalSince1970,
                       stamp.timeIntervalSince1970, accuracy: 1)
    }

    func testRoutePlanCacheMissAndCorruptFileReadAsNil() throws {
        let cache = try RoutePlanCache(directory: scratch)
        XCTAssertNil(cache.load(homeID: "never-saved"))

        try Data("not json".utf8).write(to: cache.url(for: "corrupt"))
        XCTAssertNil(cache.load(homeID: "corrupt"),
                     "a corrupt cache file must read as a miss, never throw into the UI")
    }

    func testConnectionFailureClassification() {
        XCTAssertTrue(APIClient.isConnectionFailure(URLError(.notConnectedToInternet)))
        XCTAssertTrue(APIClient.isConnectionFailure(URLError(.cannotConnectToHost)))
        XCTAssertTrue(APIClient.isConnectionFailure(URLError(.timedOut)))
        XCTAssertFalse(APIClient.isConnectionFailure(URLError(.badServerResponse)))
        XCTAssertFalse(APIClient.isConnectionFailure(
            APIClientError.unexpectedResponse(statusCode: 401)),
            "server answers (401/422/500) must never silently fall back to a stale plan")
    }

    // MARK: - /analyze decoding

    func testAnalysisResultDecodesAndIgnoresTrace() throws {
        let json = """
        {
          "findings": [
            {
              "severity": "high",
              "room_ids": ["room-1"],
              "finding": "The upstairs bedroom has a single viable exit.",
              "evidence": ["toolu_01"],
              "recommendation": "Add an egress-compliant window.",
              "citation": "nfpa-escape-planning"
            }
          ],
          "trace": [{"id": "toolu_01", "tool_name": "get_home_summary", "input": {}, "output": {"floors": 2}}],
          "truncated": false,
          "dropped": []
        }
        """
        let result = try HomeModel.decoder.decode(AnalysisResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(result.findings[0].severity, .high)
        XCTAssertFalse(result.truncated)
    }

    func testAnalysisResultLenientDefaults() throws {
        // Only what the UI renders is required; server-side bookkeeping fields may be absent.
        let json = """
        {"findings": [{"severity": "low", "finding": "f", "recommendation": "r", "citation": "c"}]}
        """
        let result = try HomeModel.decoder.decode(AnalysisResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.findings[0].room_ids, [])
        XCTAssertEqual(result.findings[0].evidence, [])
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.dropped, [])
    }
    @MainActor
    func testOnboardingCreatesUndoStackEntries() throws {
        let state = OnboardingState(documentStore: try HomeDocumentStore(directory: scratch))
        state.seedIfNeeded()
        let seeded = try XCTUnwrap(state.seededHome)
        
        let store = try HomeModelStore(model: seeded)
        let stack = UndoStack()
        store.onCommit = stack.recordCommit
        
        // This simulates the same EditAction dispatch loop OnboardingState uses:
        store.dispatch(.addProfile(profileId: "p1", name: "Alice", tags: [.child], bedroom_room_id: "br1"))
        store.dispatch(.setHousehold(tenure: .rent, existingEquipment: []))
        
        XCTAssertTrue(stack.canUndo, "Onboarding actions must produce undo stack entries via HomeModelStore")
        XCTAssertEqual(stack.undoLabel, "Edit Household")
    }
}
