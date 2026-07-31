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
                              tint: Color(DollhousePalette.warningBadgeSevere))
        case .no_secondary_egress:
            RouteFindingStyle(title: "No second way out",
                              icon: "exclamationmark.triangle.fill",
                              tint: Color(DollhousePalette.warningBadge))
        case .blocked_opening:
            RouteFindingStyle(title: "Blocked doorway",
                              icon: "door.left.hand.closed",
                              tint: Color(DollhousePalette.warningBadge))
        }
    }
}

/// One finding: severity icon in a tinted well, titled kind + room chip, and the engine's
/// verbatim detail underneath.
struct RouteFindingCard: View {
    let finding: RouteFinding
    let roomName: String

    var body: some View {
        let style = RouteFindingStyle.of(finding.kind)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(style.tint)
                .frame(width: 30, height: 30)
                .background(style.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(style.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(roomName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                        .lineLimit(1)
                }
                // Verbatim from the engine — never paraphrased client-side.
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(style.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Quiet status row for when the engine flagged nothing in the current view.
struct RouteAllClearRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(Color(DollhousePalette.opening(kind: .door, isExit: true)))
            Text("No issues flagged for this view")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
