//  LoadingTipView.swift
//  escape_plan — Loading screens (loading-tips)
//
//  SwiftUI view for showing rotating prevention tips while a load is in progress.
//  Replaces bare ProgressView(label) calls on slow operations. Shows a tip after ~0.8 s,
//  rotates every ~7 s with a crossfade, and respects Reduce Motion and VoiceOver.

import SwiftUI

struct LoadingTipView: View {
    let label: String
    let tips: [PreventionTip]

    @State private var rotator: LoadingTipRotator
    @State private var currentTip: PreventionTip?
    @State private var hasWaitedLongEnough = false
    @State private var rotationTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private let showTipDelay: TimeInterval = 0.8
    private let rotateInterval: TimeInterval = 7.0

    init(label: String, tips: [PreventionTip]) {
        self.label = label
        self.tips = tips
        _rotator = State(initialValue: LoadingTipRotator(tips: tips))
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.supporting)

            Text(label)
                .font(Theme.detail)
                .foregroundStyle(Theme.supporting)

            if hasWaitedLongEnough, let tip = currentTip {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tip")
                        .font(Theme.sectionHeader)
                        .foregroundStyle(Theme.supporting)
                        .textCase(.uppercase)

                    Text(tip.text)
                        .font(Theme.cardBody)
                        .foregroundStyle(DS.bodyInk)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Source: \(tip.cite)")
                        .font(Theme.detail)
                        .foregroundStyle(Theme.supporting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            // Show spinner immediately, tip after delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + showTipDelay) {
                hasWaitedLongEnough = true
                advanceTip()
                if !voiceOverEnabled {
                    startRotation()
                }
            }
        }
        .onDisappear {
            // Stop rotation task on exit.
            rotationTask?.cancel()
        }
    }

    private func advanceTip() {
        let nextTip = rotator.next()
        if reduceMotion {
            currentTip = nextTip
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentTip = nextTip
            }
        }
    }

    private func startRotation() {
        rotationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(rotateInterval * 1_000_000_000))
                if !Task.isCancelled {
                    advanceTip()
                }
            }
        }
    }
}

#Preview {
    let sampleTips = [
        PreventionTip(
            id: "fire-meeting-place",
            peril: .fire,
            topic: "escape-plan",
            text: "Pick one meeting place outside, a safe distance from the home.",
            cite: "nfpa-1",
            audience: .everyone
        ),
        PreventionTip(
            id: "fire-two-ways-out",
            peril: .fire,
            topic: "escape-plan",
            text: "Find two ways out of every room.",
            cite: "nfpa-2",
            audience: .everyone
        ),
        PreventionTip(
            id: "earthquake-safety",
            peril: .earthquake,
            topic: "during-earthquake",
            text: "Drop, cover, and hold on during an earthquake.",
            cite: "usgs-1",
            audience: .everyone
        ),
    ]

    VStack {
        Text("Scoring…")
            .padding()

        LoadingTipView(label: "Scoring…", tips: sampleTips)
            .frame(maxHeight: 400)
    }
}
