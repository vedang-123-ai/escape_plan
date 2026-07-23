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
            "-APIClient.baseURL", baseURL,
            "-APIClient.bearerToken", token,
        ]
        app.launch()

        // Step 1 — welcome.
        let start = app.buttons["Take the tour"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        pause(2)
        start.tap()

        // Step 2 — review: the seeded copy flags 3 items.
        let confirm = app.buttons["Confirm & Continue"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["3 items need review"].waitForExistence(timeout: 5))
        pause(4)
        confirm.tap()

        // Step 3 — plan: routes render in the embedded PlanScreen; /analyze + /score run in
        // the background panel. Wait for the score chip (backend up → seconds).
        let score = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Preparedness score:'")
        ).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 90))
        // Let the animated routes and the inspection panel breathe on camera.
        pause(12)

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        continueButton.tap()

        // Step 4 — done.
        let finish = app.buttons["Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        pause(3)
        finish.tap()

        // Landed in the tab shell.
        XCTAssertTrue(app.tabBars.buttons["Plan"].waitForExistence(timeout: 10))
        pause(2)
    }

    /// Real wall-clock pause so the recording isn't a blur — XCUITest has no visual dwell.
    /// Thread.sleep, not RunLoop.run(until:): the latter returns immediately when the test
    /// runner's loop has no pending sources, which collapsed every dwell to ~0 s.
    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
