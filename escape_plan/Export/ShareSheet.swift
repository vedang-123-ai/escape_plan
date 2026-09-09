//  ShareSheet.swift
//  escape_plan — Export module
//
//  SwiftUI wrapper over `UIActivityViewController` for handing the generated PDF to Save to
//  Files / Print / AirDrop / Mail.
//
//  It is used as a zero-size `.background(...)` of the export sheet rather than as a
//  presented sheet of its own: presenting an activity controller from inside a SwiftUI sheet
//  otherwise means flashing an empty sheet behind it. Anchoring the popover to this view is
//  also what keeps iPad happy — an unanchored `UIActivityViewController` in a popover
//  presentation environment traps at runtime.

import SwiftUI
import UIKit

/// Presents the system share sheet for `urls` as soon as it becomes non-nil, then clears the
/// binding when the user is done (which is also what dismisses it in SwiftUI's model).
struct ShareSheet: UIViewControllerRepresentable {
    @Binding var urls: [URL]?

    func makeUIViewController(context: Context) -> ShareAnchorController {
        ShareAnchorController()
    }

    func updateUIViewController(_ anchor: ShareAnchorController, context: Context) {
        guard let urls, !urls.isEmpty else { return }
        anchor.present(urls: urls) { self.urls = nil }
    }
}

/// Invisible anchor the activity controller is presented from.
final class ShareAnchorController: UIViewController {
    private var presentedURLs: [URL]?

    func present(urls: [URL], onFinish: @escaping () -> Void) {
        guard presentedURLs != urls, presentedViewController == nil else { return }
        presentedURLs = urls

        // `updateUIViewController` can run before this controller is in the window.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else {
                self?.presentedURLs = nil
                return
            }
            let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
                self?.presentedURLs = nil
                onFinish()
            }
            if let popover = activity.popoverPresentationController {
                popover.sourceView = self.view
                popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY,
                                            width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            self.present(activity, animated: true)
        }
    }
}
