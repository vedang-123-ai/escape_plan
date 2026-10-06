// LargestTextUITests.swift — S11.57: defects S53-4 (largest Dynamic Type), S53-5 (labels) and
// S53-2 (the chosen home survives a relaunch), found by the S11.53 simulator walk.
//
// Server-free: the base URL is a closed loopback port and the score comes from the DEBUG-only
// `UITEST_CANNED_SCORE` (cached for every home at launch, shown like any cached score). So the
// score card, the checklist and its filters render with nothing listening.
//
// What a UI test can see is frames, hittability and labels, not whether a word was truncated:
// the words a chip shows at XXXL are pinned by S1157AccessibilityTests.

import XCTest

final class LargestTextUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        installSystemAlertMonitor()
        XCUIDevice.shared.orientation = .portrait
    }

    /// A /score answer with one item per peril, so all three filters appear.
    private static let cannedScore = """
    {"home_id": "x", "home_name": "x", "score": 66,
     "sub_scores": {"fire": 60, "earthquake": 70, "severe_weather": 75},
     "basis": {"fire": "code_quantified", "earthquake": "guidance_based", "severe_weather": "guidance_based"},
     "components": [],
     "checklist": [
       {"id": "alarm.test_monthly", "category": "smoke_alarm", "hazard": "fire",
        "title": "Test every smoke alarm this month", "detail": "Press the test button on every alarm once a month.",
        "done": false, "scoring": true, "source_citation": "usfa-smoke-alarms"},
       {"id": "eq.secure_water_heater", "category": "mitigation", "hazard": "earthquake",
        "title": "Strap the water heater", "detail": "Brace it to the wall studs.", "done": true, "scoring": true},
       {"id": "weather.safe_room", "category": "safe_room", "hazard": "severe_weather",
        "title": "Pick a tornado safe spot", "detail": "Lowest floor, interior room.", "done": false, "scoring": false}
     ]}
    """

    private func launch(largest: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-onboarding.completed", "YES", "-auth.gate.dismissed", "YES",
                    "-APIClient.baseURL", "http://127.0.0.1:9", "-APIClient.bearerToken", "dev-local-token"]
        if largest {
            args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchArguments = args
        app.launchEnvironment["UITEST_CANNED_SCORE"] = Self.cannedScore
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20), "Tab shell did not appear.")
        return app
    }

    private func switcher(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home: '")).firstMatch
    }

    /// Makes `name` the active home through Home's switcher. Skips the test if the simulator's
    /// library no longer has that starter home (another test may have deleted it).
    private func choose(_ name: String, in app: XCUIApplication) throws {
        app.tabBars.buttons["Home"].tap()
        let button = switcher(app)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No home switcher.")
        if button.label.hasPrefix("Home: \(name).") { return }
        button.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        guard row.waitForExistence(timeout: 5) else { throw XCTSkip("\(name) is not in this simulator's library.") }
        row.tap()
        XCTAssertTrue(switcher(app).waitForExistence(timeout: 10))
        let label = switcher(app).label
        XCTAssertTrue(label.hasPrefix("Home: \(name)."), "Switch did not land on \(name): \(label)")
    }

    /// Scrolls until `element` can be tapped (at XXXL most things start below the fold).
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) {
        var left = swipes
        while !element.isHittable && left > 0 { app.swipeUp(); left -= 1 }
    }

    private func assertUsable(_ element: XCUIElement, _ what: String, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(what) is missing.", file: file, line: line)
        scrollToHittable(element, in: app)
        XCTAssertTrue(element.isHittable, "\(what) cannot be tapped.", file: file, line: line)
        let screen = app.windows.firstMatch.frame
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - 0.5, "\(what) runs off the left edge: \(frame)",
                                    file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 0.5, "\(what) runs off the right edge: \(frame)",
                                 file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 43.5, "\(what) is under 44 pt tall: \(frame)", file: file, line: line)
    }

    /// Keeps a screenshot in the result bundle (the S11.57 evidence is exported from it).
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// No control or text on screen may be labelled with an SF Symbol's name ("figure.stand").
    /// Images are left out: XCUITest lists every image under its symbol name even when it is
    /// hidden from VoiceOver (the tab bar's `gearshape.fill`, the score gauge's decorative shield,
    /// found on 2026-10-05), so an image's XCUITest label says nothing about what VoiceOver reads.
    private func assertNoSymbolNameLabels(_ app: XCUIApplication, on screen: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let raw = app.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType != %d AND label MATCHES %@",
                                  XCUIElement.ElementType.image.rawValue, "^[a-z0-9]+(\\.[a-z0-9]+)+$"))
        XCTAssertEqual(raw.count, 0, "\(screen) exposes symbol names: \(raw.allElementsBoundByIndex.map(\.label))",
                       file: file, line: line)
    }

    /// S53-4 at Accessibility XXXL: Home's score card, Tasks' filters, House's floor chips and
    /// dock switch exist, can be tapped, are 44 pt tall and sit inside the screen. The dock's two
    /// segments stack instead of truncating side by side.
    @MainActor
    func testLargestTextKeepsEveryKeyControlUsable() throws {
        let app = launch(largest: true)
        try choose("Two-Story House", in: app)
        XCTAssertTrue(app.buttons["home.scoreCard"].waitForExistence(timeout: 15))
        shot("xxxl-home")
        app.swipeUp()
        shot("xxxl-home-scrolled")
        app.swipeDown()

        assertUsable(app.buttons["home.scoreCard"], "Home score card", in: app)
        XCTAssertTrue(app.buttons["home.scoreCard"].label.hasPrefix("Preparedness score 66 out of 100"),
                      "The score card is not one button with the score in words.")
        assertNoSymbolNameLabels(app, on: "Home")

        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(app.buttons["tasks.filter.all"].waitForExistence(timeout: 15))
        shot("xxxl-tasks")
        for filter in ["all", "fire", "earthquake", "severe_weather"] {
            assertUsable(app.buttons["tasks.filter.\(filter)"], "Tasks filter \(filter)", in: app)
        }
        assertNoSymbolNameLabels(app, on: "Tasks")

        app.tabBars.buttons["House"].tap()
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'house.floorChip.'"))
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 20), "No floor chips on Two-Story House.")
        XCTAssertEqual(chips.count, 2)
        // Offline on purpose, so House shows its "showing your last saved routes" notice over the
        // model; at XXXL it can cover the chips. It is dismissible, which is the way a user clears it.
        sleep(3)
        shot("xxxl-house-offline-notice")
        let dismiss = app.buttons["failure.dismiss"]
        if dismiss.exists && dismiss.isHittable { dismiss.tap() }
        sleep(1)  // let the model settle for the screenshot
        shot("xxxl-house")
        for chip in chips.allElementsBoundByIndex { assertUsable(chip, "Floor chip \(chip.label)", in: app) }

        let routes = app.buttons["house.dock.routes"]
        let fire = app.buttons["house.dock.fire"]
        assertUsable(routes, "Dock: Escape routes", in: app)
        assertUsable(fire, "Dock: Fire simulation", in: app)
        XCTAssertGreaterThanOrEqual(fire.frame.minY, routes.frame.maxY - 1,
                                    "At XXXL the dock segments should stack, not squeeze side by side.")
    }

    /// The default text size keeps the original layout: the dock's segments side by side.
    @MainActor
    func testDefaultTextSizeKeepsTheDockSideBySide() throws {
        let app = launch(largest: false)
        try choose("Two-Story House", in: app)
        XCTAssertTrue(app.buttons["home.scoreCard"].waitForExistence(timeout: 15))
        shot("default-home")
        assertUsable(app.buttons["home.scoreCard"], "Home score card", in: app)
        app.tabBars.buttons["Tasks"].tap()
        XCTAssertTrue(app.buttons["tasks.filter.all"].waitForExistence(timeout: 15))
        shot("default-tasks")
        app.tabBars.buttons["House"].tap()
        let routes = app.buttons["house.dock.routes"]
        let fire = app.buttons["house.dock.fire"]
        XCTAssertTrue(routes.waitForExistence(timeout: 20))
        sleep(3)
        shot("default-house")
        assertUsable(routes, "Dock: Escape routes", in: app)
        assertUsable(fire, "Dock: Fire simulation", in: app)
        XCTAssertEqual(fire.frame.midY, routes.frame.midY, accuracy: 1, "Default size: one row.")
    }

    /// S53-2: the home picked on Home is the home the app reopens on.
    @MainActor
    func testTheChosenHomeSurvivesARelaunch() throws {
        var app = launch(largest: false)
        let before = switcher(app).label
        let target = before.hasPrefix("Home: Bungalow.") ? "Apartment 4B" : "Bungalow"
        try choose(target, in: app)
        app.terminate()

        app = launch(largest: false)
        XCTAssertTrue(switcher(app).waitForExistence(timeout: 10))
        XCTAssertTrue(switcher(app).label.hasPrefix("Home: \(target)."),
                      "Relaunch opened \(switcher(app).label), not \(target).")
        // Leave the simulator on the demo home for the tests that follow.
        try choose("Two-Story House", in: app)
    }
}
