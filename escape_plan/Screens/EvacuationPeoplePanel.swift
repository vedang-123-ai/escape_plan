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
            line(journey.startLine, symbol: "figure.stand", tint: Theme.supporting)
            line(journey.passesLine, symbol: "arrow.forward", tint: Theme.routeInk)
            line(journey.exitLine,
                 symbol: journey.leavesThroughWindow ? "window.casement" : "door.left.hand.open",
                 tint: Theme.exitInk)
            line(journey.timeOutLine, symbol: "clock", tint: Theme.supporting)
            if journey.overtaken {
                // The ink is for the icon and the card's border only (Theme: safety inks label
                // the hazard system, they are not text colours); the words stay full-contrast.
                line(EvacuationJourney.overtakenLine, symbol: "flame.fill", tint: Theme.hazardInk,
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

    private func line(_ text: String, symbol: String, tint: Color,
                      textTint: Color = DS.bodyInk) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
            Text(text)
                .font(.caption)
                .foregroundStyle(textTint)
                .fixedSize(horizontal: false, vertical: true)
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
