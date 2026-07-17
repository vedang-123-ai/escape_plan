//
//  RoomCaptureViewRepresentable.swift
//  Capture/Views — S1.4
//
//  Bridges RoomPlan's UIKit `RoomCaptureView` (with Apple's built-in coaching
//  overlay) into SwiftUI. The view instance is owned by the controller, not
//  created here — RoomPlan ties the AR session to the view, so re-creating it on
//  a SwiftUI update would tear the scan down mid-capture.
//

import SwiftUI

#if canImport(RoomPlan)
import RoomPlan

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let captureView: RoomCaptureView

    func makeUIView(context: Context) -> RoomCaptureView { captureView }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        // Intentionally empty: all scan state lives in the controller and is
        // driven through the capture session, not through view updates.
    }
}
#endif
