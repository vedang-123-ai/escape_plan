// ProfilesEntryUITests.swift
// S11.20 (AUD-020): household profiles were unreachable from 87c0610 (BetaScreen deleted) until
// that session. The old drill said "Add family members in Profiles first" and no Profiles screen
// could be opened, so a scanned or blank home could never be drilled.
//
// Since trim 2 (2026-10-03) "Run a fire drill" opens House on its fire simulation, and the
// simulation runs with or without people (the engine puts one stand-in per room when nobody is
// added). What AUD-020 still needs is that a family can be added and the drill knows it:
//   1. Home → Household → add a person → back → Run a fire drill → House's fire dock, with no
//      "no one is added" note.
//   2. A blank home's fire drill says where to add people; after adding one from Home's
//      Household row, the note is gone.
//
// Backend-free on purpose: the fire dock's controls and note render before any /evacuate call,
// so the localhost base URL never has to answer.

import XCTest

final class ProfilesEntryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        installSystemAlertMonitor()
        XCUIDevice.shared.orientation = .portrait
    }

    /// Same launch as `EntryPointUITests.launchPastOnboarding()`: signed out, onboarding skipped.
    @MainActor
    private func launchPastOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", "http://localhost:8000",
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()
        return app
    }

    /// Builds a fresh blank home from Home's "+" menu and comes back to Home with it active.
    ///
    /// Makes one committed edit first: since S11.21 a blank home is not written until its first
    /// edit, so backing straight out would leave no new home to add people to.
    @MainActor
    private func buildBlankHome(_ app: XCUIApplication) {
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
        XCTAssertTrue(addObject.waitForExistence(timeout: 10), "Add Object missing from the menu")
        addObject.tap()
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
    }

    /// Adds one profile named `name` from an open Household (Profiles) screen.
    @MainActor
    private func addProfile(named name: String, in app: XCUIApplication) {
        let add = app.buttons["Add Profile"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Profiles opened without its Add button.")
        add.tap()
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The new-profile form did not open.")
        field.tap()
        field.typeText(name)
        app.navigationBars["New Profile"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10)
                        || app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
                            .waitForExistence(timeout: 2),
                      "The new profile is not listed after Save.")
    }

    /// The House tab is showing, its dock on "Fire simulation", and the room picker is there.
    @MainActor
    private func assertFireDrillOpen(in app: XCUIApplication) {
        let fireTab = app.buttons["house.dock.fire"]
        XCTAssertTrue(fireTab.waitForExistence(timeout: 20), "Run a fire drill did not open House.")
        XCTAssertTrue(fireTab.isSelected, "House opened, but not on the fire simulation.")
        XCTAssertTrue(app.buttons["house.simulation.choose"].waitForExistence(timeout: 10),
                      "The fire dock has no way to start a fire.")
    }

    @MainActor
    private func tapRunAFireDrill(in app: XCUIApplication) {
        app.tabBars.buttons["Home"].tap()
        let drill = app.buttons["home.fireDrill"]
        XCTAssertTrue(drill.waitForExistence(timeout: 20), "No Run a fire drill card on Home.")
        drill.tap()
    }

    @MainActor
    func testHouseholdPersonReachesTheFireDrill() throws {
        let app = launchPastOnboarding()
        buildBlankHome(app)

        let household = app.buttons["household.row"]
        XCTAssertTrue(household.waitForExistence(timeout: 20), "No Household row on Home (AUD-020 is back).")
        household.tap()

        let name = "Ada \(Int.random(in: 100...999))"
        addProfile(named: name, in: app)
        app.navigationBars["Household"].buttons.element(boundBy: 0).tap()

        // Home's row reads ReadinessStore, so this proves the reload on leaving Household.
        let updatedRow = app.buttons.matching(
            NSPredicate(format: "identifier == 'household.row' AND label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(updatedRow.waitForExistence(timeout: 10),
                      "Home still shows the old household: ReadinessStore did not reload.")

        tapRunAFireDrill(in: app)
        assertFireDrillOpen(in: app)
        XCTAssertFalse(app.staticTexts["house.simulation.noPeople"].exists,
                       "The drill still says no one is added after adding \(name).")
    }

    @MainActor
    func testFireDrillSaysWhereToAddPeople() throws {
        let app = launchPastOnboarding()
        buildBlankHome(app)

        tapRunAFireDrill(in: app)
        assertFireDrillOpen(in: app)
        XCTAssertTrue(app.staticTexts["house.simulation.noPeople"].waitForExistence(timeout: 10),
                      "A blank home's fire drill does not say where to add people (AUD-020 is back).")

        app.tabBars.buttons["Home"].tap()
        let household = app.buttons["household.row"]
        XCTAssertTrue(household.waitForExistence(timeout: 20))
        household.tap()
        let name = "Bo \(Int.random(in: 100...999))"
        addProfile(named: name, in: app)
        app.navigationBars["Household"].buttons.element(boundBy: 0).tap()

        tapRunAFireDrill(in: app)
        assertFireDrillOpen(in: app)
        XCTAssertFalse(app.staticTexts["house.simulation.noPeople"].waitForExistence(timeout: 3),
                       "The note stayed after \(name) was added: House did not reload the home.")
    }
}
