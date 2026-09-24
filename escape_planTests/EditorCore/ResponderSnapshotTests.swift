// ResponderSnapshotTests.swift — S11.6: "Share with your fire department".
//
// THESE NOW ACTUALLY RUN. They used to sit in the app test target, which needs `xcodebuild
// test` on a simulator — so the assertions that carry this feature's privacy promises (names
// absent unless consent opts in; every snapshot carries as_of and the disclaimer) were
// written, typechecked, and never once executed. Moved into the shared EditorCore folder on
// 2026-09-24, which required lifting `EscapePlanDocument` out of the UIKit-importing
// `EscapePlanPDF.swift` so the extractor could compile in the Foundation-only package.
//
// Keep the whole snapshot path Foundation-only or this coverage silently disappears again.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

final class ResponderSnapshotTests: XCTestCase {
    func testAnonymityOfSnapshot() throws {
        let parent = Profile(id: "p1", name: "Alice", tags: [ProfileTag.vision_impaired], bedroom_room_id: "bed1")
        let child = Profile(id: "p2", name: "Bob", tags: [ProfileTag.mobility_limited], bedroom_room_id: "bed1")

        let floor = Floor(id: "f1", level: 1, name: "First Floor", height_m: 3, rooms: [
            Room(id: "bed1", name: "Master Bedroom", type: .bedroom, polygon: [], source: .manual)
        ])

        let home = HomeModel(
            schema_version: "1",
            home_id: "h1",
            name: "Test Home",
            floors: [floor],
            stairs: [],
            profiles: [parent, child],
            meta: Meta(created: Date(), modified: Date(), last_scanned: Date()),
            household: nil
        )

        let plan = EscapePlanDocument(
            home: home,
            plan: nil,
            scoreResponse: nil,
            isResponderSnapshot: true
        )

        // Default consent: names excluded.
        let json = ResponderSnapshotExtractor.extract(from: plan, consent: .acknowledgedNow())
        let jsonEncoder = JSONEncoder()
        let jsonData = try jsonEncoder.encode(json)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("Alice"), "JSON must not contain the name Alice")
        XCTAssertFalse(jsonString.contains("Bob"), "JSON must not contain the name Bob")
        XCTAssertTrue(jsonString.contains("count\":2"), "JSON must have count of 2 for the room")
        XCTAssertNil(json.vulnerableOccupants.first?.names, "names must be nil, not [], when not opted in")

        // The PDF half needs UIGraphicsPDFRenderer, so it compiles only in the app target and
        // still waits on a simulator. The JSON assertions above — the ones carrying the
        // privacy promise — now run in the package on every commit.
        #if !SWIFT_PACKAGE
        let pdfOutput = EscapePlanPDF.render(plan)
        guard let pdfString = String(data: pdfOutput.data, encoding: .utf8) ?? String(data: pdfOutput.data, encoding: .ascii) else {
            return
        }
        XCTAssertFalse(pdfString.contains("Alice"), "PDF must not contain the name Alice")
        XCTAssertFalse(pdfString.contains("Bob"), "PDF must not contain the name Bob")
        #endif
    }

    /// The one privacy escape hatch: a resident who explicitly opts in gets names next to
    /// the room, in the JSON only — the printed PDF stays anonymous unconditionally (S11.6
    /// decisions.md: paper can be left lying around; the JSON is what a department records).
    func testNamesAppearOnlyWhenConsentOptsIn() throws {
        let parent = Profile(id: "p1", name: "Alice", tags: [ProfileTag.vision_impaired], bedroom_room_id: "bed1")
        let floor = Floor(id: "f1", level: 1, name: "First Floor", height_m: 3, rooms: [
            Room(id: "bed1", name: "Master Bedroom", type: .bedroom, polygon: [], source: .manual)
        ])
        let home = HomeModel(
            schema_version: "1", home_id: "h1", name: "Test Home", floors: [floor], stairs: [],
            profiles: [parent], meta: Meta(created: Date(), modified: Date(), last_scanned: Date()),
            household: nil
        )
        let plan = EscapePlanDocument(home: home, plan: nil, scoreResponse: nil, isResponderSnapshot: true)

        let optedOut = ResponderSnapshotExtractor.extract(from: plan, consent: .acknowledgedNow(includeOccupantNames: false))
        XCTAssertNil(optedOut.vulnerableOccupants.first?.names)

        let optedIn = ResponderSnapshotExtractor.extract(from: plan, consent: .acknowledgedNow(includeOccupantNames: true))
        XCTAssertEqual(optedIn.vulnerableOccupants.first?.names, ["Alice"])

        // The PDF never shows names, regardless of the JSON's consent — it stays anonymous
        // by construction rather than by threading consent through the renderer too.
        #if !SWIFT_PACKAGE
        let pdfOutput = EscapePlanPDF.render(plan)
        let pdfString = String(data: pdfOutput.data, encoding: .utf8) ?? String(data: pdfOutput.data, encoding: .ascii) ?? ""
        XCTAssertFalse(pdfString.contains("Alice"))
        #endif
    }

    /// Acceptance: "the snapshot JSON always contains as_of, the disclaimer and consent
    /// flags" — regardless of whether the home was ever scanned.
    func testSnapshotAlwaysCarriesAsOfDisclaimerAndConsent() throws {
        let home = HomeModel(
            schema_version: "1", home_id: "h1", name: "Never Scanned Home", floors: [], stairs: [],
            profiles: [], meta: Meta(created: Date(), modified: Date(), last_scanned: nil), household: nil
        )
        let plan = EscapePlanDocument(home: home, plan: nil, scoreResponse: nil, isResponderSnapshot: true)
        let consent = SnapshotConsentDecision.acknowledgedNow(includeOccupantNames: true)
        let json = ResponderSnapshotExtractor.extract(from: plan, consent: consent)

        XCTAssertNil(json.asOf, "never-scanned home has no as_of date")
        XCTAssertTrue(json.isStale, "no scan date is unconditionally stale")
        XCTAssertEqual(json.stalenessNote, ResponderSnapshotJSON.fixedStalenessNote)
        XCTAssertFalse(json.stalenessNote.isEmpty)
        XCTAssertEqual(json.tacticalDisclaimer, ResponderSnapshotJSON.fixedTacticalDisclaimer)
        XCTAssertFalse(json.tacticalDisclaimer.isEmpty)
        XCTAssertEqual(json.consent, consent)

        let jsonData = try JSONEncoder().encode(json)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        for key in ["as_of", "stalenessNote", "tacticalDisclaimer", "consent", "hazardSummary"] {
            XCTAssertTrue(jsonString.contains("\"\(key)\""), "JSON is missing key \(key)")
        }
    }

    // FIXTURE-GATED: FixtureLoader resolves its bundle with Bundle(for:), which finds the
    // fixtures in the app test bundle but not in the SwiftPM package (no package test has
    // ever loaded a fixture — the other two FixtureLoader users here are !SWIFT_PACKAGE too).
    // Making fixtures a package resource means editing Package.swift AND the symlinked
    // FixtureLoader.swift; logged in BLOCKERS instead of risking it here.
    #if !SWIFT_PACKAGE
    /// Acceptance: "the hazard summary equals the engine's findings for the stock fixtures."
    /// There is no local Python venv on this machine (BLOCKERS §4) to run the live engine
    /// against `bungalow`/`apartment`/`twostory`, so this pins the contract that actually
    /// matters here instead: the extractor's `hazardSummary` is exactly
    /// `SnapshotHazardSummary.summarize` applied to whatever checklist the engine produced
    /// (via the cached `ScoreBreakdown`) — it never re-derives or edits the rollup. Flagged
    /// as simulator/venv-gated in the session note.
    func testHazardSummaryMatchesEngineChecklistOnStockFixtures() throws {
        let engineChecklist = [
            ChecklistItem(id: "routes.no_secondary_egress.room_1", category: .routes,
                          title: "Add a second way out", detail: "d", done: false,
                          source_citation: "nfpa-escape-planning", scoring: false),
            ChecklistItem(id: "egress.window.opening_3", category: .egress,
                          title: "Escape window too small", detail: "d", done: false,
                          source_citation: "irc-2021-r310", scoring: false),
            ChecklistItem(id: "hazard.topple.obj_2", category: .mitigation,
                          title: "Secure bookcase", detail: "d", done: false,
                          source_citation: "shakeout-guidance", scoring: false),
            // A preparedness suggestion, not a finding — must NOT appear in the summary.
            ChecklistItem(id: "mitigation.secure.obj_9", category: .mitigation,
                          title: "Secure wardrobe", detail: "d", done: false,
                          source_citation: "shakeout-guidance", scoring: false),
        ]
        let scoreResponse = ScoreBreakdown(
            home_id: "h1", home_name: "n", score: 70, sub_scores: [:], basis: nil,
            components: [], checklist: engineChecklist
        )

        for fixture: HomeFixture in [.bungalow, .apartment, .twostory] {
            let home = try FixtureLoader.load(fixture)
            let plan = EscapePlanDocument(home: home, plan: nil, scoreResponse: scoreResponse,
                                          isResponderSnapshot: true)
            let json = ResponderSnapshotExtractor.extract(from: plan, consent: .acknowledgedNow())
            XCTAssertEqual(json.hazardSummary, SnapshotHazardSummary.summarize(checklist: engineChecklist),
                           "\(fixture.rawValue): hazardSummary must equal the engine checklist rollup")
            XCTAssertEqual(json.hazardSummary.count, 3, "\(fixture.rawValue): the mitigation.secure.* item must be excluded")
        }
    }
    #endif
}

extension ResponderSnapshotTests {
    // FIXTURE-GATED: FixtureLoader resolves its bundle with Bundle(for:), which finds the
    // fixtures in the app test bundle but not in the SwiftPM package (no package test has
    // ever loaded a fixture — the other two FixtureLoader users here are !SWIFT_PACKAGE too).
    // Making fixtures a package resource means editing Package.swift AND the symlinked
    // FixtureLoader.swift; logged in BLOCKERS instead of risking it here.
    #if !SWIFT_PACKAGE
    func testTwostoryFixtureAnonymity() throws {
        var home = try FixtureLoader.load(.twostory)

        // Give someone a name so we can assert it is stripped
        home.profiles[0].name = "Grandpa Joe"
        home.profiles[0].tags.append(.mobility_limited)
        home.meta.last_scanned = nil // Force stale

        let plan = EscapePlanDocument(
            home: home,
            plan: nil,
            scoreResponse: nil,
            isResponderSnapshot: true
        )

        let json = ResponderSnapshotExtractor.extract(from: plan, consent: .acknowledgedNow())

        // Stale test
        XCTAssertTrue(json.isStale)
        XCTAssertNil(json.asOf)

        let jsonEncoder = JSONEncoder()
        let jsonData = try jsonEncoder.encode(json)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("Grandpa Joe"), "JSON must not contain the name")
        // The twostory fixture might have multiple profiles, but at least 1 is mobility_limited now.
        XCTAssertTrue(json.vulnerableOccupants.count > 0, "Should have at least 1 vulnerable occupant count")

        let pdfOutput = EscapePlanPDF.render(plan)
        XCTAssertTrue(pdfOutput.data.count > 0, "PDF renders without error and produces data")

        guard let pdfString = String(data: pdfOutput.data, encoding: .utf8) ?? String(data: pdfOutput.data, encoding: .ascii) else {
            return
        }
        XCTAssertFalse(pdfString.contains("Grandpa Joe"), "PDF bytes must not contain the name")
    }
    #endif
}
