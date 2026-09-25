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
    ///
    /// Leave this nil and the banner presents `SettingsScreen` in a sheet itself. Every call
    /// site passed nil, so a 401 said "check it in Settings" and then offered no way to get
    /// there — on a fresh install, where the bearer token is genuinely missing, that is the
    /// first thing a user hits. A screen with a better destination can still pass its own
    /// closure; the default just stops the advice from being a dead end.
    var openSettings: (() -> Void)?

    @State private var showingSettings = false

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
                    .foregroundStyle(Theme.accentText)
                    .minimumTapTarget()
                    .accessibilityIdentifier("failure.retry")
                    .accessibilityLabel("Try again")
            }
            if failure.suggestsSettings {
                Button("Settings") {
                    if let openSettings { openSettings() } else { showingSettings = true }
                }
                .font(.caption.bold())
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accentText)
                .minimumTapTarget()
                .accessibilityIdentifier("failure.settings")
                .accessibilityLabel("Open Settings")
                .accessibilityHint("Check the server address and access token.")
            }
        }
        .padding(12)
        .glassPanel(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(failure.message)
        // A banner that appears while VoiceOver focus is elsewhere is otherwise silent: the
        // user hears nothing went wrong (audit 2026-09-25). Announce it once when it appears,
        // and again if a different failure replaces it in place.
        .onAppear { AccessibilityNotification.Announcement(failure.message).post() }
        .onChange(of: failure.message) { _, message in
            AccessibilityNotification.Announcement(message).post()
        }
        .sheet(isPresented: $showingSettings) { SettingsScreen() }
    }

    /// Only a genuine fault gets the warning red. Offline and cached-data notices are states,
    /// not errors, and colouring them like errors makes the app feel broken when it is
    /// working exactly as designed.
    private var tint: Color {
        switch failure.kind {
        case .offline: return .secondary
        case .unauthorized, .rejectedInput, .localData: return Color(DollhousePalette.warningBadge)
        case .aiUnavailable, .serverBusy, .server: return Color(DollhousePalette.warningBadge)
        }
    }
}

/// The honest inventory of what this app can and cannot do with the network off.
///
/// It exists because "offline" was being reported as a failure and nothing else — which reads
/// as "the app is broken" when in fact the entire deterministic half is local. Everything in
/// `worksOffline` is a real capability with no `APIClient` anywhere in its path (the editor and
/// `HomeModelStore`, `HomeDocumentStore`, `DrillLogStore`, `EscapePlanExporter`); everything in
/// `needsServer` genuinely round-trips to the backend and is never faked client-side.
///
/// Shown alongside a `BackendFailureBanner` whose failure is offline-flavoured. Collapsed by
/// default so it informs without shouting.
struct OfflineCapabilityNote: View {
    @State private var isExpanded = false

    static let worksOffline = "the 3D editor, your saved homes, the practice drill and its "
        + "log, and the printable escape plan"
    static let needsServer = "new escape routes, converting a scan, importing a plan, the "
        + "preparedness score, the fire simulation, and the assistant"

    private static let spoken = "Works without a connection: \(worksOffline). "
        + "Needs the server: \(needsServer)."

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Works without a connection: \(Self.worksOffline).",
                      systemImage: "checkmark.circle")
                Label("Needs the server: \(Self.needsServer).",
                      systemImage: "antenna.radiowaves.left.and.right")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            // Without this every line truncates to one line at accessibility text sizes.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.spoken)
        } label: {
            Text("What still works offline")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        // The chevron alone is well under 44pt; the whole row is the target either way, but
        // this guarantees the minimum on the smallest text sizes (SC 2.5.8).
        .minimumTapTarget()
        .accessibilityLabel("What still works offline")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Lists which parts of the app need the server and which don't.")
        .accessibilityIdentifier("offline.capabilities")
    }
}
