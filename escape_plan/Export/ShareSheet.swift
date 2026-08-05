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

/// Presents the system share sheet for `url` as soon as it becomes non-nil, then clears the
/// binding when the user is done (which is also what dismisses it in SwiftUI's model).
struct ShareSheet: UIViewControllerRepresentable {
    @Binding var url: URL?

    func makeUIViewController(context: Context) -> ShareAnchorController {
        ShareAnchorController()
    }

    func updateUIViewController(_ anchor: ShareAnchorController, context: Context) {
        guard let url else { return }
        anchor.present(url: url) { self.url = nil }
    }
}

/// Invisible anchor the activity controller is presented from.
final class ShareAnchorController: UIViewController {
    private var presentedURL: URL?

    func present(url: URL, onFinish: @escaping () -> Void) {
        guard presentedURL != url, presentedViewController == nil else { return }
        presentedURL = url

        // `updateUIViewController` can run before this controller is in the window.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else {
                self?.presentedURL = nil
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
                self?.presentedURL = nil
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
