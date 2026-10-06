//  BackendFailureBanner.swift
//  Screens — the single notice component for a backend problem.
//
//  One banner, driven by `BackendFailure`, so every screen reports a failure the same way and
//  a Retry button only appears when retrying can actually help.
//
//  A caller may let it go away on its own (2026-10-02, Anish: "they should disappear after some
//  time"): with `autoHides`, it fades after `autoHideDelay` and has a close button. Opt-in, because
//  on most screens the banner holds the only Retry, and hiding it leaves an empty card the user
//  cannot recover from. House opts in: its banners float over the 3D model, a room tap re-runs
//  the simulation, and the dock carries its own routes Retry. Even then it stays up for a fix in
//  Settings, an offline or saved-routes notice (it says what is on screen is not live), and under
//  VoiceOver. A different failure shows it again.

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
    /// Fade after `autoHideDelay` and offer a close button. Only where hiding loses nothing the
    /// user needs: see the file header.
    var autoHides = false

    @State private var showingSettings = false
    @State private var isHidden = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasActions: Bool { (failure.isRetryable && retry != nil) || failure.suggestsSettings || autoHides }

    static let autoHideDelay: Duration = .seconds(8)

    /// Whether this failure fades on its own, for a caller that opted in. Not when the fix is in
    /// Settings (the banner is the only thing saying why nothing works), and not for an offline
    /// notice, which is what tells the user the routes on screen are saved rather than live.
    static func hidesAutomatically(_ failure: BackendFailure, voiceOverRunning: Bool) -> Bool {
        !failure.suggestsSettings && failure.kind != .offline && !voiceOverRunning
    }

    /// A cancellation draws nothing: nothing went wrong, and a banner would say otherwise.
    static func rendersBanner(for failure: BackendFailure) -> Bool { !failure.isSilent }

    var body: some View {
        // The reset, the timer and the Settings sheet hang off this outer view, which stays in the
        // tree while the banner is hidden. Inside `banner` they left with it, so a later failure
        // assigned in place never showed (review, 2026-10-02).
        Group {
            if !isHidden, Self.rendersBanner(for: failure) { banner }
        }
        .onChange(of: failure.message) { isHidden = false }
        .task(id: failure.message) {
            guard autoHides,
                  Self.hidesAutomatically(failure, voiceOverRunning: UIAccessibility.isVoiceOverRunning)
            else { return }
            try? await Task.sleep(for: Self.autoHideDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { isHidden = true }
        }
        .sheet(isPresented: $showingSettings) { SettingsScreen() }
    }

    /// At the accessibility text sizes the buttons move under the message: side by side they
    /// squeezed it into a column one syllable wide over House's model (S11.57, found at XXXL).
    private var banner: some View {
        let large = typeSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                           : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: failure.symbol)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Text(failure.message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hasActions { HStack(alignment: .firstTextBaseline, spacing: 10) { actions } }
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
        .transition(.opacity)
    }

    @ViewBuilder
    private var actions: some View {
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
        if autoHides {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isHidden = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityIdentifier("failure.dismiss")
            .accessibilityLabel("Dismiss")
        }
    }

    /// Only a genuine fault gets the warning red. Offline and cached-data notices are states,
    /// not errors, and colouring them like errors makes the app feel broken when it is
    /// working exactly as designed.
    private var tint: Color {
        switch failure.kind {
        case .offline, .timedOut, .cancelled: return .secondary
        case .unauthorized, .rejectedInput, .localData: return Color(DollhousePalette.warningBadge)
        case .aiUnavailable, .serverBusy, .server, .serverTimedOut, .appServerMismatch, .responseCutOff:
            return Color(DollhousePalette.warningBadge)
        }
    }
}

/// The honest inventory of what this app can and cannot do with the network off.
///
/// It exists because "offline" was being reported as a failure and nothing else — which reads
/// as "the app is broken" when in fact the entire deterministic half is local. Everything in
/// `worksOffline` is a real capability with no `APIClient` anywhere in its path (the editor and
/// `HomeModelStore`, `HomeDocumentStore`, `EscapePlanExporter`); everything in
/// `needsServer` genuinely round-trips to the backend and is never faked client-side.
///
/// Shown alongside a `BackendFailureBanner` whose failure is offline-flavoured. Collapsed by
/// default so it informs without shouting.
struct OfflineCapabilityNote: View {
    @State private var isExpanded = false

    // The practice drill and its log left this list in trim 2 (2026-10-03): the drill is now the
    // fire simulation, which needs the server (`/evacuate`).
    static let worksOffline = "the 3D editor, your saved homes, and the printable escape plan"
    static let needsServer = "new escape routes, converting a scan, importing a plan, the "
        + "preparedness score, the fire drill simulation, and the assistant"

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
