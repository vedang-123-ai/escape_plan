// GoldenPathRecordingUITests.swift
// S4.1: drives the full onboarding golden path (seed → review → routes/inspection → done)
// so `xcrun simctl io ... recordVideo` can capture the handoff recording unattended.
//
// Skipped unless GOLDEN_PATH=1 is in the runner environment (pass TEST_RUNNER_GOLDEN_PATH=1
// to xcodebuild) — it needs a live backend, so it must never gate the normal suite.
// Backend + token come from GOLDEN_PATH_BASE_URL / GOLDEN_PATH_TOKEN (defaults match
// backend/README.md's local run).

import XCTest

final class GoldenPathRecordingUITests: XCTestCase {

    override func setUpWithError() throws {
        installSystemAlertMonitor()
    }

    @MainActor
    func testGoldenPathFullLoop() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["GOLDEN_PATH"] == "1" else {
            throw XCTSkip("Recording driver — run with TEST_RUNNER_GOLDEN_PATH=1 and a live backend.")
        }
        let baseURL = env["GOLDEN_PATH_BASE_URL"] ?? "http://localhost:8001"
        let token = env["GOLDEN_PATH_TOKEN"] ?? "dev-local-token"

        let app = XCUIApplication()
        // UserDefaults overrides: force first-launch onboarding and point at the local backend.
        app.launchArguments = [
            "-onboarding.completed", "NO",
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", baseURL,
            "-APIClient.bearerToken", token,
        ]
        app.launch()

        // Step 0 — welcome.
        let start = app.buttons["Get started"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        pause(2)
        start.tap()

        // Step 1 — who lives here.
        XCTAssertTrue(app.staticTexts["Who lives here?"].waitForExistence(timeout: 10))
        let continue1 = app.buttons["Continue"]
        XCTAssertTrue(continue1.waitForExistence(timeout: 10))
        pause(2)
        continue1.tap()

        // Step 2 — per-person needs.
        XCTAssertTrue(app.staticTexts["Does anyone need extra help?"].waitForExistence(timeout: 10))
        let continue2 = app.buttons["Continue"]
        XCTAssertTrue(continue2.waitForExistence(timeout: 10))
        pause(2)
        continue2.tap()

        // Step 3 — rent or own.
        XCTAssertTrue(app.staticTexts["Do you rent or own?"].waitForExistence(timeout: 10))
        let own = app.buttons["Own"]
        if own.waitForExistence(timeout: 5) {
            own.tap()
        }
        let finish = app.buttons["Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        pause(2)
        finish.tap()

        // Landed in the tab shell.
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        pause(2)
    }

    /// Real wall-clock pause so the recording isn't a blur — XCUITest has no visual dwell.
    /// Thread.sleep, not RunLoop.run(until:): the latter returns immediately when the test
    /// runner's loop has no pending sources, which collapsed every dwell to ~0 s.
    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
