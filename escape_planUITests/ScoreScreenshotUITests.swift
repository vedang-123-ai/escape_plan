// ScoreScreenshotUITests.swift
// Captures the Score screen on its own, because S44ScreenshotUITests reaches it through a
// swipe-right action on a List cell and that swipe is flaky — it produced 11-score.png on one
// run and silently skipped the step on the next (the step is best-effort by design, so a
// missed swipe looks identical to a passing run).
//
// Worth having separately: Score was completely broken from 2026-07-27 to 2026-08-02 (an
// unmapped `egress` checklist category failed the whole ScoreBreakdown decode), and the
// evidence that it works is a picture of it working.
//
// Skipped unless SCORE_SHOT=1 (pass TEST_RUNNER_SCORE_SHOT=1) — needs a live local backend.

import XCTest

final class ScoreScreenshotUITests: XCTestCase {

    func testCaptureScoreScreen() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SCORE_SHOT"] == "1" else {
            throw XCTSkip("Screenshot driver — run with TEST_RUNNER_SCORE_SHOT=1.")
        }
        guard let out = env["SCORE_SHOT_OUT"] else { throw XCTSkip("SCORE_SHOT_OUT not set") }
        let outDir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-APIClient.baseURL", env["SCORE_SHOT_BASE_URL"] ?? "http://localhost:8000",
            "-APIClient.bearerToken", env["SCORE_SHOT_TOKEN"] ?? "dev-local-token",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Two-Story House"].waitForExistence(timeout: 20),
                      "seeded homes never appeared")

        // HomeScreen exposes Score two ways: a leading swipe action and a context menu.
        // Prefer the long-press — a swipe that lands mid-layout silently does nothing, which
        // is what made S44's step skip intermittently, whereas a context menu either opens
        // or doesn't. Swipe stays as the fallback.
        let cell = app.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 15), "no home cells on the Home tab")

        var opened = false
        for _ in 1...3 {
            cell.press(forDuration: 1.2)
            let menuItem = app.buttons["Preparedness Score"].firstMatch
            if menuItem.waitForExistence(timeout: 5) {
                menuItem.tap()
                opened = true
                break
            }
        }
        if !opened {
            cell.swipeRight()
            let score = app.buttons["Score"].firstMatch
            if score.waitForExistence(timeout: 5) {
                score.tap()
                opened = true
            }
        }
        XCTAssertTrue(opened, "couldn't open Score via context menu or swipe")

        // /score is a round trip plus a render; give it room.
        XCTAssertTrue(app.navigationBars["Score"].waitForExistence(timeout: 20),
                      "Score screen never appeared")
        sleep(8)

        let shot = XCUIScreen.main.screenshot()
        try shot.pngRepresentation.write(to: outDir.appendingPathComponent("score.png"))

        // The regression this guards: a decode failure renders this exact string. Asserting
        // it is absent means the screenshot can't quietly be a picture of the bug.
        XCTAssertFalse(app.staticTexts["Couldn't get your score"].exists,
                       "Score screen is showing the decode-failure state")
    }
}
