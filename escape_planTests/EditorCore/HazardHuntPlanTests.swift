//  HazardHuntPlanTests.swift — the guided hunt's question generation.
//
//  These exist because the questions used to live inside a SwiftUI view where no test could
//  reach them, and three defects hid there (docs/decisions.md, 2026-09-10). The first test
//  below is the regression guard for the worst of them: the water-heater question was inverted,
//  so answering honestly about an UNSTRAPPED heater recorded nothing at all.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

@MainActor
final class HazardHuntPlanTests: XCTestCase {

    // MARK: Builders

    private func room(_ id: String, _ name: String, _ type: RoomType,
                      _ polygon: [Point] = square(6)) -> Room {
        Room(id: id, name: name, type: type, polygon: polygon, source: .scan, confidence: 0.9)
    }

    nonisolated private static func square(_ side: Double) -> [Point] {
        [Point(0, 0), Point(side, 0), Point(side, side), Point(0, side)]
    }

    private func object(_ id: String, _ category: ObjectCategory, at center: Point,
                        size: [Double] = [0.8, 0.4], height: Double = 1.8,
                        source: Source = .scan, secured: Bool = false,
                        mounted: Bool = false) -> FloorObject {
        FloorObject(id: id, category: category, center: center, size_m: size, height_m: height,
                    source: source, confidence: source == .scan ? 0.8 : nil,
                    secured: secured, elevation_m: 0, mounted: mounted)
    }

    private func ids(_ key: String) -> String { "new-\(key)" }

    private func plan(_ room: Room, _ objects: [FloorObject] = []) -> [HazardHuntQuestion] {
        HazardHuntPlan.questions(for: room, floorId: "f1", objects: objects, newObjectId: ids)
    }

    private func question(_ id: String, in questions: [HazardHuntQuestion]) throws
        -> HazardHuntQuestion {
        try XCTUnwrap(questions.first { $0.id == id }, "no question with id \(id)")
    }

    // MARK: The inverted water-heater question

    /// THE REGRESSION GUARD. Old behavior: one question, "Water heater — strapped?", whose Yes
    /// created a SECURED heater and whose No created nothing — so the person with the actual
    /// hazard answered truthfully and the model learned nothing. Every answer must now land.
    func testUnstrappedWaterHeaterIsRecordedInsteadOfDropped() throws {
        let garage = room("r_garage", "Garage", .garage)
        let qs = plan(garage)

        let presence = try question("identify.waterHeater", in: qs)
        let strap = try question("strap.waterHeater", in: qs)
        XCTAssertEqual(strap.requiresYesOf, presence.id,
                       "the strap question is only meaningful after a heater exists")

        // Yes there is one, No it is not strapped — the dangerous combination.
        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        for action in presence.yes { store.dispatch(action) }
        for action in strap.no { store.dispatch(action) }

        let heater = try XCTUnwrap(store.activeFloor.objects.first { $0.category == .water_heater })
        XCTAssertFalse(heater.secured, "an unstrapped water heater must survive into the model")
        XCTAssertModelValid(store.model)
    }

    func testStrappedWaterHeaterIsRecordedAsSecured() throws {
        let qs = plan(room("r_util", "Utility Room", .other))
        let presence = try question("identify.waterHeater", in: qs)
        let strap = try question("strap.waterHeater", in: qs)

        let store = try HomeModelStore.testStore(try Fixtures.load("bungalow"))
        for action in presence.yes { store.dispatch(action) }
        for action in strap.yes { store.dispatch(action) }

        let heater = try XCTUnwrap(store.activeFloor.objects.first { $0.category == .water_heater })
        XCTAssertTrue(heater.secured)
    }

    func testSayingNoToTheWaterHeaterLeavesTheModelUntouched() throws {
        let qs = plan(room("r_garage", "Garage", .garage))
        let presence = try question("identify.waterHeater", in: qs)
        XCTAssertTrue(presence.no.isEmpty, "no heater means nothing to write down")
    }

    func testWaterHeaterIsNotAskedAboutInAnOrdinaryRoom() {
        let qs = plan(room("r_bed", "Bedroom", .bedroom))
        XCTAssertNil(qs.first { $0.id.contains("waterHeater") })
    }

    /// The scan sees the box, it just calls it `appliance`. Confirming must relabel that object
    /// rather than stack a second water heater on top of it.
    func testScannedApplianceIsOfferedAsTheWaterHeaterInsteadOfANewObject() throws {
        let util = room("r_util", "Basement Utility", .other)
        let appliance = object("o_app", .appliance, at: Point(3, 3), size: [0.6, 0.6], height: 1.5)
        let qs = plan(util, [appliance])

        let presence = try question("identify.waterHeater", in: qs)
        XCTAssertEqual(presence.subject, .existing(objectId: "o_app"))
        XCTAssertEqual(presence.yes,
                       [.setObjectCategory(objectId: "o_app", category: .water_heater)])
        XCTAssertNil(presence.placementHint, "the scan already knows where it is")
    }

    // MARK: Asking about what the scan found

    func testTallScannedStorageIsOfferedForRelabellingNotDuplicated() throws {
        let bedroom = room("r_bed", "Bedroom", .bedroom)
        let storage = object("o_store", .storage, at: Point(1, 1), height: 1.9)
        let qs = plan(bedroom, [storage])

        let identify = try question("identify.bookcase.o_store", in: qs)
        XCTAssertEqual(identify.subject, .existing(objectId: "o_store"))
        XCTAssertEqual(identify.yes,
                       [.setObjectCategory(objectId: "o_store", category: .bookcase)])
        XCTAssertNil(qs.first { $0.id == "add.bookcase" },
                     "the scan already found something topple-prone; do not also ask cold")
    }

    func testShortStorageIsNotMistakenForABookcase() {
        let qs = plan(room("r_bed", "Bedroom", .bedroom),
                      [object("o_low", .storage, at: Point(1, 1), height: 0.6)])
        XCTAssertNil(qs.first { $0.id.hasPrefix("identify.bookcase") })
    }

    func testHandPlacedObjectsAreNotOfferedForRelabelling() {
        let qs = plan(room("r_bed", "Bedroom", .bedroom),
                      [object("o_manual", .storage, at: Point(1, 1), height: 1.9,
                              source: .manual)])
        XCTAssertNil(qs.first { $0.id.hasPrefix("identify.bookcase") },
                     "the user already told us what it is")
    }

    func testObjectsInOtherRoomsAreIgnored() {
        let bedroom = room("r_bed", "Bedroom", .bedroom, Self.square(4))
        let elsewhere = object("o_far", .storage, at: Point(40, 40), height: 1.9)
        let qs = plan(bedroom, [elsewhere])
        XCTAssertNil(qs.first { $0.id.contains("o_far") })
    }

    // MARK: The strap question

    func testEveryToppleProneObjectGetsAStrapQuestion() {
        let bedroom = room("r_bed", "Bedroom", .bedroom)
        let qs = plan(bedroom, [
            object("o_a", .bookcase, at: Point(1, 1)),
            object("o_b", .wardrobe, at: Point(2, 2)),
            object("o_c", .bed, at: Point(3, 3), size: [1.4, 2.0], height: 0.5),
        ])
        XCTAssertNotNil(qs.first { $0.id == "strap.o_a" })
        XCTAssertNotNil(qs.first { $0.id == "strap.o_b" })
        XCTAssertNil(qs.first { $0.id == "strap.o_c" }, "a bed does not topple")
    }

    /// `secured` defaults to false, so a No looks like a no-op — but a recorded false is an
    /// answer and a defaulted false is an assumption. Dispatch it.
    func testStrapNoWritesSecuredFalseRatherThanSkipping() throws {
        let qs = plan(room("r_bed", "Bedroom", .bedroom),
                      [object("o_a", .bookcase, at: Point(1, 1))])
        let strap = try question("strap.o_a", in: qs)
        XCTAssertEqual(strap.no, [.setObjectSecured(objectId: "o_a", secured: false)])
        XCTAssertEqual(strap.yes, [.setObjectSecured(objectId: "o_a", secured: true)])
    }

    func testMountedObjectsAreNotAskedAboutStrapping() {
        let qs = plan(room("r_liv", "Living Room", .living),
                      [object("o_shelf", .storage, at: Point(1, 1), mounted: true)])
        XCTAssertNil(qs.first { $0.id == "strap.o_shelf" },
                     "a wall-mounted shelf is not a floor-standing topple risk")
    }

    // MARK: Placement — the fix for everything landing in the middle of the room

    func testFallbackBookcaseIsPlacedBesideTheBedNotTheRoomCentre() throws {
        let bedroom = room("r_bed", "Bedroom", .bedroom, Self.square(6))
        let bed = object("o_bed", .bed, at: Point(2, 2), size: [1.4, 2.0], height: 0.5)
        let add = try question("add.bookcase", in: plan(bedroom, [bed]))

        guard case .addObject(_, _, _, let center, _, _) = add.yes.first else {
            return XCTFail("expected an addObject")
        }
        XCTAssertNotEqual(center, HazardHuntPlan.centroid(bedroom.polygon))
        XCTAssertTrue(Geometry.contains(bedroom.polygon, center), "must land inside the room")
        XCTAssertLessThan(Geometry.distance(center, bed.center), 2.0, "must land beside the bed")
        XCTAssertNil(add.placementHint, "derived from real geometry, so no drag-it prompt")
    }

    func testFallbackBookcaseAsksForPlacementWhenThereIsNoBed() throws {
        let add = try question("add.bookcase", in: plan(room("r_bed", "Bedroom", .bedroom)))
        XCTAssertNotNil(add.placementHint, "nothing to anchor to — say so instead of guessing")
    }

    func testPlaceBesideFallsBackWhenEverySideIsOutsideTheRoom() {
        let tiny: [Point] = [Point(0, 0), Point(0.5, 0), Point(0.5, 0.5), Point(0, 0.5)]
        let bed = object("o_bed", .bed, at: Point(0.25, 0.25), size: [1.4, 2.0], height: 0.5)
        XCTAssertNil(HazardHuntPlan.placeBeside(bed, size: [0.8, 0.4], inside: tiny))
    }

    // MARK: The mounted question needs something to be mounted above

    func testMountedQuestionIsSkippedWhenTheRoomHasNoBed() {
        let qs = plan(room("r_bed", "Bedroom", .bedroom))
        XCTAssertNil(qs.first { $0.id == "add.mounted" },
                     "'above the bed' is meaningless without a bed")
    }

    func testMountedObjectLandsOverTheBedElevatedAndFlagged() throws {
        let bed = object("o_bed", .bed, at: Point(2, 2), size: [1.4, 2.0], height: 0.5)
        let mounted = try question("add.mounted", in: plan(room("r_bed", "Bedroom", .bedroom), [bed]))

        XCTAssertEqual(mounted.yes.count, 3)
        guard case .addObject(let id, _, let category, let center, _, _) = mounted.yes[0] else {
            return XCTFail("expected an addObject")
        }
        XCTAssertEqual(category, .tv)
        XCTAssertEqual(center, bed.center, "'above the bed' means at the bed")
        XCTAssertEqual(mounted.yes[1], .setObjectMounted(objectId: id, mounted: true))
        XCTAssertEqual(mounted.yes[2],
                       .setObjectElevation(objectId: id,
                                           elevation_m: HazardHuntPlan.mountedTVElevation_m))
    }

    // MARK: Heater

    func testHeaterIsAskedAboutInLivingSpacesButNotWetOrCookingRooms() {
        XCTAssertNotNil(plan(room("r_liv", "Living Room", .living)).first { $0.id == "add.heater" })
        XCTAssertNotNil(plan(room("r_hall", "Hall", .hall)).first { $0.id == "add.heater" })
        XCTAssertNil(plan(room("r_bath", "Bathroom", .bath)).first { $0.id == "add.heater" })
        XCTAssertNil(plan(room("r_kit", "Kitchen", .kitchen)).first { $0.id == "add.heater" })
    }

    func testHeaterAsksTheUserToPlaceIt() throws {
        let heater = try question("add.heater", in: plan(room("r_liv", "Living Room", .living)))
        XCTAssertNotNil(heater.placementHint,
                        "a portable heater has no scanned position to inherit")
    }

    // MARK: Determinism

    func testTheSameRoomAlwaysProducesTheSameQuestionsInTheSameOrder() {
        let bedroom = room("r_bed", "Bedroom", .bedroom)
        let objects = [
            object("o_b", .wardrobe, at: Point(2, 2)),
            object("o_a", .storage, at: Point(1, 1), height: 1.9),
        ]
        XCTAssertEqual(plan(bedroom, objects).map(\.id), plan(bedroom, objects).map(\.id))
    }
}
