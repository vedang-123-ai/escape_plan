//  EvacuationPeoplePanel.swift
//  Screens — "Who does what" in House's fire simulation dock (trim 2, 2026-10-03).
//
//  One card per person in the loaded timeline: where they start, the rooms they pass, the way
//  out they use, when they are outside, and a warning when the engine flagged them overtaken.
//  Someone the engine found no way out for has no track; their `no_viable_route` finding is
//  shown first, in the engine's own words, so the person in most danger is never missing.
//  Presentation only: the words come from `EvacuationJourney` (Editor/Core, unit-tested), which
//  narrates the engine's tracks and never computes a route.
//
//  Colours follow the safety guardrails: cool (route ink) for the way through, green (exit ink)
//  for the way out, warm (hazard ink) for the warning. Each card is one VoiceOver element.

import SwiftUI

struct EvacuationPeoplePanel: View {
    let journeys: [EvacuationJourney]
    var noWayOut: [RouteFinding] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who does what").sectionHeaderStyle()
            ForEach(noWayOut.indices, id: \.self) { i in
                NoWayOutCard(finding: noWayOut[i])
            }
            ForEach(journeys) { journey in
                EvacuationPersonCard(journey: journey)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("house.simulation.people")
    }
}

private struct EvacuationPersonCard: View {
    let journey: EvacuationJourney
    /// Icons grow with Dynamic Type so the text column stays aligned at every size.
    @ScaledMetric(relativeTo: .caption) private var iconWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(journey.personName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            line(journey.startLine, icon: .start, tint: Theme.supporting)
            line(journey.passesLine, icon: .passes, tint: Theme.routeInk)
            line(journey.exitLine, icon: journey.leavesThroughWindow ? .exitWindow : .exitDoor,
                 tint: Theme.exitInk)
            line(journey.timeOutLine, icon: .timeOut, tint: Theme.supporting)
            if journey.overtaken {
                // The ink is for the icon and the card's border only (Theme: safety inks label
                // the hazard system, they are not text colours); the words stay full-contrast.
                line(EvacuationJourney.overtakenLine, icon: .overtaken, tint: Theme.hazardInk,
                     textTint: Theme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(journey.overtaken ? Theme.hazardInk : Theme.border, lineWidth: Theme.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(journey.spokenSummary)
        .accessibilityIdentifier("house.simulation.person.\(journey.id)")
    }

    private func line(_ text: String, icon: PersonLineIcon, tint: Color,
                      textTint: Color = DS.bodyInk) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon.symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                // Never the SF Symbol's name (S53-5 read "figure.stand"): a real word if the icon
                // is ever reached on its own. The card itself reads as one element (`spokenSummary`).
                .accessibilityLabel(icon.spokenLabel)
            Text(text)
                .font(.caption)
                .foregroundStyle(textTint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The icon at the start of each line of a person's card, and what it is called aloud.
enum PersonLineIcon: CaseIterable {
    case start, passes, exitDoor, exitWindow, timeOut, overtaken

    var symbol: String {
        switch self {
        case .start: return "figure.stand"
        case .passes: return "arrow.forward"
        case .exitDoor: return "door.left.hand.open"
        case .exitWindow: return "window.casement"
        case .timeOut: return "clock"
        case .overtaken: return "flame.fill"
        }
    }

    var spokenLabel: String {
        switch self {
        case .start: return "Starts in"
        case .passes: return "Goes through"
        case .exitDoor: return "Leaves by a door"
        case .exitWindow: return "Leaves by a window"
        case .timeOut: return "Time to get out"
        case .overtaken: return "Warning"
        }
    }
}

/// A person the engine could not get out. The detail is the engine's sentence, verbatim (it
/// names the person and the start room); nothing is added but the heading.
private struct NoWayOutCard: View {
    let finding: RouteFinding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.caption)
                .foregroundStyle(Theme.hazardInk)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("No way out found")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(Theme.hazardInk, lineWidth: Theme.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Warning. No way out found. \(finding.detail)")
        .accessibilityIdentifier("house.simulation.noWayOut.\(finding.room_id)")
    }
}
