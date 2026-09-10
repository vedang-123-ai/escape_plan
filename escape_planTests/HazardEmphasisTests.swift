//  HazardEmphasisTests.swift — S7.7's two unit-testable halves:
//  (1) checklist row → object id, against the ids the home actually has, and
//  (2) the advisory ring landing on exactly the named nodes, leaving every other object's
//      RenderOrder untouched.
//
//  The route ids join culprits with "-" and object ids CONTAIN "-" (the converter emits
//  `obj-<hex>`, the hazard hunt a raw UUID), which is the whole reason resolution goes through
//  the model instead of a string split. The hyphen cases below are the regression guard.

import SceneKit
import XCTest
@testable import escape_plan

@MainActor
final class HazardEmphasisTests: XCTestCase {

    // MARK: - Row → object id

    private let known = ["obj-1a2b3c4d", "obj-9f8e7d6c", "3F2A5B10-4C1D-4E2F-9A80-BB1122334455"]

    func testHazardRowResolvesToItsObject() {
        XCTAssertEqual(
            ChecklistObjectIDs.resolve(itemID: "hazard.heat_clearance.obj-1a2b3c4d", known: known),
            ["obj-1a2b3c4d"])
    }

    func testGenericStrapItRowResolves_ownerAndRenterVariants() {
        XCTAssertEqual(
            ChecklistObjectIDs.resolve(itemID: "mitigation.secure.obj-9f8e7d6c", known: known),
            ["obj-9f8e7d6c"])
        XCTAssertEqual(
            ChecklistObjectIDs.resolve(itemID: "mitigation.secure.obj-9f8e7d6c.renter", known: known),
            ["obj-9f8e7d6c"])
    }

    /// The bug this file exists for: splitting the tail on "-" shreds every real object id.
    func testRouteRowWithHyphenatedIDsIsNotShredded() {
        XCTAssertEqual(
            ChecklistObjectIDs.resolve(itemID: "routes.blocked_opening.room-af3c.obj-1a2b3c4d",
                                       known: known),
            ["obj-1a2b3c4d"])
    }

    func testRouteRowWithMultipleCulpritsResolvesAllOfThemInOrder() {
        let id = "routes.narrows_route.room-af3c.obj-9f8e7d6c-obj-1a2b3c4d"
        XCTAssertEqual(ChecklistObjectIDs.resolve(itemID: id, known: known),
                       ["obj-9f8e7d6c", "obj-1a2b3c4d"])
    }

    /// A hazard-hunt object is a raw UUID — hyphens throughout, and uppercase.
    func testHuntCreatedUUIDObjectResolves() {
        XCTAssertEqual(
            ChecklistObjectIDs.resolve(itemID: "hazard.topple.3F2A5B10-4C1D-4E2F-9A80-BB1122334455",
                                       known: known),
            ["3F2A5B10-4C1D-4E2F-9A80-BB1122334455"])
    }

    /// A row pointing at an object that has since been deleted focuses nothing — never a
    /// near-miss match on some other object.
    func testDeletedOrUnknownObjectResolvesToNothing() {
        XCTAssertTrue(ChecklistObjectIDs.resolve(itemID: "hazard.topple.obj-deadbeef", known: known).isEmpty)
        XCTAssertTrue(ChecklistObjectIDs.resolve(itemID: "routes.blocked_opening.room-af3c.obstruction",
                                                 known: known).isEmpty)
    }

    func testRowsThatAreNotAboutAnObjectResolveToNothing() {
        for id in ["supply_kit.72h", "routes.no_secondary_egress.room-af3c",
                   "egress.window.op-1234", "engine.no_viable_route.room-af3c"] {
            XCTAssertTrue(ChecklistObjectIDs.resolve(itemID: id, known: known).isEmpty,
                          "\(id) should not resolve to an object")
        }
    }

    func testResolutionThroughTheModelUsesTheHomesOwnIDs() throws {
        let home = try FixtureLoader.load(.twostory)
        let objectID = try XCTUnwrap(home.floors.flatMap { $0.objects }.first?.id)
        let item = ChecklistItem(id: "hazard.topple.\(objectID)", category: .mitigation,
                                 title: "Strap it", detail: "…", done: false, scoring: false)
        XCTAssertEqual(item.objectIDs(in: home), [objectID])
    }

    // MARK: - Emphasis in the scene

    func testAdvisoryRingLandsOnTheNamedObjectsOnly() throws {
        let home = try FixtureLoader.load(.twostory)
        let floor = try XCTUnwrap(home.floors.first)
        let objects = floor.objects
        try XCTSkipIf(objects.count < 2, "fixture must carry at least two objects")
        let flagged = objects[0].id
        let untouched = objects[1].id

        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let controller = UnifiedSceneController(scnView: view, home: home)
        controller.currentHome = home
        controller.rebuild(home: home, activeFloorId: floor.id)
        // The builder starts on the top floor; the screen's own focusFloor drives it down. Do the
        // same here, or every object below is legitimately ghosted and the band check is moot.
        controller.dollhouse?.setActiveFloor(floor.id, animated: false)
        controller.setHazardObjects([flagged])

        let root = try XCTUnwrap(controller.dollhouse?.scene.rootNode)
        let flaggedNode = try XCTUnwrap(root.childNode(withName: "object:\(flagged)", recursively: true))
        let untouchedNode = try XCTUnwrap(root.childNode(withName: "object:\(untouched)", recursively: true))

        XCTAssertNotNil(flaggedNode.childNode(withName: "advisory_ring", recursively: true),
                        "the flagged object must carry the advisory ring")
        XCTAssertNil(untouchedNode.childNode(withName: "advisory_ring", recursively: true),
                     "an object the engine did not flag must be left alone")

        // Emphasis must not reorder the scene: furniture stays at RenderOrder.objects.
        XCTAssertEqual(flaggedNode.renderingOrder, RenderOrder.objects)
        XCTAssertEqual(untouchedNode.renderingOrder, RenderOrder.objects)
    }

    /// Clearing the set removes the emphasis — a checked-off hazard must stop glowing.
    func testClearingTheHazardSetRemovesEveryRing() throws {
        let home = try FixtureLoader.load(.twostory)
        let floor = try XCTUnwrap(home.floors.first)
        let flagged = try XCTUnwrap(floor.objects.first?.id)

        let view = SCNView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let controller = UnifiedSceneController(scnView: view, home: home)
        controller.currentHome = home
        controller.rebuild(home: home, activeFloorId: floor.id)
        controller.setHazardObjects([flagged])
        controller.setHazardObjects([])

        let root = try XCTUnwrap(controller.dollhouse?.scene.rootNode)
        XCTAssertNil(root.childNode(withName: "advisory_ring", recursively: true))
    }
}
