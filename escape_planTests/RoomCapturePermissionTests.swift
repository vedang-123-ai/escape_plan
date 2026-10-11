import XCTest
import AVFoundation
@testable import escape_plan

@MainActor
final class RoomCapturePermissionTests: XCTestCase {

    func testCameraPermissionDeniedTransitionsToPermissionDeniedPhase() {
        let controller = RoomCaptureController()
        controller.cameraAuthorizationStatus = { .denied }

        controller.startScanningRoom()

        XCTAssertEqual(controller.phase, .permissionDenied)
    }

    func testCameraPermissionRestrictedTransitionsToPermissionDeniedPhase() {
        let controller = RoomCaptureController()
        controller.cameraAuthorizationStatus = { .restricted }

        controller.startScanningRoom()

        XCTAssertEqual(controller.phase, .permissionDenied)
    }

    func testSingleRoomScanWithDeniedPermissionTransitionsToPermissionDeniedPhase() {
        let controller = RoomCaptureController()
        controller.cameraAuthorizationStatus = { .denied }

        controller.startSingleRoomScan(roomID: "room-1")

        XCTAssertEqual(controller.phase, .permissionDenied)
    }

    func testRetryAfterPermissionDeniedReturnsToInstructions() {
        let controller = RoomCaptureController()
        controller.cameraAuthorizationStatus = { .denied }

        controller.startScanningRoom()
        XCTAssertEqual(controller.phase, .permissionDenied)

        controller.retry()
        XCTAssertEqual(controller.phase, .instructions)
    }
}
