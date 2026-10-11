//  RouteFindingViews.swift
//  escape_plan
//
//  Presentation for the routing engine's findings (UI craft pass, Jul 2026). The engine's
//  `detail` string is rendered VERBATIM — the client never writes its own safety judgments.
//  What this file adds is presentation only: a short title naming the machine `kind`, a
//  severity tier drawn from the shared palette, and the affected room as a chip, so a judge
//  can triage the list at a glance instead of parsing three lines of red caption text.

import SwiftUI

/// Maps a finding kind to its presentation. Severity colors come from `DollhousePalette`
/// (the same colors the 3D warning badges use), so the dock and the scene agree.
struct RouteFindingStyle {
    let title: String
    let icon: String
    let tint: Color

    static func of(_ kind: RouteFinding.FindingKind) -> RouteFindingStyle {
        switch kind {
        case .no_viable_route:
            // The worst finding the engine emits — matches the severe badge in the scene.
            RouteFindingStyle(title: "No way out",
                              icon: "xmark.octagon.fill",
                              tint: Theme.warningBadgeSevere)
        case .no_secondary_egress:
            RouteFindingStyle(title: "No second way out",
                              icon: "exclamationmark.triangle.fill",
                              tint: Theme.warningBadge)
        case .blocked_opening:
            RouteFindingStyle(title: "Blocked doorway",
                              icon: "door.left.hand.closed",
                              tint: Theme.warningBadge)
        case .narrows_route:
            // The mildest finding the engine emits: the way out still works, it is
            // just tight. Deliberately shares `warningBadge` with the tiers above
            // rather than introducing a third colour — the White Model overhaul
            // removed exactly that kind of proliferation, and route orange is
            // reserved for lit routes. Icon and title carry the distinction.
            RouteFindingStyle(title: "Tight squeeze",
                              icon: "arrow.down.right.and.arrow.up.left",
                              tint: Theme.warningBadge)
        case .no_viable_safe_room:
            RouteFindingStyle(title: "No safe room",
                              icon: "exclamationmark.triangle.fill",
                              tint: Theme.warningBadgeSevere)
        case .no_cover_in_room:
            RouteFindingStyle(title: "No cover",
                              icon: "exclamationmark.triangle.fill",
                              tint: Theme.warningBadge)
        case .unknown:
            // A kind newer than this build. The engine's `detail` still reads fine, so
            // show the warning rather than hiding a real safety finding behind a
            // version mismatch. Generic title, cautious (non-severe) tint.
            RouteFindingStyle(title: "Safety warning",
                              icon: "exclamationmark.triangle.fill",
                              tint: Theme.warningBadge)
        }
    }

    /// The evacuation simulation's one finding kind: the engine's `overtaken_by_hazard` flag.
    ///
    /// Deliberately the SEVERE tier — the same tier as `no_viable_route` — because it is the
    /// same class of result: the engine is telling us this person does not get out ahead of
    /// the modeled fire. Giving it a gentler colour than the routing engine's worst finding
    /// would be editing the engine's answer with presentation.
    static let overtakenByHazard = RouteFindingStyle(
        title: "Hazard reaches them first",
        icon: "flame.fill",
        tint: Theme.warningBadgeSevere)
}

/// The shared chassis every finding is drawn in: severity icon in a tinted well, a titled
/// kind with a room/person chip, and a detail line underneath.
///
/// Extracted so the routing findings and the evacuation simulation's findings are literally
/// the same component rather than two that look alike today and drift apart in a month.
struct FindingCard: View {
    let style: RouteFindingStyle
    /// The chip on the trailing edge — a room name, or a person's name for an occupant finding.
    let chip: String
    /// The supporting line. For engine findings this is the engine's string, verbatim.
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.tint)
                .frame(width: 30, height: 30)
                .background(style.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                // At the accessibility text sizes the title and the chip cannot share a line;
                // ViewThatFits drops them onto two rather than truncating either.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        titleText
                        Spacer(minLength: 4)
                        chipText
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        titleText
                        chipText
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(style.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.title). \(chip). \(detail)")
    }

    private var titleText: some View {
        Text(style.title)
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chipText: some View {
        Text(chip)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One routing-engine finding. The `detail` inside is the engine's own string, rendered
/// verbatim — the client never paraphrases or softens a safety judgment.
struct RouteFindingCard: View {
    let finding: RouteFinding
    let roomName: String

    var body: some View {
        FindingCard(style: RouteFindingStyle.of(finding.kind),
                    chip: roomName,
                    detail: finding.detail)
    }
}

/// One occupant the engine flagged `overtaken_by_hazard` in an evacuation timeline.
///
/// Same component, same severity vocabulary, same tier as the routing engine's worst finding —
/// because it IS a finding, not an error state and not a rendering hiccup. It is shown
/// whenever the flag is set, never suppressed to keep the animation comfortable.
///
/// On the wording: the detail line here is written client-side, unlike `RouteFindingCard`.
/// That is allowed only because it states the engine's numbers back — the boolean it set, the
/// egress time it computed, the room it started the fire in — and makes no safety judgment,
/// gives no advice, and predicts no outcome. If the backend attaches its own `findings` to the
/// timeline, those render through `RouteFindingCard` verbatim alongside these.
struct OvertakenFindingCard: View {
    let track: OccupantTrack
    /// Human name of the room the fire starts in, resolved by the caller.
    let originRoomName: String

    var body: some View {
        FindingCard(
            style: .overtakenByHazard,
            chip: track.profile_name,
            detail: "In this simulation the modeled fire from \(originRoomName) reaches a room "
                  + "on \(track.profile_name)'s way out before they clear it. Modeled time "
                  + "out: \(EvacuationPlaybackModel.timeLabel(track.egress_time_s)).")
    }
}

/// Quiet status row for when the engine flagged nothing in the current view.
struct RouteAllClearRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.subheadline)
                // Theme.exitInk, not the renderer's raw exitGreen: the pad colour is tuned to
                // sit on the white model, and on a dark grouped row it drops to 3.42:1.
                .foregroundStyle(Theme.exitInk)
            Text("No issues flagged for this view")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
