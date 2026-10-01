//
//  escape_planUITestsLaunchTests.swift
//  escape_planUITests
//
//  Created by Manogna Bhargav on 7/10/26.
//

import XCTest

final class escape_planUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        installSystemAlertMonitor()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // Without these the "Launch Screen" attachment silently becomes a screenshot of the
        // S8.3 auth gate rather than the app — a changed artifact nobody would think to check.
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-auth.gate.dismissed", "YES",
        ]
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
