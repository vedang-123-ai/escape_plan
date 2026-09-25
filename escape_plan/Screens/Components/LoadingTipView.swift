//  LoadingTipView.swift
//  escape_plan — Loading screens (loading-tips)
//
//  A spinner and its label, plus — once the wait has lasted long enough to read something —
//  a rotating, cited prevention tip, like the hints on a game's loading screen. The slow
//  waits are real: a cold Render backend takes 30 s or more.
//
//  Tips come verbatim from the bundled corpus file (Resources/prevention_tips.json, kept
//  byte-identical to backend/corpus by scripts/check-tips-sync.py) and always show their
//  source. Order is LoadingTipRotator's job.

import SwiftUI

struct LoadingTipView: View {
    let label: String

    @State private var rotator: LoadingTipRotator
    @State private var currentTip: PreventionTip?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// Long enough that a fast load never flashes a tip it had no time to show.
    private static let firstTipDelay: Duration = .milliseconds(800)
    private static let rotateInterval: Duration = .seconds(7)

    /// Decoded once per launch. An unreadable file yields no tips, and the view is a plain
    /// spinner — never an uncited or invented one.
    private static let bundledTips: [PreventionTip] = {
        guard let url = Bundle.main.url(forResource: "prevention_tips", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let tips = try? PreventionTips.decode(from: data)
        else { return [] }
        return tips
    }()

    init(label: String, tips: [PreventionTip]? = nil) {
        self.label = label
        _rotator = State(initialValue: LoadingTipRotator(tips: tips ?? Self.bundledTips))
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ProgressView()
                Text(label)
                    .font(Theme.detail)
                    .foregroundStyle(Theme.supporting)
            }
            .accessibilityElement(children: .combine)

            if let tip = currentTip {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tip")
                        .sectionHeaderStyle()
                    Text(tip.text)
                        .font(Theme.cardBody)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Source: \(tip.cite)")
                        .font(Theme.detail)
                        .foregroundStyle(Theme.supporting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
                .id(tip.id)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await runTips() }
    }

    /// Cancelled with the view, so a finished load never leaves a timer writing to dead state.
    private func runTips() async {
        guard rotator.cycleLength > 0 else { return }
        try? await Task.sleep(for: Self.firstTipDelay)
        guard !Task.isCancelled else { return }
        advance()
        // VoiceOver users hear one tip; text changing under the cursor is disorienting.
        guard !voiceOverEnabled else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.rotateInterval)
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private func advance() {
        let next = rotator.next()
        if reduceMotion {
            currentTip = next
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { currentTip = next }
        }
    }
}

#Preview {
    LoadingTipView(label: "Scoring…")
}
