// ManualBuildRecordingUITests.swift
// Lane A acceptance: builds a complete two-story home ENTIRELY BY HAND in the editor —
// rooms, interior doors, an exterior door, windows, stairs — then opens the Plan tab and
// confirms the deterministic engine returns routes for it. Drives the real UI so
// `xcrun simctl io ... recordVideo` can capture the evidence unattended.
//
// Skipped unless MANUAL_BUILD=1 is in the runner environment (pass
// TEST_RUNNER_MANUAL_BUILD=1 to xcodebuild) — the routes step needs a live backend, so it
// must never gate the normal suite. Backend + token come from MANUAL_BUILD_BASE_URL /
// MANUAL_BUILD_TOKEN (defaults match backend/README.md's local run).
//
// How taps find geometry: the unified editor normally runs a free perspective orbit camera,
// which is not invertible from outside the app — so this driver launches with
// `-editor.topDownCamera YES`, which pins the old deterministic top-down orthographic frame
// (UnifiedSceneController.applyTopDownFrame — bbox + 1.5 m padding, scale =
// max(width, depth) / 2). The test tracks the room rectangles it has built and inverts that
// projection to turn floor-plan meters into normalized offsets on the scene view
// (accessibility id "editor.scene").
//
// Drags must land on the CURRENT SELECTION to edit (GestureArbiter — anything else orbits),
// so every corner-drag below is preceded by a tap selecting its room.

import XCTest

final class ManualBuildRecordingUITests: XCTestCase {

    private var app: XCUIApplication!
    private var scene: XCUIElement!
    /// Axis-aligned room rects (schema meters) on the CURRENTLY ACTIVE floor — the test's
    /// mirror of what it has built, driving the camera-inverse math.
    private var rooms: [CGRect] = []

    @MainActor
    func testBuildTwoStoryHomeByHandAndFetchRoutes() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["MANUAL_BUILD"] == "1" else {
            throw XCTSkip("Recording driver — run with TEST_RUNNER_MANUAL_BUILD=1 and a live backend.")
        }
        let baseURL = env["MANUAL_BUILD_BASE_URL"] ?? "http://localhost:8001"
        let token = env["MANUAL_BUILD_TOKEN"] ?? "dev-local-token"

        // The synthesized-event → window coordinate conversion is only trustworthy when the
        // device orientation and the app's interface orientation agree; pin both to portrait.
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-APIClient.baseURL", baseURL,
            "-APIClient.bearerToken", token,
            "-editor.topDownCamera", "YES",
        ]
        app.launch()

        // Home tab → a brand-new home in the editor.
        app.tabBars.buttons["Home"].tap()
        let menuButton = app.buttons["Menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10))
        menuButton.tap()
        
        let newHome = app.buttons["Build Manually"].firstMatch
        XCTAssertTrue(newHome.waitForExistence(timeout: 10))
        newHome.tap()

        scene = app.otherElements["editor.scene"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        pause(2)

        // ---- Ground floor: Room 1 exists at (0,0)-(3,3). Add a second room and join it. ----
        rooms = [CGRect(x: 0, y: 0, width: 3, height: 3)]
        addMenuTap("Add Room")
        rooms.append(CGRect(x: 3.5, y: 0, width: 3, height: 3))
        pause(1)

        // Join: drag the new room's left corners onto Room 1's right corners (vertex snap
        // lands them exactly — that shared wall is what makes the door INTERIOR). Select the
        // room first: unselected geometry orbits the camera instead of dragging.
        tapWorld(5.0, 1.5)
        pause(1)
        dragWorld(from: (3.5, 0), to: (3.02, 0.02))
        rooms[1] = CGRect(x: 3, y: 0, width: 3.5, height: 3)   // left edge now at x=3 (bottom)
        dragWorld(from: (3.5, 3), to: (3.02, 2.98))
        pause(1)

        // Interior door on the shared wall — the inspector must read "Interior".
        addMenuTap("Add Door")
        tapWorld(3.0, 1.5)
        XCTAssertTrue(app.staticTexts["Interior"].waitForExistence(timeout: 5),
                      "door on the shared wall must derive an interior connection")
        pause(1)

        // Exterior door on Room 1's bottom wall — this is the exit.
        addMenuTap("Add Door")
        tapWorld(1.5, 0.0)
        XCTAssertTrue(app.staticTexts["Exterior"].waitForExistence(timeout: 5),
                      "door on an unshared wall must derive EXTERIOR (an exit)")
        pause(1)

        // Two windows on exterior walls.
        addMenuTap("Add Window")
        tapWorld(1.5, 3.0)
        XCTAssertTrue(app.staticTexts["Exterior"].waitForExistence(timeout: 5))
        addMenuTap("Add Window")
        tapWorld(6.5, 1.5)
        XCTAssertTrue(app.staticTexts["Exterior"].waitForExistence(timeout: 5))
        pause(1)

        // ---- Second floor: add it, build two joined rooms, connect with a door. ----
        addMenuTap("Add Floor Above")
        let secondFloor = app.buttons["Second Floor"]
        XCTAssertTrue(secondFloor.waitForExistence(timeout: 5))
        secondFloor.tap()
        rooms = [CGRect(x: 0, y: 0, width: 3, height: 3)]      // the seeded starter room
        pause(1)

        addMenuTap("Add Room")
        rooms.append(CGRect(x: 3.5, y: 0, width: 3, height: 3))
        pause(1)
        tapWorld(5.0, 1.5)                                     // select before dragging
        pause(1)
        dragWorld(from: (3.5, 0), to: (3.02, 0.02))
        rooms[1] = CGRect(x: 3, y: 0, width: 3.5, height: 3)
        dragWorld(from: (3.5, 3), to: (3.02, 2.98))
        addMenuTap("Add Door")
        tapWorld(3.0, 1.5)
        XCTAssertTrue(app.staticTexts["Interior"].waitForExistence(timeout: 5))
        pause(1)

        // ---- Stairs: ground floor room 1 up to the starter room. ----
        app.buttons["Ground Floor"].tap()
        rooms = [CGRect(x: 0, y: 0, width: 3, height: 3),
                 CGRect(x: 3, y: 0, width: 3.5, height: 3)]
        pause(1)
        tapWorld(1.5, 1.5)                                     // select Room 1
        pause(1)
        addMenuTap("Add Stairs")
        let upstairsRoom = app.buttons["Room"].firstMatch
        XCTAssertTrue(upstairsRoom.waitForExistence(timeout: 5))
        upstairsRoom.tap()
        pause(1)

        // Undo/redo on camera: redo must work on the FIRST tap (the old stale-render bug).
        app.buttons["Undo"].tap()
        pause(1)
        app.buttons["Redo"].tap()
        pause(2)

        // ---- Routes: same screen — the unified HouseScreen re-fetches after every edit
        // burst, so the deterministic engine's plan appears in place. ----

        // routeControls only render once a RoutePlan arrived from /routes.
        let routeHint = app.staticTexts["Pick a room to tour"]
        XCTAssertTrue(routeHint.waitForExistence(timeout: 60),
                      "the engine must return a plan for the hand-built home")
        pause(2)

        // Select Room 1's route: a Tour button proves a primary route exists for it.
        let routePicker = app.buttons["Route"].firstMatch
        if routePicker.exists {
            routePicker.tap()
            let roomChoice = app.buttons["Room 1"].firstMatch
            XCTAssertTrue(roomChoice.waitForExistence(timeout: 5))
            roomChoice.tap()
            XCTAssertTrue(app.buttons["Tour"].waitForExistence(timeout: 10),
                          "Room 1 must have a primary route to tour")
        }
        pause(4)
    }

    // MARK: - Editor helpers

    /// Opens the toolbar Add menu and taps one of its items.
    private func addMenuTap(_ item: String) {
        app.buttons["Add"].firstMatch.tap()
        let button = app.buttons[item].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "menu item \(item)")
        button.tap()
    }

    // MARK: - World-space taps (inverse of EditorSceneController's framing)

    private struct Framing {
        let cx: Double, cy: Double, scale: Double
    }

    private func framing() -> Framing {
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for r in rooms {
            minX = min(minX, r.minX); maxX = max(maxX, r.maxX)
            minY = min(minY, r.minY); maxY = max(maxY, r.maxY)
        }
        let padding = 1.5
        let width = (maxX - minX) + padding * 2
        let depth = (maxY - minY) + padding * 2
        return Framing(cx: (minX + maxX) / 2, cy: (minY + maxY) / 2,
                       scale: max(width, depth) / 2)
    }

    /// Schema meters -> XCUICoordinate on the scene view. The camera is orthographic and
    /// top-down: orthographicScale is half the frustum height, width scales by aspect, and
    /// schema +y points UP the screen (scenePoint maps (x, y) -> (x, -z)).
    private func coordinate(_ x: Double, _ y: Double) -> XCUICoordinate {
        let f = framing()
        let frame = scene.frame
        let aspect = Double(frame.width / frame.height)
        let u = 0.5 + (x - f.cx) / (2 * f.scale * aspect)
        let v = 0.5 + (f.cy - y) / (2 * f.scale)
        return scene.coordinate(withNormalizedOffset: CGVector(dx: u, dy: v))
    }

    private func tapWorld(_ x: Double, _ y: Double) {
        coordinate(x, y).tap()
    }

    private func dragWorld(from: (Double, Double), to: (Double, Double)) {
        coordinate(from.0, from.1).press(forDuration: 0.4, thenDragTo: coordinate(to.0, to.1),
                                         withVelocity: .slow, thenHoldForDuration: 0.3)
        pause(0.5)
    }

    /// Real wall-clock pause so the recording isn't a blur (see GoldenPathRecordingUITests).
    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
