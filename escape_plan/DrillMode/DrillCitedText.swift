//  DrillCitedText.swift
//  escape_plan — S4.2 drill mode
//
//  The one place drill copy is rendered, so a cited claim can never accidentally be shown
//  without its citation. Copy is displayed verbatim, inline `[cite: id]` tags and all, with the
//  ids echoed as chips underneath — the AssistantScreen / DrillScreen precedent, where
//  grounding is the feature rather than noise.
//
//  Accessibility: the chips are decorative once the tags are already spoken as part of the
//  body, so the whole block is one VoiceOver element with the source ids named at the end
//  instead of a swipe-through row of monospaced fragments.

import SwiftUI

struct DrillCitedText: View {
    let text: String
    var font: Font = .subheadline

    private var citations: [String] { DrillInstructions.citationIDs(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(font)
                // No lineLimit: at the largest accessibility sizes this must wrap, not clip.
                .fixedSize(horizontal: false, vertical: true)
            if !citations.isEmpty {
                DrillCitationChips(ids: citations)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// Reads the claim, then names its sources — "[cite: nfpa-escape-planning]" spoken
    /// literally mid-sentence is unusable.
    private var spokenLabel: String {
        var spoken = text
        for id in citations {
            spoken = spoken.replacingOccurrences(of: "[cite: \(id)]", with: "")
        }
        spoken = spoken.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !citations.isEmpty else { return spoken }
        return spoken + " Source\(citations.count == 1 ? "" : "s"): "
            + citations.joined(separator: ", ") + "."
    }
}

/// Horizontal row of source-id chips. Scrolls rather than truncating so the ids stay legible
/// at accessibility text sizes.
struct DrillCitationChips: View {
    let ids: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in
                    Text(id)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sources: \(ids.joined(separator: ", "))")
    }
}
