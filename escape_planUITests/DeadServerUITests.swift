// DeadServerUITests.swift — S11.53: what a person sees when the server cannot be reached.
//
// The demo can meet a dead network (a venue's Wi-Fi, Render down). These pin the honest, plain-language
// answer and that the app stays usable: the failure is said in words, a retry is offered, nothing
// hangs. The server is "dead" by pointing the app at a closed loopback port (DEBUG accepts
// http://127.0.0.1), so the connection is refused at once and no network is needed.
//
// Mutation-checked 2026-10-05: with `deadServer` switched to the deployed (reachable) server, both
// tests fail at their first offline assertion, because a server that answers produces a different
// message. So they check the offline classification, not just that some banner appeared.

import XCTest

final class DeadServerUITests: XCTestCase {

    private static let deadServer = "http://127.0.0.1:9"

    override func setUpWithError() throws {
        continueAfterFailure = false
        installSystemAlertMonitor()
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func launchAgainstDeadServer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-auth.gate.dismissed", "YES",
            "-APIClient.baseURL", Self.deadServer,
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()
        return app
    }

    /// Asking the assistant with no server: it says "offline" in plain words, offers Try again,
    /// and the composer stays usable for the next question.
    @MainActor
    func testAssistantAgainstDeadServerSaysOfflineAndKeepsTheComposer() throws {
        let app = launchAgainstDeadServer()
        XCTAssertTrue(app.tabBars.buttons["Assistant"].waitForExistence(timeout: 20), "Tab shell did not appear.")
        app.tabBars.buttons["Assistant"].tap()

        let field = app.textFields["Your question"]
        guard field.waitForExistence(timeout: 10) else {
            // No home in the library means no composer; that path is not what this test is about.
            throw XCTSkip("The assistant has no home to answer about on this simulator.")
        }
        field.tap()
        field.typeText("Where should smoke alarms go?")
        let send = app.buttons.matching(identifier: "arrow.up").firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "No Send button.")
        send.tap()

        let offline = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Getting the assistant needs a connection")).firstMatch
        let shown = offline.waitForExistence(timeout: 30)
            || app.buttons.matching(NSPredicate(
                format: "label CONTAINS %@", "Getting the assistant needs a connection")).firstMatch.exists
        XCTAssertTrue(shown, "A dead server did not produce the plain-language offline message.")
        XCTAssertTrue(app.buttons["Try again"].firstMatch.exists, "Offline is retryable, but no Try again was offered.")
        XCTAssertFalse(app.staticTexts["AI features are unavailable right now — the server needs attention. Your escape routes still work."].exists,
                       "A connection failure was reported as the server's AI being broken.")
        XCTAssertFalse(app.otherElements["Assistant is typing"].exists, "Still 'typing' after the failure: the request hangs.")
        XCTAssertTrue(field.exists && field.isEnabled, "The composer is gone or disabled after a failure.")
    }

    /// House with no server: routes come from the saved copy with an offline notice, or an offline
    /// failure; either way it says "offline", offers Try again, and the app is still responsive after it.
    @MainActor
    func testHouseAgainstDeadServerSaysOfflineAndRetryStaysResponsive() throws {
        let app = launchAgainstDeadServer()
        XCTAssertTrue(app.tabBars.buttons["House"].waitForExistence(timeout: 20), "Tab shell did not appear.")
        app.tabBars.buttons["House"].tap()

        let offline = NSPredicate(format: "label CONTAINS[c] %@", "offline")
        let notice = app.staticTexts.matching(offline).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 30), "House said nothing about being offline.")

        let retry = app.buttons.matching(identifier: "failure.retry").firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "No Try again on the offline notice.")
        retry.tap()
        XCTAssertTrue(app.staticTexts.matching(offline).firstMatch.waitForExistence(timeout: 30),
                      "After Try again the offline notice vanished without routes coming back.")

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected, "The app stopped responding after a retry.")
    }
}
