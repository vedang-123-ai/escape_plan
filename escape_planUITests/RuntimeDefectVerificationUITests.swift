//  RuntimeDefectVerificationUITests.swift
//  escape_planUITests
//
//  Runtime verification and screenshot evidence collector for audit findings:
//  - A02-01: Nested NavigationStack hierarchy in HouseScreen when pushed from HomeScreen
//  - A02-02: Navigation return affordance on "Build Manually" pushed HouseScreen
//  - A03-02: Tab bar occlusion on bottom content across tabs
//

import XCTest

final class RuntimeDefectVerificationUITests: XCTestCase {

    private static let shotsDir = URL(fileURLWithPath: "/tmp/ep-fix-qa-shots", isDirectory: true)

    override func setUpWithError() throws {
        installSystemAlertMonitor()
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        try? FileManager.default.createDirectory(at: Self.shotsDir, withIntermediateDirectories: true)
    }

    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let url = Self.shotsDir.appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", "http://127.0.0.1:9",
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20), "Tab shell did not appear.")
        return app
    }

    // MARK: - A02-01 / A02-02: Nested NavigationStack and Back Affordance

    @MainActor
    func testVerifyBuildManuallyNavigationStackAndBackAffordance() throws {
        let app = launchApp()
        app.tabBars.buttons["Home"].tap()

        let menuButton = app.buttons["Menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10), "Menu button missing on Home.")
        menuButton.tap()

        let buildManually = app.buttons["Build Manually"].firstMatch
        XCTAssertTrue(buildManually.waitForExistence(timeout: 10), "Build Manually option missing in Menu.")
        buildManually.tap()

        // Wait for HouseScreen editor scene to appear
        let scene = app.otherElements["editor.scene"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "HouseScreen 3D surface never appeared.")

        sleep(2)
        shoot("a02-01-02-build-manually-pushed")

        // Inspect navigation bars in the accessibility tree
        let navBars = app.navigationBars
        print("[A02 Verification] navBars count = \(navBars.count)")
        for i in 0..<navBars.count {
            let bar = navBars.element(boundBy: i)
            print("[A02 Verification] navBar[\(i)] label='\(bar.label)' identifier='\(bar.identifier)' buttons=\(bar.buttons.allElementsBoundByIndex.map(\.label))")
        }

        // Check back button affordance
        let backButton = navBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'back' OR label CONTAINS[c] 'home'")).firstMatch
        let anyNavButton0 = navBars.buttons.element(boundBy: 0)

        print("[A02 Verification] backButton.exists = \(backButton.exists), anyNavButton0.exists = \(anyNavButton0.exists) label='\(anyNavButton0.label)'")

        if anyNavButton0.exists {
            anyNavButton0.tap()
            sleep(2)
            shoot("a02-02-after-nav-button-tap")
            let backOnHome = app.tabBars.buttons["Home"].isSelected
            print("[A02 Verification] Returned to Home tab after tapping navButton0? \(backOnHome)")
        }
    }

    // MARK: - A03-02: Tab Bar Occlusion Verification

    @MainActor
    func testVerifyTabBarOcclusionAcrossTabs() throws {
        let app = launchApp()

        // 1. Home tab bottom scroll
        app.tabBars.buttons["Home"].tap()
        sleep(2)
        // Scroll multiple times to reach the very bottom
        for _ in 1...4 {
            app.swipeUp()
            sleep(1)
        }
        shoot("a03-02-home-bottom-scroll")

        let tabBar = app.tabBars.firstMatch
        let tabBarFrame = tabBar.frame
        print("[A03-02 Verification] tabBar frame: \(tabBarFrame)")

        // 2. Tasks tab bottom scroll
        app.tabBars.buttons["Tasks"].tap()
        sleep(2)
        for _ in 1...5 {
            app.swipeUp()
            sleep(1)
        }
        shoot("a03-02-tasks-bottom-scroll")

        // 3. Settings tab bottom scroll
        app.tabBars.buttons["Settings"].tap()
        sleep(2)
        for _ in 1...4 {
            app.swipeUp()
            sleep(1)
        }
        shoot("a03-02-settings-bottom-scroll")

        // 4. House tab
        app.tabBars.buttons["House"].tap()
        sleep(3)
        shoot("a03-02-house-dock")
    }
}
