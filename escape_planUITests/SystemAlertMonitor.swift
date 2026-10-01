//  SystemAlertMonitor.swift — S11.8: the shared answer to a system alert covering the app.
//
//  BLOCKERS §4 records the second face of this project's iOS flake: a tab-bar button that goes
//  stale mid-tap, which XCTest attributes to a system interruption. With no interruption monitor
//  installed, XCTest has nothing to hand that alert to and the tap fails. Every UI test class
//  calls `installSystemAlertMonitor()` from its setUp, so there is one policy in one place.
//
//  The policy declines rather than grants. A test that passes only because a permission was
//  granted mid-run is testing a different app from the one a first-time user sees, and nothing
//  in these tests needs the camera, location or notifications. "OK" and "Close" come last: they
//  are for informational alerts that offer no choice.
//
//  Each time it fires it prints `[UIInterruption]`, so a run's log says how often it was needed:
//  grep the xcodebuild output for that tag when measuring whether it reduced flake.

import XCTest

extension XCTestCase {

    /// Safe to call from a nonisolated `setUpWithError()`: registering is not UI work, and
    /// XCTest invokes the handler on the main thread, which `assumeIsolated` asserts.
    func installSystemAlertMonitor() {
        let testName = name
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            MainActor.assumeIsolated {
                let declineFirst = ["Don’t Allow", "Don't Allow", "Not Now", "Cancel",
                                    "OK", "Close", "Dismiss"]
                for label in declineFirst where alert.buttons[label].exists {
                    print("[UIInterruption] \(testName): tapped \"\(label)\" on \"\(alert.label)\"")
                    alert.buttons[label].tap()
                    return true
                }
                print("[UIInterruption] \(testName): unhandled alert \"\(alert.label)\"")
                return false
            }
        }
    }
}
