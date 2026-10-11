//
//  ScanFlowView.swift
//  Capture/Views — S1.4
//
//  The scan flow: instructions → scanning → per-room checkpoint → processing →
//  review. Entry point for the whole Capture module.
//
//  Integration: HomeScreen presents this as a `fullScreenCover` (toolbar "Scan",
//  and the empty state's "Scan a Home"). `onFinished` hands back the artifacts on
//  disk; HomeScreen uploads `artifacts.rawJSON` via `APIClient.convertScan(at:homeName:)`,
//  saves the returned HomeModel, and opens it in the editor for review.
//

import SwiftUI

//  Accessibility (lane D1): the three hero glyphs here were `.system(size: 56/48/48)` — fixed
//  point sizes that ignore Dynamic Type. Each is decorative (the headline directly beneath
//  says the same thing), so each is now hidden from VoiceOver and dropped at accessibility
//  sizes rather than scaled, which would push the primary action off-screen on a small phone.

/// Shared by every scan step: whether the decorative hero glyph earns its space at the
/// current text size.
private struct ScanHeroGlyph: View {
    let systemName: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize < .accessibility1 {
            Image(systemName: systemName)
                .font(.system(size: 52))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
    }
}

struct ScanFlowView: View {
    /// Called once the scan's artifacts are on disk.
    var recheckRoomID: String? = nil
    var onFinished: (ScanArtifacts) -> Void
    /// Called if the user backs out before finishing.
    var onCancel: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controller = RoomCaptureController()

    var body: some View {
        Group {
            switch controller.phase {
            case .instructions:
                ScanInstructionsView(
                    isSupported: controller.isSupported,
                    capturedRoomCount: controller.capturedRoomCount,
                    onStart: { controller.startScanningRoom() },
                    onCancel: onCancel
                )

            case .scanning:
                scanningView

            case .roomFinished:
                ScanRoomFinishedView(
                    capturedRoomCount: controller.capturedRoomCount,
                    onScanAnother: { controller.startScanningRoom() },
                    onFinish: { Task { await controller.exportScan() } }
                )

            case .processing:
                ScanProcessingView()

            case .finished(let artifacts):
                ScanReviewView(
                    artifacts: artifacts,
                    fallbackReason: controller.fallbackReason,
                    onUse: { onFinished(artifacts) },
                    onRescan: { controller.reset() }
                )

            case .failed(let message):
                ScanFailureView(
                    message: message,
                    capturedRoomCount: controller.capturedRoomCount,
                    onRetry: { controller.retry() },
                    onCancel: onCancel
                )

            case .permissionDenied:
                ScanPermissionDeniedView(
                    capturedRoomCount: controller.capturedRoomCount,
                    onOpenSettings: {
                        #if canImport(UIKit)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    },
                    onCancel: onCancel
                )
            }
        }
        // Reduce Motion: steps still swap, they just cut instead of cross-fading. The flow is
        // unchanged — only the transition is.
        .animation(reduceMotion ? nil : .default, value: controller.phase)
    }

    @ViewBuilder
    private var scanningView: some View {
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        ZStack(alignment: .bottom) {
            RoomCaptureViewRepresentable(captureView: controller.roomCaptureView)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Walk the walls slowly. Keep doors open.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityAddTraits(.isStaticText)

                Button {
                    controller.finishCurrentRoom()
                } label: {
                    Text("Done with this room")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .accessibilityLabel("Done with this room")
                .accessibilityHint("Stops capturing this room and lets you scan the next one.")
            }
            .padding(.bottom, 32)
        }
        // The live camera view is the content; VoiceOver users can't drive a LiDAR scan from
        // it, so the controls carry the whole interaction and get read first.
        .accessibilityElement(children: .contain)
        #else
        // Simulator / no RoomPlan: the flow is still navigable for UI work.
        ScanUnsupportedView(onCancel: onCancel)
        #endif
    }
}

// MARK: - Instructions

struct ScanInstructionsView: View {
    var isSupported: Bool
    var capturedRoomCount: Int
    var onStart: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(capturedRoomCount == 0 ? "Scan your home" : "Scan the next room")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            if capturedRoomCount > 0 {
                Label("\(capturedRoomCount) room\(capturedRoomCount == 1 ? "" : "s") captured so far",
                      systemImage: "checkmark.circle.fill")
                    // Accent as TEXT needs 4.5:1; the fill accent measures 4.45:1 on white.
                    .foregroundStyle(Theme.accentText)
                    .accessibilityLabel("\(capturedRoomCount) "
                                        + "room\(capturedRoomCount == 1 ? "" : "s") captured so far.")
            }

            VStack(alignment: .leading, spacing: 14) {
                ScanTipRow(icon: "lightbulb.fill",
                           title: "Turn the lights on",
                           detail: "RoomPlan needs a well-lit room to find walls.")
                ScanTipRow(icon: "figure.walk.motion",
                           title: "Pan slowly",
                           detail: "Walk the perimeter and sweep the camera along each wall.")
                ScanTipRow(icon: "door.left.hand.open",
                           title: "Open every door",
                           detail: "Closed doors get missed — and doors are your escape routes.")
                ScanTipRow(icon: "window.vertical.closed",
                           title: "Include windows",
                           detail: "Bedroom windows may be a second way out. Don't skip them.")
            }

            Spacer()

            if !isSupported {
                Label("This device doesn't have LiDAR, so scanning is unavailable. "
                      + "You can still build your home in the editor.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.supporting)
            }

            Button(action: onStart) {
                Text(capturedRoomCount == 0 ? "Start scanning" : "Scan next room")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isSupported)
            .accessibilityLabel(capturedRoomCount == 0 ? "Start scanning" : "Scan next room")
            .accessibilityHint(isSupported
                               ? "Opens the camera to capture the room you're standing in."
                               : "Unavailable — this device has no LiDAR scanner.")

            Button("Cancel", action: onCancel)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Leaves the scan without saving anything.")
        }
        .padding(24)
    }
}

struct ScanTipRow: View {
    var icon: String
    var title: String
    var detail: String

    /// The glyph column scales with the text, so the tip text doesn't collide with it at large
    /// sizes the way a hard-coded 28pt column did.
    @ScaledMetric(relativeTo: .title3) private var iconColumn: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: iconColumn)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.supporting)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

// MARK: - Between rooms

struct ScanRoomFinishedView: View {
    var capturedRoomCount: Int
    var onScanAnother: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ScanHeroGlyph(systemName: "checkmark.circle.fill", tint: Theme.accent)

            Text("Room captured")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("\(capturedRoomCount) room\(capturedRoomCount == 1 ? "" : "s") so far. "
                 + "Walk to the next room without closing the app so the rooms line up.")
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: onScanAnother) {
                Text("Scan another room").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Captures another room and adds it to this home.")

            Button(action: onFinish) {
                Text("Finish scan").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Merges the \(capturedRoomCount) captured "
                               + "room\(capturedRoomCount == 1 ? "" : "s") into one home model.")
        }
        .padding(24)
    }
}

// MARK: - Processing

struct ScanProcessingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Building your home model…")
                .font(.headline)
            Text("Merging rooms and saving the scan.")
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)
        }
        .padding(24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Building your home model. Merging rooms and saving the scan.")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Review

struct ScanReviewView: View {
    var artifacts: ScanArtifacts
    var fallbackReason: String?
    var onUse: () -> Void
    var onRescan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan complete")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Label("\(artifacts.roomCount) room\(artifacts.roomCount == 1 ? "" : "s") captured",
                  systemImage: "square.split.bltr")
                .accessibilityLabel("\(artifacts.roomCount) "
                                    + "room\(artifacts.roomCount == 1 ? "" : "s") captured.")

            Label(artifacts.usdz == nil ? "3D preview unavailable" : "3D preview saved",
                  systemImage: artifacts.usdz == nil ? "cube.transparent" : "cube.fill")
                .foregroundStyle(artifacts.usdz == nil ? AnyShapeStyle(Theme.supporting)
                                                       : AnyShapeStyle(.primary))

            if let fallbackReason {
                Label(fallbackReason, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
                    .accessibilityLabel("Heads up. \(fallbackReason)")
            }

            Text("The scan is a starting point, not the final map — you'll fix walls, "
                 + "doors and windows in the editor next.")
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)

            // Surfaced so a tester can find the files to copy off the device for
            // schema/fixtures/scans/ (S1.4's handoff artifact). Was `.tertiary` — ~1.74:1 on
            // white, i.e. unreadable to the exact tester who needs to read it.
            Text(artifacts.directory.lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.supporting)
                .textSelection(.enabled)
                .accessibilityLabel("Scan saved in folder \(artifacts.directory.lastPathComponent)")

            Spacer()

            Button(action: onUse) {
                Text("Continue to editor").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Turns this scan into an editable home model.")

            Button(action: onRescan) {
                Text("Scan again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Discards this scan and starts over.")
        }
        .padding(24)
    }
}

// MARK: - Failure / unsupported

struct ScanFailureView: View {
    var message: String
    var capturedRoomCount: Int
    var onRetry: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ScanHeroGlyph(systemName: "exclamationmark.triangle.fill", tint: Theme.caution)

            Text("Scan interrupted")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)
                .multilineTextAlignment(.center)

            if capturedRoomCount > 0 {
                Text("Your \(capturedRoomCount) captured room\(capturedRoomCount == 1 ? "" : "s") "
                     + "\(capturedRoomCount == 1 ? "is" : "are") safe — retrying keeps them.")
                    .font(.footnote)
                    .foregroundStyle(Theme.supporting)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onRetry) {
                Text("Try again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint(capturedRoomCount > 0
                               ? "Restarts the scan. The rooms you already captured are kept."
                               : "Restarts the scan.")

            Button("Cancel", action: onCancel)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Leaves the scan.")
        }
        .padding(24)
    }
}

struct ScanPermissionDeniedView: View {
    var capturedRoomCount: Int
    var onOpenSettings: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ScanHeroGlyph(systemName: "camera.badge.ellipsis", tint: Theme.caution)

            Text("Camera access needed")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("Escape Plan uses the camera and LiDAR scanner to measure your rooms, doors and windows. To scan your home, allow camera access in Settings.")
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)
                .multilineTextAlignment(.center)

            if capturedRoomCount > 0 {
                Text("Your \(capturedRoomCount) captured room\(capturedRoomCount == 1 ? "" : "s") "
                     + "\(capturedRoomCount == 1 ? "is" : "are") safe.")
                    .font(.footnote)
                    .foregroundStyle(Theme.supporting)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onOpenSettings) {
                Text("Open Settings").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Opens iOS Settings so you can allow camera access.")

            Button("Cancel", action: onCancel)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Leaves the scan.")
        }
        .padding(24)
    }
}

struct ScanUnsupportedView: View {
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ScanHeroGlyph(systemName: "iphone.slash", tint: Theme.supporting)
            Text("Scanning needs a LiDAR device")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Run on an iPhone/iPad Pro to capture a room. "
                 + "The editor works everywhere.")
                .font(.subheadline)
                .foregroundStyle(Theme.supporting)
                .multilineTextAlignment(.center)
            Button("Back", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Goes back without scanning.")
        }
        .padding(24)
    }
}
