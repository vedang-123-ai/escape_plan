// FireDrillUITests.swift
// Trim 2 (2026-10-03): "Run a fire drill" on Home opens the House tab on its fire simulation
// (the old practice drill screen was deleted). Guards that entry end to end:
// Home → Run a fire drill → House, dock on "Fire simulation", the fire controls showing, and the
// room list that starts a fire opens.
//
// Backend-free on purpose: everything asserted renders before any /evacuate call, so the
// localhost base URL never has to answer. Starting a fire and the playback controls need the
// server and are covered by the simulator walk in the trim-2 note.

import XCTest

final class FireDrillUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        installSystemAlertMonitor()
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testRunAFireDrillOpensHouseOnTheFireSimulation() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", "http://localhost:8000",
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()

        // A fresh blank home (one committed edit, so it is saved) makes Home show its drill card
        // whatever the simulator's library held before.
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20), "Tab shell did not appear.")
        app.tabBars.buttons["Home"].tap()
        let menu = app.buttons["Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let build = app.buttons["Build Manually"].firstMatch
        XCTAssertTrue(build.waitForExistence(timeout: 10))
        build.tap()
        let addMenu = app.buttons["house.addMenu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 20), "The editor never opened.")
        addMenu.tap()
        let addObject = app.buttons["Add Object"]
        XCTAssertTrue(addObject.waitForExistence(timeout: 10))
        addObject.tap()
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()

        let drill = app.buttons["home.fireDrill"]
        XCTAssertTrue(drill.waitForExistence(timeout: 20), "No Run a fire drill card on Home.")
        drill.tap()

        XCTAssertTrue(app.tabBars.buttons["House"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["House"].isSelected, "Run a fire drill did not switch to House.")
        let fireTab = app.buttons["house.dock.fire"]
        XCTAssertTrue(fireTab.waitForExistence(timeout: 20), "House has no fire simulation tab.")
        XCTAssertTrue(fireTab.isSelected, "House opened on Escape routes, not the fire simulation.")
        XCTAssertFalse(app.buttons["house.dock.routes"].isSelected)
        XCTAssertTrue(app.buttons["house.simulation.ignite"].exists, "No ignite button in the fire dock.")

        let choose = app.buttons["house.simulation.choose"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10), "No room list to start a fire from.")
        choose.tap()
        XCTAssertTrue(app.navigationBars["Start the fire in…"].waitForExistence(timeout: 10),
                      "The room list did not open.")
        XCTAssertTrue(app.buttons["Start the fire in Room 1"].exists, "The blank home's room is not listed.")
    }
}
