// GestureFrameCostUITests.swift
//
// The measurement behind #5: how many SwiftUI update passes actually land on a camera drag's
// frames. HouseScreen carries ~40 `@State` vars and its own warning about "an endless rebuild
// loop that starves gesture handling", so the question is not rhetorical — every
// `updateUIView` runs `rebuildIfNeeded` and, in the drill host, a sweep of every floor.
//
// It reads the counter off the scene view's `accessibilityValue`, which the app only writes
// under `-editor.gestureInstrumentation YES`. That channel exists because log streams do not
// reach a cloned test simulator (decisions.md 2026-07-23).
//
// No backend needed: "New Home" seeds a starter room locally, and this only drags the camera.

import XCTest

final class GestureFrameCostUITests: XCTestCase {

    /// Parses `updates=N duringGesture=M`.
    private func counters(_ value: String?) -> (updates: Int, duringGesture: Int)? {
        guard let value else { return nil }
        let parts = value.split(separator: " ")
        guard parts.count == 2,
              let updates = Int(parts[0].split(separator: "=").last ?? ""),
              let during = Int(parts[1].split(separator: "=").last ?? "") else { return nil }
        return (updates, during)
    }

    func testACameraDragDoesNotDragSwiftUIUpdatesAlongWithIt() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-onboarding.completed", "YES",
            "-editor.gestureInstrumentation", "YES",
        ]
        app.launch()

        app.tabBars.buttons["Home"].tap()
        let newHome = app.buttons["New Home"].firstMatch
        XCTAssertTrue(newHome.waitForExistence(timeout: 20), "could not reach the home library")
        newHome.tap()

        let scene = app.otherElements["editor.scene"].firstMatch
        XCTAssertTrue(scene.waitForExistence(timeout: 20), "the 3D surface never appeared")

        // Let the opening render and any settling animation finish, so the baseline is a
        // genuinely idle screen rather than the tail of launch.
        Thread.sleep(forTimeInterval: 3)
        guard let before = counters(scene.value as? String) else {
            throw XCTSkip("Instrumentation channel unreadable — accessibilityValue was "
                          + "\(String(describing: scene.value)). The fix still stands; only "
                          + "this measurement is unavailable.")
        }

        // A slow press-drag across the middle of the scene: one finger, so it orbits, and slow
        // enough to span many frames. Starting off-centre avoids the seeded starter room, so
        // GestureArbiter routes it to the camera rather than to an edit drag.
        let start = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.30))
        let end = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.42))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)

        Thread.sleep(forTimeInterval: 1.5)
        let after = counters(scene.value as? String)
        XCTAssertNotNil(after)

        // The number that matters. Update passes DURING the gesture are the ones that land on
        // its frames; passes before and after are free.
        let landedOnGestureFrames = (after?.duringGesture ?? 0) - before.duringGesture
        // Printed, not just asserted: the interesting number is how many passes the drag
        // provoked AT ALL, which a pass/fail cannot tell you.
        print("[gesture-cost] before=\(before) after=\(String(describing: after)) "
              + "provokedByDrag=\((after?.updates ?? 0) - before.updates) "
              + "landedOnGestureFrames=\(landedOnGestureFrames)")
        XCTAssertEqual(landedOnGestureFrames, 0,
                       "\(landedOnGestureFrames) SwiftUI update passes ran while a camera "
                       + "gesture was in flight; each one runs rebuildIfNeeded and a redraw "
                       + "on the drag's own frames")
    }
}
