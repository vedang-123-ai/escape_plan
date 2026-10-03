// HomeDeleteUITests.swift
// S11.21 (AUD-021): homes can be deleted and duplicated from Home's "Your homes" list, and Build
// Manually writes nothing until the first edit.
//
// The simulator's library carries homes from earlier runs, and the list is lazy, so nothing here
// counts rows. Each test reads the TOP row instead: the list is newest first, so a home that was
// just written (a duplicate, or a blank home saved on open) is always the top row.
//
// Signed out, like EntryPointUITests.launchPastOnboarding(); nothing reaches a backend.

import XCTest

final class HomeDeleteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        installSystemAlertMonitor()
        XCUIDevice.shared.orientation = .portrait
    }

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
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20), "Tab shell did not appear.")
        app.tabBars.buttons["Home"].tap()
        return app
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'homes.row.'"))
    }

    /// Home → switcher → "Manage homes…".
    @MainActor
    private func openYourHomes(_ app: XCUIApplication) {
        let switcher = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home: '")).firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "No home switcher on Home.")
        switcher.tap()
        let manage = app.buttons.matching(
            NSPredicate(format: "identifier == 'homes.manage' OR label BEGINSWITH 'Manage homes'")).firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 10), "No Manage homes in the switcher.")
        manage.tap()
        XCTAssertTrue(app.navigationBars["Your homes"].waitForExistence(timeout: 10), "Your homes did not open.")
    }

    @MainActor
    private func closeYourHomes(_ app: XCUIApplication) {
        app.navigationBars["Your homes"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Your homes"].waitForNonExistence(timeout: 10))
    }

    /// The top row's identifier, or "none" for an empty library.
    @MainActor
    private func topRowID(_ app: XCUIApplication) -> String {
        let top = rows(app).firstMatch
        return top.waitForExistence(timeout: 5) ? top.identifier : "none"
    }

    /// Build Manually, one edit, back: a new home the test owns, active and at the top.
    @MainActor
    private func buildHomeWithOneEdit(_ app: XCUIApplication) {
        app.buttons["Menu"].tap()
        let build = app.buttons["Build Manually"].firstMatch
        XCTAssertTrue(build.waitForExistence(timeout: 10))
        build.tap()
        let addMenu = app.buttons["house.addMenu"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 20), "The editor never opened.")
        addMenu.tap()
        let addObject = app.buttons["Add Object"]
        XCTAssertTrue(addObject.waitForExistence(timeout: 10))
        addObject.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    private func swipeAction(_ name: String, on row: XCUIElement, in app: XCUIApplication) {
        row.swipeLeft()
        let action = app.buttons[name].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "No \(name) swipe action.")
        action.tap()
    }

    /// Answers the confirmation and checks it is the signed-out wording: this iPhone only.
    @MainActor
    private func confirmDelete(_ app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Delete asked no confirmation.")
        XCTAssertTrue(alert.label.hasPrefix("Delete "), "The confirmation does not name the home: \(alert.label)")
        XCTAssertTrue(alert.staticTexts["It's removed from this iPhone. You can't undo this."].exists,
                      "Signed out, the confirmation must say this iPhone only.")
        alert.buttons["Delete"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testBuildManuallyThenBackLeavesNoHome() throws {
        let app = launchPastOnboarding()
        openYourHomes(app)
        let before = topRowID(app)
        closeYourHomes(app)

        app.buttons["Menu"].tap()
        let build = app.buttons["Build Manually"].firstMatch
        XCTAssertTrue(build.waitForExistence(timeout: 10))
        build.tap()
        XCTAssertTrue(app.buttons["house.addMenu"].waitForExistence(timeout: 20), "The editor never opened.")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openYourHomes(app)
        XCTAssertEqual(topRowID(app), before, "Backing out of Build Manually left a blank home behind.")
    }

    @MainActor
    func testDuplicateThenDeleteTheCopyFromTheList() throws {
        let app = launchPastOnboarding()
        openYourHomes(app)
        if topRowID(app) == "none" {
            closeYourHomes(app)
            buildHomeWithOneEdit(app)
            openYourHomes(app)
        }
        let original = rows(app).firstMatch
        let originalID = original.identifier
        let originalName = original.label.components(separatedBy: ",").first ?? original.label

        swipeAction("Duplicate", on: original, in: app)
        let copy = rows(app).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        XCTAssertNotEqual(copy.identifier, originalID, "Duplicate did not add a home.")
        XCTAssertTrue(copy.label.hasPrefix("\(originalName) copy"), "Unexpected copy name: \(copy.label)")
        XCTAssertFalse(copy.label.contains("demo home"), "A copy is the user's own home, not a demo.")
        let copyID = copy.identifier

        swipeAction("Delete", on: copy, in: app)
        confirmDelete(app)

        XCTAssertTrue(app.buttons[copyID].waitForNonExistence(timeout: 10), "The deleted copy is still listed.")
        XCTAssertEqual(topRowID(app), originalID)
    }

    @MainActor
    func testDeletingTheActiveHomeMovesHomeToAnother() throws {
        let app = launchPastOnboarding()
        buildHomeWithOneEdit(app)
        openYourHomes(app)
        let active = rows(app).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        XCTAssertTrue(active.label.contains("current home"), "The new home should be active: \(active.label)")
        let activeID = active.identifier

        swipeAction("Delete", on: active, in: app)
        confirmDelete(app)

        XCTAssertTrue(app.buttons[activeID].waitForNonExistence(timeout: 10))
        let next = rows(app).firstMatch
        if next.waitForExistence(timeout: 5) {
            let current = rows(app).matching(NSPredicate(format: "label CONTAINS 'current home'")).firstMatch
            XCTAssertTrue(current.waitForExistence(timeout: 10), "No home became active after the delete.")
            XCTAssertNotEqual(current.identifier, activeID)
        } else {
            closeYourHomes(app)
            XCTAssertTrue(app.staticTexts["Map your home"].waitForExistence(timeout: 10))
        }
    }
}
