// RouteRedrawAfterEditUITests.swift
// The regression guard for the bug that survived a merge twice (2026-07-24, 2026-07-30).
//
// `onRebuild` captures the HouseScreen struct once, so every @State read inside it returns
// attach-time values. Committing an edit rebuilds the dollhouse, fires `onRebuild`, and — with
// the stale capture — wiped the routes as fast as they were drawn. Two branches each fixed
// half of it (`RouteOverlayHolder` for draw inputs, `SceneViewStateHolder` for view state);
// a verbatim "take theirs" during the merge would have silently reverted one half.
//
// The insufficient test is asserting the route CONTROLS reappear: the bug's exact signature
// was "controls appear but no route draws." So this drives a real committing edit and compares
// route-colored pixels in the 3D view before and after. Screenshots go to ROUTE_REDRAW_OUT
// for eyeball confirmation; the pixel assertion is what fails CI.
//
// Skipped unless ROUTE_REDRAW=1 (pass TEST_RUNNER_ROUTE_REDRAW=1) — it needs a live local
// backend, so it must never gate the normal suite.

import XCTest

final class RouteRedrawAfterEditUITests: XCTestCase {

    private var outDir: URL?

    override func setUpWithError() throws {
        installSystemAlertMonitor()
    }

    /// Primary-route blue pixels, as a fraction of the frame. This matches
    /// `DollhousePalette.routePrimary` (#123FB0), not the retired orange route color.
    private func routePixelFraction(_ screenshot: XCUIScreenshot) -> Double {
        guard let cg = screenshot.image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &raw, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hits = 0
        for i in stride(from: 0, to: raw.count, by: 4) {
            let r = Double(raw[i]), g = Double(raw[i + 1]), b = Double(raw[i + 2])
            // #123FB0 is blue-dominant; allow lighting and antialiasing around it.
            if b > 110, r < 80, g > 35, g < 115, b - r > 75 {
                hits += 1
            }
        }
        return Double(hits) / Double(width * height)
    }

    private func shoot(_ name: String, _ screenshot: XCUIScreenshot) {
        guard let outDir else { return }
        try? screenshot.pngRepresentation.write(to: outDir.appendingPathComponent("\(name).png"))
    }

    func testRoutesStillDrawAfterAnEditCommits() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["ROUTE_REDRAW"] == "1" else {
            throw XCTSkip("Needs a live backend — run with TEST_RUNNER_ROUTE_REDRAW=1.")
        }
        if let out = env["ROUTE_REDRAW_OUT"] {
            outDir = URL(fileURLWithPath: out, isDirectory: true)
            try? FileManager.default.createDirectory(
                at: outDir!, withIntermediateDirectories: true)
        }

        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-auth.gate.dismissed", "YES",
            "-TEST_SEED_DEMO_HOME", "YES",
            "-APIClient.baseURL", env["ROUTE_REDRAW_BASE_URL"] ?? "http://localhost:8000",
            "-APIClient.bearerToken", env["ROUTE_REDRAW_TOKEN"] ?? "dev-local-token",
        ]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["House"].waitForExistence(timeout: 20))
        app.tabBars.buttons["House"].tap()

        // Routes arrive from the backend a beat after the scene builds.
        XCTAssertTrue(app.buttons["house.addMenu"].waitForExistence(timeout: 20),
                      "House screen never finished loading")
        XCTAssertTrue(app.buttons["plan.route.picker"].waitForExistence(timeout: 20), "route controls never appeared")
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5), "Profiles missing! Blank home loaded instead of Two-Story House.")
        sleep(3)
        if app.buttons["Upstairs"].waitForExistence(timeout: 5) {
            app.buttons["Upstairs"].tap()
        }
        sleep(3)

        let before = XCUIScreen.main.screenshot()
        shoot("before-edit", before)
        let beforeFraction = routePixelFraction(before)
        XCTAssertGreaterThan(
            beforeFraction, 0.001,
            "no route pixels BEFORE the edit — the test can't prove anything about the redraw"
        )

        // --- the committing edit ------------------------------------------------
        // Add Object commits through HomeModelStore.onCommit -> invalidateRoutes(), which
        // clears the overlay, debounces ~900ms, refetches, and redraws. It also rebuilds the
        // dollhouse (objects are rendered), which is what fires `onRebuild`.
        let addButton = app.buttons["house.addMenu"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "no Add menu in the toolbar")
        addButton.tap()
        let addObject = app.buttons["Add Object"]
        XCTAssertTrue(addObject.waitForExistence(timeout: 10), "Add Object missing from the menu")
        addObject.tap()

        // 900ms debounce + the round trip + the redraw. Generous: a slow refetch that
        // eventually draws is a different (and lesser) problem than one that never draws.
        sleep(12)

        let after = XCUIScreen.main.screenshot()
        shoot("after-edit", after)
        let afterFraction = routePixelFraction(after)

        XCTAssertGreaterThan(
            afterFraction, beforeFraction * 0.5,
            """
            Routes did not come back after a committed edit — the 2026-07-24 blocker has \
            regressed. Route pixels went \(beforeFraction) -> \(afterFraction). \
            Check that `onRebuild` calls overlayHolder.redraw() and NOT applyOverlay().
            """
        )
    }
}
