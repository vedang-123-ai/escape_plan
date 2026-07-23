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

struct ScanFlowView: View {
    /// Called once the scan's artifacts are on disk.
    var onFinished: (ScanArtifacts) -> Void
    /// Called if the user backs out before finishing.
    var onCancel: () -> Void = {}

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
            }
        }
        .animation(.default, value: controller.phase)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())

                Button {
                    controller.finishCurrentRoom()
                } label: {
                    Text("Done with this room")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
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

            if capturedRoomCount > 0 {
                Label("\(capturedRoomCount) room\(capturedRoomCount == 1 ? "" : "s") captured so far",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
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
                    .foregroundStyle(.secondary)
            }

            Button(action: onStart) {
                Text(capturedRoomCount == 0 ? "Start scanning" : "Scan next room")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isSupported)

            Button("Cancel", action: onCancel)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }
}

struct ScanTipRow: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Between rooms

struct ScanRoomFinishedView: View {
    var capturedRoomCount: Int
    var onScanAnother: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Room captured")
                .font(.title.bold())
            Text("\(capturedRoomCount) room\(capturedRoomCount == 1 ? "" : "s") so far. "
                 + "Walk to the next room without closing the app so the rooms line up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button(action: onScanAnother) {
                Text("Scan another room").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: onFinish) {
                Text("Finish scan").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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
                .foregroundStyle(.secondary)
        }
        .padding(24)
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

            Label("\(artifacts.roomCount) room\(artifacts.roomCount == 1 ? "" : "s") captured",
                  systemImage: "square.split.bltr")

            Label(artifacts.usdz == nil ? "3D preview unavailable" : "3D preview saved",
                  systemImage: artifacts.usdz == nil ? "cube.transparent" : "cube.fill")
                .foregroundStyle(artifacts.usdz == nil ? .secondary : .primary)

            if let fallbackReason {
                Label(fallbackReason, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Text("The scan is a starting point, not the final map — you'll fix walls, "
                 + "doors and windows in the editor next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Surfaced so a tester can find the files to copy off the device for
            // schema/fixtures/scans/ (S1.4's handoff artifact).
            Text(artifacts.directory.lastPathComponent)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            Spacer()

            Button(action: onUse) {
                Text("Continue to editor").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: onRescan) {
                Text("Scan again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
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
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Scan interrupted").font(.title.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if capturedRoomCount > 0 {
                Text("Your \(capturedRoomCount) captured room\(capturedRoomCount == 1 ? "" : "s") "
                     + "\(capturedRoomCount == 1 ? "is" : "are") safe — retrying keeps them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onRetry) {
                Text("Try again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Cancel", action: onCancel)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
    }
}

struct ScanUnsupportedView: View {
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Scanning needs a LiDAR device")
                .font(.title2.bold())
            Text("Run on an iPhone/iPad Pro to capture a room. "
                 + "The editor works everywhere.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Back", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(24)
    }
}
