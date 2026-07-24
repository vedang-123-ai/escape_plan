// S44ScreenshotUITests.swift
// S4.4 polish pass: walks every screen and writes PNG screenshots to the host directory in
// S44_OUT, so the before/after acceptance evidence is reproducible unattended.
//
// Skipped unless S44_SHOTS=1 (pass TEST_RUNNER_S44_SHOTS=1 to xcodebuild) — it wants a live
// local backend and pre-seeded homes, so it must never gate the normal suite. Steps are
// best-effort: a screen that can't be reached logs and is skipped rather than failing the run.

import XCTest

final class S44ScreenshotUITests: XCTestCase {

    private var outDir: URL!

    private func makeApp(onboarding: Bool) -> XCUIApplication {
        // Other tests (launch tests) rotate the simulator and the orientation sticks
        // between runs — a landscape "after" can't pair with a portrait "before".
        XCUIDevice.shared.orientation = .portrait
        let env = ProcessInfo.processInfo.environment
        let baseURL = env["S44_BASE_URL"] ?? "http://localhost:8000"
        let token = env["S44_TOKEN"] ?? "dev-local-token"
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", onboarding ? "NO" : "YES",
            "-APIClient.baseURL", baseURL,
            "-APIClient.bearerToken", token,
        ]
        return app
    }

    private func shoot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let url = outDir.appendingPathComponent("\(name).png")
        do {
            try png.write(to: url)
        } catch {
            XCTFail("couldn't write \(name).png: \(error)")
        }
    }

    /// Best-effort step: failures are logged, not fatal — a broken sub-screen must not cost
    /// the remaining screenshots.
    @discardableResult
    private func attempt(_ label: String, _ body: () throws -> Bool) -> Bool {
        do {
            let ok = try body()
            if !ok { print("S44: SKIPPED \(label)") }
            return ok
        } catch {
            print("S44: FAILED \(label): \(error)")
            return false
        }
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["S44_SHOTS"] == "1" else {
            throw XCTSkip("Screenshot driver — run with TEST_RUNNER_S44_SHOTS=1.")
        }
        guard let out = env["S44_OUT"] else { throw XCTSkip("S44_OUT not set") }
        outDir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        continueAfterFailure = true
    }

    @MainActor
    func testOnboardingShot() throws {
        let app = makeApp(onboarding: true)
        app.launch()
        let start = app.buttons["Take the tour"]
        _ = start.waitForExistence(timeout: 15)
        sleep(2)
        shoot("01-onboarding-welcome")
        app.terminate()
    }

    @MainActor
    func testMainTour() throws {
        let app = makeApp(onboarding: false)
        app.launch()

        // --- Home tab -------------------------------------------------------
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        _ = app.staticTexts["Two-Story House"].waitForExistence(timeout: 10)
        sleep(1)
        shoot("02-home")

        // --- House tab (unified editor+routes): pick Two-Story, wait for routes ----------
        app.tabBars.buttons["House"].tap()
        sleep(2)
        attempt("select two-story in plan") {
            // Toolbar principal picker collapses to a button naming the current home.
            let picker = app.buttons["Bungalow"].exists ? app.buttons["Bungalow"]
                : app.buttons["Apartment 4B"].exists ? app.buttons["Apartment 4B"]
                : app.buttons["Two-Story House"]
            guard picker.waitForExistence(timeout: 5) else { return false }
            if picker.label != "Two-Story House" {
                picker.tap()
                let item = app.buttons["Two-Story House"].firstMatch
                guard item.waitForExistence(timeout: 3) else { return false }
                item.tap()
            }
            return true
        }
        // Routes fetched from the local backend land in a second or two.
        _ = app.staticTexts["Explode"].waitForExistence(timeout: 10)
        sleep(6)
        shoot("03-plan-everyone")

        // The other two fixtures, same whole-house view — the palette/route work must hold
        // on every home, not just the demo star.
        attempt("bungalow + apartment plan") {
            // The toolbar principal Picker isn't an accessibility button; its collapsed
            // label surfaces as a static text naming the current home.
            func switchHome(from current: String, to name: String) -> Bool {
                let picker = app.staticTexts[current].firstMatch
                guard picker.waitForExistence(timeout: 5) else { return false }
                picker.tap()
                let item = app.buttons[name].firstMatch
                guard item.waitForExistence(timeout: 3) else { return false }
                item.tap()
                sleep(5)
                return true
            }
            guard switchHome(from: "Two-Story House", to: "Bungalow") else { return false }
            self.shoot("03b-plan-bungalow")
            guard switchHome(from: "Bungalow", to: "Apartment 4B") else { return false }
            self.shoot("03c-plan-apartment")
            // Back to the two-story for the rest of the tour.
            _ = switchHome(from: "Apartment 4B", to: "Two-Story House")
            return true
        }

        // Room selection → primary + secondary + tour button.
        let toured = attempt("room route + tour") {
            let routeButton = app.descendants(matching: .any)["plan.route.picker"].firstMatch
            guard routeButton.waitForExistence(timeout: 5) else { return false }
            routeButton.tap()
            let room = app.buttons["Kids' Bedroom"].firstMatch
            guard room.waitForExistence(timeout: 3) else { return false }
            room.tap()
            sleep(2)
            self.shoot("04-plan-room")
            let tour = app.descendants(matching: .any)["plan.tour.button"].firstMatch
            guard tour.waitForExistence(timeout: 3) else { return false }
            tour.tap()
            sleep(3)
            self.shoot("05-plan-midtour")
            sleep(8)   // let the tour end so the camera hand-back is exercised
            let stop = app.buttons["Stop"].firstMatch
            if stop.exists { stop.tap() }
            return true
        }
        if !toured { shoot("04-plan-room") }

        // Profile switch (S3.4 money shot).
        attempt("profile switch") {
            let seg = app.segmentedControls.firstMatch
            guard seg.waitForExistence(timeout: 5) else { return false }
            let maya = seg.buttons["Maya"]
            guard maya.exists else { return false }
            maya.tap()
            sleep(4)
            self.shoot("06-plan-profile-maya")
            return true
        }

        // --- House tab again: the unified screen IS the editor now ----------
        app.tabBars.buttons["House"].tap()
        sleep(3)
        shoot("07-editor")

        // --- Assistant ------------------------------------------------------
        app.tabBars.buttons["Assistant"].tap()
        sleep(2)
        let newChat = app.buttons["New Chat"].firstMatch
        if newChat.exists && newChat.isEnabled {
            newChat.tap()
            sleep(1)
        }
        shoot("08-chat-empty")
        attempt("send chat message") {
            let field = app.textFields.firstMatch.exists
                ? app.textFields.firstMatch : app.textViews.firstMatch
            guard field.waitForExistence(timeout: 5) else { return false }
            field.tap()
            field.typeText("How do we get out from upstairs?")
            let send = app.buttons["Send"].firstMatch.exists
                ? app.buttons["Send"].firstMatch
                : app.buttons["arrow.up.circle.fill"].firstMatch
            guard send.exists else { return false }
            send.tap()
            sleep(8)
            self.shoot("09-chat-reply")
            return true
        }

        // --- Relaunch: the chat keyboard otherwise covers the tab bar -------
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))

        // --- Settings -------------------------------------------------------
        app.tabBars.buttons["Settings"].tap()
        sleep(1)
        shoot("10-settings")

        // --- Home swipe actions: Score / Profiles / Drill -------------------
        app.tabBars.buttons["Home"].tap()
        sleep(1)

        func swipeAction(_ button: String, row: String) -> Bool {
            // Rows are List cells; the seeded Two-Story home is the newest → first cell.
            var cell = app.cells.firstMatch
            if !cell.waitForExistence(timeout: 5) {
                let predicate = NSPredicate(format: "label BEGINSWITH %@", row)
                cell = app.buttons.matching(predicate).firstMatch
                guard cell.waitForExistence(timeout: 3) else {
                    print("S44 debug: cells=\(app.cells.count) buttons="
                          + app.buttons.allElementsBoundByIndex.prefix(12).map(\.label)
                              .joined(separator: " | "))
                    return false
                }
            }
            cell.swipeRight()
            let action = app.buttons[button].firstMatch
            guard action.waitForExistence(timeout: 3) else { return false }
            action.tap()
            return true
        }

        attempt("score screen") {
            guard swipeAction("Score", row: "Two-Story House") else { return false }
            sleep(6)
            self.shoot("11-score")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            sleep(1)
            return true
        }

        attempt("profiles screen") {
            guard swipeAction("Profiles", row: "Two-Story House") else { return false }
            sleep(2)
            self.shoot("12-profiles")
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() }
            sleep(1)
            return true
        }

        attempt("drill screen") {
            guard swipeAction("Drill", row: "Two-Story House") else { return false }
            sleep(3)
            self.shoot("13-drill")
            // Begin the drill as Maya, then advance one step.
            let maya = app.buttons["Maya"].firstMatch
            if maya.waitForExistence(timeout: 3) {
                maya.tap()
                sleep(5)
                self.shoot("14-drill-start")
                let next = app.buttons["Next"].firstMatch
                if next.waitForExistence(timeout: 5) {
                    next.tap()
                    sleep(4)
                    self.shoot("15-drill-step")
                }
            }
            return true
        }

        app.terminate()
    }
}

/// S4.3's simulator-verifiable half, backend-down leg: with the server unreachable, every
/// screen on the demo path must degrade to a banner or an explicit error state — never a
/// crash, never a dead spinner. Enabled with TEST_RUNNER_S44_DOWN=1.
final class S44BackendDownUITests: XCTestCase {

    @MainActor
    func testDemoPathWithBackendDown() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["S44_DOWN"] == "1" else {
            throw XCTSkip("Backend-down driver — run with TEST_RUNNER_S44_DOWN=1.")
        }
        let outDir = env["S44_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let outDir {
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        }
        func shoot(_ name: String) {
            guard let outDir else { return }
            try? XCUIScreen.main.screenshot().pngRepresentation
                .write(to: outDir.appendingPathComponent("\(name).png"))
        }

        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            // A port nothing listens on: connection-refused, the offline-cache path.
            "-APIClient.baseURL", "http://localhost:9799",
            "-APIClient.bearerToken", "dev-local-token",
        ]
        app.launch()

        // House: either the cached-plan banner or the error banner — and a live scene.
        XCTAssertTrue(app.tabBars.buttons["House"].waitForExistence(timeout: 15))
        app.tabBars.buttons["House"].tap()
        sleep(8)
        shoot("offline-01-plan")
        XCTAssertTrue(app.staticTexts["Explode"].waitForExistence(timeout: 10),
                      "House screen must still render the dollhouse with the backend down")

        // Assistant: send must fail into the error banner, not hang.
        app.tabBars.buttons["Assistant"].tap()
        sleep(1)
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("Are we ready?")
            let send = app.buttons["arrow.up.circle.fill"].firstMatch.exists
                ? app.buttons["arrow.up.circle.fill"].firstMatch : app.buttons["Send"].firstMatch
            if send.exists { send.tap() }
            let retry = app.buttons["Retry"].firstMatch
            XCTAssertTrue(retry.waitForExistence(timeout: 30),
                          "chat failure must surface a Retry, not a spinner forever")
            shoot("offline-02-chat")
        }

        // Score: explicit error state with Try Again.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        let cell = app.cells.firstMatch
        if cell.waitForExistence(timeout: 5) {
            cell.swipeRight()
            let score = app.buttons["Score"].firstMatch
            if score.waitForExistence(timeout: 3) {
                score.tap()
                let tryAgain = app.buttons["Try Again"].firstMatch
                XCTAssertTrue(tryAgain.waitForExistence(timeout: 30),
                              "score failure must land in the Try Again empty state")
                shoot("offline-03-score")
                let back = app.navigationBars.buttons.firstMatch
                if back.exists { back.tap() }
                sleep(1)
            }
        }

        // Drill: picking a person must surface the route error banner, app stays alive.
        let cell2 = app.cells.firstMatch
        if cell2.waitForExistence(timeout: 5) {
            cell2.swipeRight()
            let drill = app.buttons["Drill"].firstMatch
            if drill.waitForExistence(timeout: 3) {
                drill.tap()
                let maya = app.buttons["Maya"].firstMatch
                if maya.waitForExistence(timeout: 5) {
                    maya.tap()
                    sleep(8)
                    shoot("offline-04-drill")
                }
            }
        }

        // Still alive at the end — the whole point.
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
    }
}
