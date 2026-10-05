// SimulatorWalkUITests.swift — S11.53 simulator walk of the demo golden path.
//
// The walk driver (`testWalk*`) is skipped unless WALK_OUT is set (pass TEST_RUNNER_WALK_OUT=<dir>
// to xcodebuild). It writes a screenshot and the accessibility tree of every step to that host
// directory, so the walk is reproducible evidence, not a description. It never gates the suite.

import XCTest

final class SimulatorWalkUITests: XCTestCase {

    private var outDir: URL?
    private var step = 0

    override func setUpWithError() throws {
        installSystemAlertMonitor()
        XCUIDevice.shared.orientation = .portrait
        if let out = ProcessInfo.processInfo.environment["WALK_OUT"] {
            outDir = URL(fileURLWithPath: out, isDirectory: true)
            try FileManager.default.createDirectory(at: outDir!, withIntermediateDirectories: true)
        }
    }

    // MARK: - Walk driver helpers

    private func requireWalk() throws {
        guard outDir != nil else { throw XCTSkip("Walk driver — run with TEST_RUNNER_WALK_OUT=<dir>.") }
        continueAfterFailure = true
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        guard let outDir else { return }
        step += 1
        let stem = String(format: "%@-%02d-%@", self.name.components(separatedBy: " ").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? "walk", step, name)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: outDir.appendingPathComponent("\(stem).png"))
        try? app.debugDescription.write(to: outDir.appendingPathComponent("\(stem).txt"),
                                        atomically: true, encoding: .utf8)
    }

    private func launchApp(baseURL: String, onboarded: Bool = true,
                           extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-auth.gate.dismissed", "YES", "-APIClient.baseURL", baseURL]
        if onboarded { args += ["-onboarding.completed", "YES"] }
        app.launchArguments = args + extra
        app.launch()
        return app
    }

    private static let deployed = "https://escape-plan-backend.onrender.com"

    // MARK: - Walk

    @MainActor
    func testWalk01FirstLaunch() throws {
        try requireWalk()
        let app = launchApp(baseURL: Self.deployed, onboarded: false)
        sleep(4)
        capture(app, "first-launch")
    }

    @MainActor
    func testWalk02Tabs() throws {
        try requireWalk()
        let app = launchApp(baseURL: Self.deployed)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        sleep(6)
        capture(app, "home")
        for tab in ["Tasks", "House", "Assistant", "Settings"] {
            app.tabBars.buttons[tab].tap()
            sleep(tab == "House" ? 12 : 3)
            capture(app, tab.lowercased())
        }
    }

    /// Waits until no static text contains `text`. Returns the seconds it took, or nil on timeout.
    @discardableResult
    private func waitGone(_ app: XCUIApplication, _ text: String, timeout: TimeInterval) -> Double? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if !app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists {
                let t = Date().timeIntervalSince(start)
                print("WALK: '\(text)' gone after \(String(format: "%.1f", t)) s")
                return t
            }
            usleep(500_000)
        }
        print("WALK: '\(text)' STILL SHOWN after \(timeout) s")
        return nil
    }

    private func switchHome(_ app: XCUIApplication, to name: String) {
        app.tabBars.buttons["Home"].tap()
        let switcher = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home: '")).firstMatch
        guard switcher.waitForExistence(timeout: 10) else { print("WALK: no switcher"); return }
        switcher.tap()
        sleep(2)
        capture(app, "switcher")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        if row.waitForExistence(timeout: 5) { row.tap() } else { print("WALK: no row \(name)") }
        sleep(2)
    }

    @MainActor
    func testWalk03HomeAndScore() throws {
        try requireWalk()
        let app = launchApp(baseURL: Self.deployed)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        waitGone(app, "Scoring", timeout: 90)
        capture(app, "jagged-scored")
        switchHome(app, to: "Two-Story House")
        waitGone(app, "Scoring", timeout: 90)
        capture(app, "twostory-home")
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Preparedness score'")).firstMatch
        if card.waitForExistence(timeout: 5) {
            card.tap(); sleep(3)
            capture(app, "score-breakdown")
            app.swipeUp(); sleep(1)
            capture(app, "score-breakdown-2")
            app.swipeUp(); sleep(1)
            capture(app, "score-breakdown-3")
        } else { print("WALK: no score card") }
    }

    @MainActor
    func testWalk04Tasks() throws {
        try requireWalk()
        let app = launchApp(baseURL: Self.deployed)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Tasks"].tap()
        waitGone(app, "Loading your tasks", timeout: 90)
        capture(app, "tasks")
        // Tick the first tickable task and capture the result.
        let tick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mark ' AND label ENDSWITH ' as done'")).firstMatch
        if tick.waitForExistence(timeout: 5) {
            print("WALK: ticking '\(tick.label)'")
            tick.tap(); sleep(3)
            capture(app, "tasks-ticked")
        } else { print("WALK: nothing tickable") }
        for pill in ["Fire", "Earthquake", "Severe weather", "Tornado"] {
            let b = app.buttons[pill].firstMatch
            if b.exists { b.tap(); sleep(2); capture(app, "filter-\(pill)") } else { print("WALK: no pill \(pill)") }
        }
        app.swipeUp(); sleep(1); capture(app, "tasks-scrolled")
        app.swipeUp(); sleep(1); capture(app, "tasks-scrolled-2")
    }

    @MainActor
    func testWalk05House() throws {
        try requireWalk()
        let app = launchApp(baseURL: Self.deployed)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        switchHome(app, to: "Two-Story House")
        app.tabBars.buttons["House"].tap()
        sleep(10)
        capture(app, "house-routes")
        app.swipeUp(); sleep(1); capture(app, "house-routes-scrolled")
        app.swipeDown(); sleep(1)
        let more = app.buttons["house.moreMenu"]
        if more.exists { more.tap(); sleep(2); capture(app, "house-more-menu"); app.tap() ; sleep(1) }
        let fire = app.buttons["house.dock.fire"]
        if fire.waitForExistence(timeout: 5) {
            fire.tap(); sleep(2); capture(app, "fire-dock")
            let choose = app.buttons["house.simulation.choose"]
            if choose.waitForExistence(timeout: 5) {
                choose.tap(); sleep(2); capture(app, "fire-room-list")
                let room = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start the fire in'")).element(boundBy: 1)
                if room.exists { print("WALK: \(room.label)"); room.tap() }
                sleep(15); capture(app, "fire-running")
                sleep(10); capture(app, "fire-later")
            }
        } else { print("WALK: no fire dock") }
    }

    @MainActor
    func testWalk06AssistantLive() throws {
        try requireWalk()
        let app = launchApp(baseURL: Self.deployed)
        XCTAssertTrue(app.tabBars.buttons["Assistant"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Assistant"].tap()
        let chip = app.buttons["Where should smoke alarms go?"]
        if chip.waitForExistence(timeout: 5) { chip.tap() }
        let start = Date()
        sleep(5); capture(app, "assistant-5s")
        let banner = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'unavailable' OR label CONTAINS[c] 'server' OR label CONTAINS[c] 'offline'")).firstMatch
        _ = banner.waitForExistence(timeout: 90)
        print("WALK: assistant outcome after \(Date().timeIntervalSince(start)) s: \(banner.exists ? banner.label : "none")")
        capture(app, "assistant-outcome")
    }

    /// Dead server: connection refused on the loopback (DEBUG accepts http://127.0.0.1).
    @MainActor
    func testWalk07Offline() throws {
        try requireWalk()
        let app = launchApp(baseURL: "http://127.0.0.1:9")
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        sleep(8); capture(app, "offline-home")
        app.tabBars.buttons["Tasks"].tap(); sleep(3); capture(app, "offline-tasks")
        app.tabBars.buttons["House"].tap(); sleep(8); capture(app, "offline-house")
        let retry = app.buttons["failure.retry"].firstMatch
        if retry.exists { retry.tap(); sleep(5); capture(app, "offline-house-retried") }
        app.tabBars.buttons["Assistant"].tap()
        let chip = app.buttons["Where should smoke alarms go?"]
        if chip.waitForExistence(timeout: 5) { chip.tap() }
        sleep(8); capture(app, "offline-assistant")
        app.tabBars.buttons["Settings"].tap(); sleep(1)
        let test = app.buttons["Test connection"]
        if test.waitForExistence(timeout: 5) { test.tap(); sleep(5); capture(app, "offline-settings-test") }
        app.tabBars.buttons["Home"].tap(); sleep(1)
        let homeRetry = app.buttons["failure.retry"].firstMatch
        if homeRetry.exists { homeRetry.tap(); sleep(5); capture(app, "offline-home-retried") }
    }

    @MainActor
    func testWalk08DynamicTypeLargest() throws {
        try requireWalk()
        let app = launchApp(baseURL: Self.deployed, extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        waitGone(app, "Scoring", timeout: 60)
        capture(app, "a11y-home")
        app.swipeUp(); sleep(1); capture(app, "a11y-home-scrolled")
        for tab in ["Tasks", "House", "Assistant", "Settings"] {
            app.tabBars.buttons[tab].tap()
            sleep(tab == "House" ? 10 : 3)
            capture(app, "a11y-\(tab.lowercased())")
        }
    }

    @MainActor
    func testWalk10ScoreDoneOfflineChatAndActiveHome() throws {
        try requireWalk()
        var app = launchApp(baseURL: Self.deployed)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        print("WALK: active home at launch: \(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home: '")).firstMatch.label)")
        switchHome(app, to: "Two-Story House")
        waitGone(app, "Scoring", timeout: 90)
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Preparedness,'")).firstMatch
        if card.waitForExistence(timeout: 10) {
            card.tap(); sleep(3)
            capture(app, "score-breakdown")
            app.swipeUp(); sleep(1); capture(app, "score-breakdown-2")
            app.swipeUp(); sleep(1); capture(app, "score-breakdown-3")
        } else { print("WALK: no score card button") }
        // Relaunch: is Two-Story still the active home?
        app.terminate()
        app = launchApp(baseURL: Self.deployed)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        sleep(2)
        print("WALK: active home after relaunch: \(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home: '")).firstMatch.label)")
        capture(app, "after-relaunch")
        // Tasks: open the Done group and read the recurring item.
        app.tabBars.buttons["Tasks"].tap()
        waitGone(app, "Loading your tasks", timeout: 90)
        let done = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Done, '")).firstMatch
        if done.waitForExistence(timeout: 5) {
            print("WALK: done group: \(done.label)")
            done.tap(); sleep(2)
            for _ in 0..<4 { app.swipeUp() }
            sleep(1); capture(app, "tasks-done-open")
        }
        app.terminate()
    }

    @MainActor
    func testWalk11OfflineChat() throws {
        try requireWalk()
        // Offline assistant, typed (a stored conversation hides the suggestion chips).
        let app = launchApp(baseURL: "http://127.0.0.1:9")
        XCTAssertTrue(app.tabBars.buttons["Assistant"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Assistant"].tap()
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap(); field.typeText("Where should smoke alarms go?")
            let send = app.buttons.matching(identifier: "arrow.up").firstMatch
            if send.exists { send.tap() } else { print("WALK: no send button") }
            let start = Date()
            sleep(3); capture(app, "offline-chat-3s")
            let msg = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'server' OR label CONTAINS[c] 'offline'")).firstMatch
            _ = msg.waitForExistence(timeout: 60)
            print("WALK: offline chat after \(Date().timeIntervalSince(start)) s: \(msg.exists ? msg.label : "none")")
            capture(app, "offline-chat-outcome")
        } else { print("WALK: no chat field") }
    }

    @MainActor
    func testWalk09Settings() throws {
        try requireWalk()
        let app = launchApp(baseURL: Self.deployed)
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Settings"].tap(); sleep(1)
        let test = app.buttons["Test connection"]
        if test.waitForExistence(timeout: 5) { test.tap(); sleep(8) }
        capture(app, "settings-tested")
        app.swipeUp(); sleep(1); capture(app, "settings-2")
        app.swipeUp(); sleep(1); capture(app, "settings-3")
        let link = app.buttons["What leaves this iPhone?"].firstMatch
        app.swipeDown(); app.swipeDown(); sleep(1)
        if link.exists { link.tap(); sleep(2); capture(app, "settings-privacy") }
    }
}
