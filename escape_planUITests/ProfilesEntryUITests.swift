// ProfilesEntryUITests.swift
// S11.20 (AUD-020): household profiles were unreachable from 87c0610 (BetaScreen deleted) until
// this session. The drill said "Add family members in Profiles first" and no Profiles screen
// could be opened, so a scanned or blank home could never be drilled.
//
// Guards both entry points end to end, on a blank home the test builds itself (a blank home
// has "Room 1", which a new profile takes as its bedroom):
//   1. Home → Household → add a person → back → Run a fire drill → the drill offers that person.
//   2. A blank home's drill empty state → Add family members → add a person → Done → the drill
//      offers that person, without leaving the drill.
//
// Backend-free on purpose: "reaches the drill" is asserted as the drill's person picker (past
// the empty state), not as a /routes result, so the localhost base URL never has to answer.

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

    @MainActor
    private func assertDrillOffers(_ name: String, in app: XCUIApplication) {
        let person = app.buttons["Practice with \(name)"]
        XCTAssertTrue(person.waitForExistence(timeout: 20),
                      "The drill did not offer \(name): it is still at the empty state or never loaded.")
        XCTAssertFalse(app.staticTexts["No family profiles yet"].exists)
    }

    @MainActor
    func testHomeHouseholdRowAddsAPersonTheDrillThenOffers() throws {
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

        let drill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Run a fire drill'")).firstMatch
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        drill.tap()
        assertDrillOffers(name, in: app)
    }

    @MainActor
    func testDrillEmptyStateOpensProfilesAndReloads() throws {
        let app = launchPastOnboarding()
        buildBlankHome(app)

        let drill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Run a fire drill'")).firstMatch
        XCTAssertTrue(drill.waitForExistence(timeout: 20))
        drill.tap()

        let addPeople = app.buttons["drill.addProfiles"]
        XCTAssertTrue(addPeople.waitForExistence(timeout: 20),
                      "A blank home's drill has no way to add people (AUD-020 is back).")
        addPeople.tap()

        let name = "Bo \(Int.random(in: 100...999))"
        addProfile(named: name, in: app)
        app.navigationBars["Household"].buttons["Done"].tap()
        assertDrillOffers(name, in: app)
    }
}
