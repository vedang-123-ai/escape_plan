//  SignedOutPathUITests.swift — S11.7: the whole app, with no account.
//
//  The claim on the sign-in screen (`AccountPrivacy.signedOutSummary`) is that everything works
//  signed out. `SignedOutProofTests` pins the part that is pure — no token means no request.
//  This walks the screens, which is the part only a simulator can answer.
//
//  Deliberately BACKEND-FREE. Every assertion below is about a screen appearing, never about a
//  route or a score arriving: `/routes`, `/score`, `/convert`, `/evacuate` and `/chat` need the
//  network whether or not anyone is signed in — they are guarded by the build's shared bearer
//  token, a different axis from the per-user JWT. The base URL is pointed at a port nothing is
//  listening on, so a screen that only renders when a request succeeds fails here rather than
//  passing on a lucky connection.
//
//  Two launch arguments do the work. UserDefaults reads the `NSArgumentDomain` first, so
//  `-auth.gate.dismissed YES` is the supported "skip the gate" path — no test-only branch in
//  the app, and the same mechanism the other seven UI test files already use. The gate tests
//  below pass `-auth.gate.dismissed NO` instead. Omitting the flag is NOT enough: the app writes
//  it to UserDefaults when anyone taps "Continue without an account", and that persists on the
//  simulator, so after the first dismissal in a run the gate would never appear again (AUD-036).

import XCTest

final class SignedOutPathUITests: XCTestCase {

    override func setUpWithError() throws {
        installSystemAlertMonitor()
        continueAfterFailure = false
    }

    /// No token anywhere, and a server address nothing answers on.
    @MainActor
    private func launchSignedOut(showGate: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            // 1 is reserved and nothing binds it, so every backend call fails fast.
            "-APIClient.baseURL", "http://127.0.0.1:1",
            "-APIClient.bearerToken", "not-a-real-token",
            // Forced either way: an argument overrides whatever an earlier test left persisted.
            "-auth.gate.dismissed", showGate ? "NO" : "YES",
        ]
        app.launch()
        return app
    }

    // MARK: - The gate is soft

    /// The one assertion the whole soft-gate decision rests on: a brand-new install can get
    /// into the app without an account, and the way past is a visible control rather than
    /// something to hunt for.
    @MainActor
    func testTheGateCanBeDismissedWithoutAnAccount() throws {
        let app = launchSignedOut(showGate: true)

        let skip = app.buttons["Continue without an account"]
        XCTAssertTrue(skip.waitForExistence(timeout: 20),
                      "no way past the auth gate — the soft gate has become a wall")
        XCTAssertTrue(skip.isHittable, "the way past must not be off-screen or covered")
        skip.tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20),
                      "dismissing the gate did not reach the app")
    }

    /// The disclosure has to be readable before the decision, not after it.
    @MainActor
    func testTheGateSaysWhatAnAccountWouldUpload() throws {
        let app = launchSignedOut(showGate: true)

        let disclose = app.buttons["What does an account upload?"]
        XCTAssertTrue(disclose.waitForExistence(timeout: 20),
                      "the gate asks for an account without saying what it uploads")
        disclose.tap()

        // By identifier, not by visible string: the two lists are `.combine`d for VoiceOver,
        // which replaces their descendant Texts with one element whose label is the whole
        // paragraph. Queried by string these never resolve — caught in review before they had
        // ever run, which is exactly the failure mode an unrun test has.
        XCTAssertTrue(disclosureList(in: app, "privacy.uploads").waitForExistence(timeout: 5))
        XCTAssertTrue(disclosureList(in: app, "privacy.neverUploads").exists)
    }

    // MARK: - Every tab opens

    /// Not a deep walk of each screen — a tab that crashes or hangs signed out is the failure
    /// this catches, and it is the failure that would take the demo down.
    @MainActor
    func testEveryTabOpensSignedOutWithNoBackend() throws {
        let app = launchSignedOut()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))

        // The Linear revamp (2026-09-25) split out Tasks and removed the Beta tab.
        for tab in ["Home", "Tasks", "House", "Assistant", "Settings"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "\(tab) tab is missing")
            button.tap()
            XCTAssertTrue(button.isSelected, "\(tab) tab did not open")
        }
    }

    /// The homes library is local, so it must be populated with no account and no server —
    /// `FixtureSeeder` installs the starter homes at launch for exactly this reason.
    @MainActor
    func testTheHomesLibraryIsPopulatedSignedOut() throws {
        let app = launchSignedOut()
        app.tabBars.buttons["Home"].tap()

        XCTAssertTrue(app.buttons["Menu"].waitForExistence(timeout: 20),
                      "the Home tab did not finish loading without an account")
        XCTAssertGreaterThan(app.cells.count + app.buttons.count, 1,
                             "the library is empty signed out — the starter homes did not seed")
    }

    // MARK: - Settings tells the truth

    @MainActor
    func testSettingsOffersAnAccountRatherThanRequiringOne() throws {
        let app = launchSignedOut()
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.buttons["Sign in or create an account"].waitForExistence(timeout: 20),
                      "signed out, Settings must offer the way IN to an account")
        XCTAssertFalse(app.buttons["Delete account and data"].exists,
                       "there is no account to delete")
    }

    /// Signed out, the disclosure is still there — someone deciding whether to sign up looks
    /// here as often as at the gate.
    @MainActor
    func testSettingsCarriesThePrivacyDisclosureSignedOut() throws {
        let app = launchSignedOut()
        app.tabBars.buttons["Settings"].tap()

        let disclose = app.buttons["What does an account upload?"]
        XCTAssertTrue(disclose.waitForExistence(timeout: 20))
        disclose.tap()
        XCTAssertTrue(disclosureList(in: app, "privacy.neverUploads").waitForExistence(timeout: 5))
    }

    /// The `.combine`d list is exposed under whatever element type SwiftUI picks for a Label plus
    /// Texts — not `.other` — so `app.otherElements[id]` never matched it (AUD-036). Match the
    /// identifier on any type; the identifier is the contract, the type is SwiftUI's business.
    @MainActor
    private func disclosureList(in app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
