//  BackendFailureBanner.swift
//  Screens — the single notice component for a backend problem.
//
//  One banner, driven by `BackendFailure`, so every screen reports a failure the same way and
//  a Retry button only appears when retrying can actually help.

import SwiftUI

struct BackendFailureBanner: View {
    var failure: BackendFailure
    /// Offered only when `failure.isRetryable`.
    var retry: (() -> Void)?
    /// Offered only when `failure.suggestsSettings` — a 502 is not a settings problem.
    var openSettings: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: failure.symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(failure.message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if failure.isRetryable, let retry {
                Button("Retry", action: retry)
                    .font(.caption.bold())
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("failure.retry")
            }
            if failure.suggestsSettings, let openSettings {
                Button("Settings", action: openSettings)
                    .font(.caption.bold())
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("failure.settings")
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(failure.message)
    }

    /// Only a genuine fault gets the warning red. Offline and cached-data notices are states,
    /// not errors, and colouring them like errors makes the app feel broken when it is
    /// working exactly as designed.
    private var tint: Color {
        switch failure.kind {
        case .offline: return .secondary
        case .unauthorized, .rejectedInput: return Color(DollhousePalette.warningBadge)
        case .aiUnavailable, .serverBusy, .server: return Color(DollhousePalette.warningBadge)
        }
    }
}
