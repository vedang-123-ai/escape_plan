//  AppRouterTests.swift
//  The cross-tab router (Linear revamp). Audit 2026-09-25: `houseRequest` was never cleared,
//  and the House tab preferred it over the active home, so after one "Show me in the house"
//  tap, switching homes on the Home tab left the House tab showing the old home.

import XCTest
@testable import escape_plan

@MainActor
final class AppRouterTests: XCTestCase {

    func testOpenHouseRecordsTheRequestAndSwitchesTab() throws {
        let router = AppRouter()
        router.openHouse(homeID: "home-a", focusItemID: "alarm.bedroom")

        let request = try XCTUnwrap(router.houseRequest)
        XCTAssertEqual(request.homeID, "home-a")
        XCTAssertEqual(request.focusItemID, "alarm.bedroom")
        XCTAssertEqual(router.selectedTab, .house)
    }

    /// Trim 2 (2026-10-03): "Run a fire drill" is House on the fire simulation, not a pushed screen.
    func testOpenFireDrillAsksHouseForTheFireSimulation() throws {
        let router = AppRouter()
        router.selectedTab = .tasks
        router.openFireDrill(homeID: "home-a")

        let request = try XCTUnwrap(router.houseRequest)
        XCTAssertEqual(request.homeID, "home-a")
        XCTAssertNil(request.focusItemID)
        XCTAssertTrue(request.opensFireSimulation)
        XCTAssertEqual(router.selectedTab, .house)

        router.openHouse(homeID: "home-a")
        XCTAssertFalse(try XCTUnwrap(router.houseRequest).opensFireSimulation,
                       "a plain 'open house' must not land on the fire tab")
    }

    func testClearHouseRequestForgetsItWithoutChangingTab() {
        let router = AppRouter()
        router.openHouse(homeID: "home-a")
        router.selectedTab = .home

        router.clearHouseRequest()

        XCTAssertNil(router.houseRequest)
        XCTAssertEqual(router.selectedTab, .home, "clearing is bookkeeping, not navigation")
    }

    func testTheSameItemTwiceIsTwoRequests() throws {
        let router = AppRouter()
        router.openHouse(homeID: "home-a", focusItemID: "x")
        let first = try XCTUnwrap(router.houseRequest)
        router.openHouse(homeID: "home-a", focusItemID: "x")
        let second = try XCTUnwrap(router.houseRequest)
        XCTAssertNotEqual(first, second, "a repeat tap must still refocus the camera")
    }

    func testGoHomeSetsTheIntentAndTab() {
        let router = AppRouter()
        router.selectedTab = .tasks
        router.go(home: .scan)
        XCTAssertEqual(router.homeIntent, .scan)
        XCTAssertEqual(router.selectedTab, .home)
    }

    // MARK: - Which request the House tab honours

    func testARequestForTheActiveHomeIsHonoured() throws {
        let router = AppRouter()
        router.openHouse(homeID: "home-a", focusItemID: "x")
        let honoured = try XCTUnwrap(HouseRequest.honoured(router.houseRequest, activeHomeID: "home-a"))
        XCTAssertEqual(honoured.focusItemID, "x")
    }

    func testARequestForAnotherHomeIsIgnored() {
        let router = AppRouter()
        router.openHouse(homeID: "home-a")
        XCTAssertNil(HouseRequest.honoured(router.houseRequest, activeHomeID: "home-b"),
                     "switching homes must not leave the House tab on the old one")
    }
}
