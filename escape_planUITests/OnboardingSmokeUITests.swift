//  OnboardingSmokeUITests.swift
//  escape_planUITests
//
//  Non-gated UI smoke tests for first launch onboarding and relaunch persistence.
//  Exercises both the "I'll do this later" exit and the "Get started" interview path,
//  and verifies persistence of completion across app relaunch.
//

import XCTest

final class OnboardingSmokeUITests: XCTestCase {

    private static let shotsDir = URL(fileURLWithPath: "/tmp/ep-fix-qa-shots", isDirectory: true)

    override func setUpWithError() throws {
        installSystemAlertMonitor()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try? FileManager.default.createDirectory(at: Self.shotsDir, withIntermediateDirectories: true)
    }

    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let url = Self.shotsDir.appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }

    /// First launch -> "I'll do this later" -> Main screen (Home tab) visible.
    @MainActor
    func testFirstLaunchLaterPathLeavesOnboardingAndShowsMainScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "NO",
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", "http://127.0.0.1:9",
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()

        // Welcome screen assertions
        let welcomeTitle = app.staticTexts["Let's map your home"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 15), "Welcome screen title did not appear.")
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "Get started button missing.")
        let later = app.buttons["I'll do this later"]
        XCTAssertTrue(later.waitForExistence(timeout: 5), "I'll do this later button missing.")

        shoot("01-welcome-screen")

        later.tap()

        // Main screen assertions
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "Home tab did not appear after dismissing onboarding.")
        XCTAssertTrue(homeTab.isSelected, "Home tab is not active.")

        // Verify standard tabs are present
        for tab in ["Home", "Tasks", "House", "Assistant", "Settings"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "\(tab) tab missing from tab bar.")
        }

        shoot("02-home-after-later")
    }

    /// First launch -> "Get started" -> walk through the household interview -> Finish -> Main screen.
    @MainActor
    func testFirstLaunchGetStartedThroughInterviewPath() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "NO",
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", "http://127.0.0.1:9",
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()

        // Step 0: Welcome
        let getStarted = app.buttons["Get started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 15), "Welcome screen did not appear.")
        getStarted.tap()

        // Step 1: Who lives here
        let whoLivesHereTitle = app.staticTexts["Who lives here?"]
        XCTAssertTrue(whoLivesHereTitle.waitForExistence(timeout: 10), "Step 1 'Who lives here?' did not appear.")
        shoot("03-onboarding-wholiveshere")

        let continue1 = app.buttons["Continue"]
        XCTAssertTrue(continue1.waitForExistence(timeout: 5), "Continue button on step 1 missing.")
        continue1.tap()

        // Step 2: Per-person needs
        let needsTitle = app.staticTexts["Does anyone need extra help?"]
        XCTAssertTrue(needsTitle.waitForExistence(timeout: 10), "Step 2 'Does anyone need extra help?' did not appear.")
        shoot("04-onboarding-needs")

        let continue2 = app.buttons["Continue"]
        XCTAssertTrue(continue2.waitForExistence(timeout: 5), "Continue button on step 2 missing.")
        continue2.tap()

        // Step 3: Rent or own
        let rentOrOwnTitle = app.staticTexts["Do you rent or own?"]
        XCTAssertTrue(rentOrOwnTitle.waitForExistence(timeout: 10), "Step 3 'Do you rent or own?' did not appear.")
        shoot("05-onboarding-rentorown")

        let ownButton = app.buttons["Own"]
        if ownButton.waitForExistence(timeout: 5) {
            ownButton.tap()
        }

        let finishButton = app.buttons["Finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 5), "Finish button on step 3 missing.")
        finishButton.tap()

        // Verify arrival on main screen
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10), "Main screen Home tab did not appear after finishing onboarding.")
        XCTAssertTrue(homeTab.isSelected, "Home tab should be selected.")

        shoot("06-home-after-interview")
    }

    /// Relaunch persistence check: once onboarding is completed/dismissed, relaunching the app
    /// without the override does NOT present onboarding again.
    @MainActor
    func testOnboardingDismissalPersistsAcrossRelaunch() throws {
        var app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "NO",
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", "http://127.0.0.1:9",
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()

        let later = app.buttons["I'll do this later"]
        XCTAssertTrue(later.waitForExistence(timeout: 15))
        later.tap()

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))

        // Terminate app
        app.terminate()

        // Relaunch without forcing onboarding.completed to NO
        app = XCUIApplication()
        app.launchArguments = [
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", "http://127.0.0.1:9",
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()

        // The welcome screen should NOT appear
        XCTAssertFalse(app.staticTexts["Let's map your home"].exists,
                       "Onboarding welcome screen reappeared on relaunch after being dismissed.")

        // The main Home tab should be directly visible
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10),
                      "Home tab should be directly visible on relaunch.")
        shoot("07-relaunch-home")
    }
}
