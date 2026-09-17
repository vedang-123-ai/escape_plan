//  SyncStatusBadge.swift
//  escape_plan — S8.4 cloud sync
//
//  The one piece of chrome that says whether this device and the user's account agree.
//
//  Two rules it is built around:
//
//  * **Sync is never a wall.** The app is local-first: every home, route and score works with
//    no account and no connection, exactly as it did before S8. So a failure here is a small
//    amber glyph and a sentence on tap — never a modal, never a blocked screen, and never red
//    unless the user has to do something about it.
//  * **No new colours.** `Theme` is the semantic scale (see CLAUDE.md). Synced is
//    `accentText`, a partial failure is `caution`, a dead session is `warning`, and
//    signed-out is `supporting`.

import SwiftUI

struct SyncStatusBadge: View {
    @Environment(SyncManager.self) private var sync

    /// Tapping asks for a sync and, when there is something to say, reveals the detail line.
    @State private var isShowingDetail = false

    var body: some View {
        Button {
            Haptics.press()
            // Dismissing the detail must not fire another sync — a second tap is the user
            // closing a popover, not asking for anything.
            let opening = !isShowingDetail
            isShowingDetail = opening
            if opening { Task { await sync.syncIfSignedIn() } }
        } label: {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                // The spinner is the icon, not a second element beside it — a badge that
                // changes width mid-sync nudges the toolbar around.
                .symbolEffect(.pulse, isActive: isSyncing)
        }
        .accessibilityLabel("Sync status")
        .accessibilityValue(spokenStatus)
        .accessibilityHint("Double tap to sync now.")
        .popover(isPresented: $isShowingDetail) {
            detail
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(headline, systemImage: symbol)
                .font(Theme.sectionHeader)
                .foregroundStyle(tint)
            if let sentence {
                Text(sentence)
                    .font(Theme.detail)
                    .foregroundStyle(Theme.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: 280, alignment: .leading)
    }

    // MARK: - Status → presentation

    private var isSyncing: Bool { sync.status == .syncing }

    private var symbol: String {
        // Checked before the status, because signing out is exactly what a rejected token
        // causes — so `.signedOut` would otherwise hide the reason for it.
        if sync.needsReauthentication { return "person.crop.circle.badge.exclamationmark" }
        switch sync.status {
        case .signedOut: return "icloud.slash"
        case .idle: return "icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced(_, let outcome):
            return outcome.isClean ? "checkmark.icloud" : "exclamationmark.icloud"
        case .failed(let failure):
            return failure.symbol
        }
    }

    private var tint: Color {
        if sync.needsReauthentication { return Theme.warning }
        switch sync.status {
        case .signedOut, .idle, .syncing: return Theme.supporting
        case .synced(_, let outcome): return outcome.isClean ? Theme.accentText : Theme.caution
        case .failed(let failure):
            // Only a dead session needs the user to DO something; everything else resolves on
            // its own and does not deserve the colour reserved for "act now".
            return failure.requiresReauthentication ? Theme.warning : Theme.caution
        }
    }

    private var headline: String {
        if sync.needsReauthentication { return "Sign in again" }
        switch sync.status {
        case .signedOut: return "Not syncing"
        case .idle: return "Ready to sync"
        case .syncing: return "Syncing…"
        case .synced(_, let outcome):
            if !outcome.conflicts.isEmpty { return "Synced — one version won" }
            if outcome.skippedOtherAccount > 0 && outcome.isClean { return "Synced yours" }
            return outcome.isClean ? "Synced" : "Partly synced"
        case .failed: return "Sync problem"
        }
    }

    private var sentence: String? {
        if sync.needsReauthentication {
            return "Your session expired, so you've been signed out. Your homes are still on "
                 + "this device — sign in again to keep them syncing."
        }
        switch sync.status {
        case .signedOut:
            return "Your homes are saved on this device. Sign in to keep them on your account "
                 + "and on your other devices."
        case .idle:
            return "Tap to sync this device with your account."
        case .syncing:
            return nil
        case .synced(let at, let outcome):
            // Conflicts first: a replaced home is the thing the user most needs to hear
            // about, and it is the one that looks like success if nobody says otherwise.
            if !outcome.conflicts.isEmpty {
                let count = outcome.conflicts.count
                let noun = count == 1 ? "home was" : "homes were"
                return "\(count) \(noun) edited on another device too, so that version is now "
                     + "the main one. What was on this device is kept alongside it, named "
                     + "\"(this device)\"."
            }
            // Homes left behind because they belong to someone else who used this phone. Said
            // plainly: the alternative is a user who thinks everything is backed up and finds
            // out otherwise when they replace the device.
            if outcome.skippedOtherAccount > 0 && outcome.failures.isEmpty {
                let count = outcome.skippedOtherAccount
                let noun = count == 1 ? "home" : "homes"
                return "\(count) \(noun) on this device belong to a different account, so "
                     + "they weren't added to yours. They're still here and still work."
            }
            if !outcome.failures.isEmpty {
                let count = outcome.failures.count
                let noun = count == 1 ? "home" : "homes"
                // Name the specific reason when every failure shares one — "1 home didn't
                // sync" with no explanation is the kind of message people learn to ignore.
                let shared = Set(outcome.failures.map(\.failure.message))
                let why = shared.count == 1 ? " \(shared.first ?? "")" : ""
                return "\(count) \(noun) didn't sync.\(why)"
            }
            return "Last synced \(Self.timeFormatter.string(from: at))."
                 + (outcome.changed > 0 ? " \(changeSummary(outcome))" : "")
        case .failed(let failure):
            return failure.message
        }
    }

    private func changeSummary(_ outcome: SyncOutcome) -> String {
        var parts: [String] = []
        if outcome.pushed > 0 { parts.append("\(outcome.pushed) sent") }
        if outcome.pulled > 0 { parts.append("\(outcome.pulled) received") }
        return parts.joined(separator: ", ") + "."
    }

    private var spokenStatus: String {
        [headline, sentence].compactMap { $0 }.joined(separator: ". ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
