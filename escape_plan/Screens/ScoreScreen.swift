// ScoreScreen.swift
// S3.5 preparedness score: overall 0–100 score, the per-peril sub-scores and the single
// largest deduction. Pushed from HomeScreen for the ACTIVE home (not a tab — a sixth tab would
// overflow into iOS's "More" list; see docs/decisions.md).
//
// No score math happens on this device, and since the audit (2026-09-25) no score request
// either: this screen reads `ReadinessStore`, the one owner of the active home's /score result.
// It used to load its own copy of the home and POST /score itself, so Home and Score could show
// two different numbers for one home. Refresh asks the store to re-score; the Home card, the
// Tasks tab and this screen then update together.

//
// Accessibility (lane D1): the ring is the app's most colour-dependent surface, so it does
// three things it didn't before — it says its band in words ("Some gaps"), it scales its
// geometry with Dynamic Type and drops the ring entirely at accessibility sizes, and it reads
// as ONE VoiceOver sentence instead of "75", "of 100", and an unlabelled circle.

import SwiftUI

struct ScoreScreen: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(ReadinessStore.self) private var readiness
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        content
            .dsPage()
            .navigationTitle(readiness.breakdown?.home_name ?? "Score")
            .navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .snappy, value: readiness.breakdown?.score)
    }

    @ViewBuilder
    private var content: some View {
        if readiness.needsDraftReview {
            // An unreviewed AI draft has no score (AUD-023).
            ScrollView {
                DraftReviewNotice().padding(DS.pagePadding)
            }
        } else if let breakdown = readiness.breakdown {
            scoreList(breakdown)
        } else if readiness.isScoring {
            LoadingTipView(label: "Scoring…", accessibilityText: "Working out your preparedness score.")
        } else if let failure = readiness.scoreFailure {
            ContentUnavailableView {
                // A home file that will not open is not "couldn't get your score" — nothing
                // was asked of the server.
                Label(failure.kind == .localData ? "Couldn't open this home" : "Couldn't get your score",
                      systemImage: failure.symbol)
            } description: {
                VStack(spacing: 10) {
                    Text(failure.message)
                    if failure.isOfflineFlavoured {
                        OfflineCapabilityNote()
                            .frame(maxWidth: 420)
                    }
                }
            } actions: {
                // No Retry on a 502: the server needs an operator, and a button that provably
                // cannot work is worse than no button.
                if failure.isRetryable {
                    Button("Try Again") { refresh() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Try again")
                        .accessibilityHint("Asks the server for your preparedness score again.")
                }
            }
        } else if readiness.activeHomeID == nil {
            ContentUnavailableView("No home yet", systemImage: "house",
                                   description: Text("Add a home on the Home tab to see its score."))
        } else {
            ProgressView()
                .accessibilityLabel("Loading your preparedness score.")
        }
    }

    private func scoreList(_ breakdown: ScoreBreakdown) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                scoreHeader(breakdown)
                    .padding(.top, 8)

                if let failure = readiness.scoreFailure {
                    // One banner, one classifier. The stale-score caveat is spoken up front so
                    // VoiceOver users hear *why* the number below might be wrong.
                    VStack(alignment: .leading, spacing: 8) {
                        BackendFailureBanner(failure: failure,
                                             retry: failure.isRetryable ? { refresh() } : nil)
                            .accessibilityLabel("This score may be out of date. \(failure.message)")
                        if failure.isOfflineFlavoured {
                            OfflineCapabilityNote()
                        }
                    }
                    .padding(.horizontal, DS.pagePadding)
                    .padding(.top, 8)
                }

                // S6.7: the new composite model returns 0 or 1 components — the single
                // largest unresolved scoring deduction across all perils — not a fixed set of
                // five, so this whole block (header, card, explainer) is conditional on there
                // being one to show at all.
                if !breakdown.components.isEmpty {
                    Text("Largest Deduction")
                        .sectionHeaderStyle()
                        .padding(.horizontal, DS.pagePadding)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                    VStack(spacing: 0) {
                        ForEach(Array(breakdown.components.enumerated()), id: \.element.id) { index, component in
                            if index > 0 { Divider().padding(.leading, 16) }
                            componentRow(component)
                        }
                    }
                    .dsCard(padding: nil)
                    .padding(.horizontal, DS.pagePadding)

                    Text("Points come from the deterministic engine's audit of your home — alarms, routes, findings and practice. The assistant doesn't influence the score.")
                        .font(.footnote)
                        .foregroundStyle(DS.supporting)
                        .padding(.horizontal, DS.pagePadding)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Score header

    /// Below accessibility sizes the score is the design's 72pt hero number; at AX1 and above
    /// it becomes the scaling `Theme.metric` with a bar under it — the *shape* gives way, not
    /// the text.
    private var usesRing: Bool { dynamicTypeSize < .accessibility1 }

    private func scoreHeader(_ breakdown: ScoreBreakdown) -> some View {
        VStack(spacing: 10) {
            scoreNumber(breakdown)
                .padding(.top, 6)
            if !usesRing {
                // At accessibility sizes the number alone can't carry the proportion, so a
                // bar sits under it.
                ProgressView(value: Double(breakdown.score), total: 100)
                    .tint(ReadinessStore.band(for: breakdown.score).tint)
                    .padding(.horizontal, 40)
            }
            bandLabel(breakdown.score)

            HStack(spacing: 24) {
                subScoreView(label: "Fire", score: breakdown.sub_scores["fire"] ?? 0,
                            basis: ScoreBasisLabel.label(for: "fire", basis: breakdown.basis))
                subScoreView(label: "Earthquake", score: breakdown.sub_scores["earthquake"] ?? 0,
                            basis: ScoreBasisLabel.label(for: "earthquake", basis: breakdown.basis))
                subScoreView(label: "Severe Weather", score: breakdown.sub_scores["severe_weather"] ?? 0,
                            basis: ScoreBasisLabel.label(for: "severe_weather", basis: breakdown.basis))
            }
            .padding(.top, 8)
            // Honest tiering, never blurred (CLAUDE.md "Scope lock"): fire is fully
            // code-quantified; earthquake and tornado are FEMA/NOAA-grounded readiness
            // modules. Omitted, not a placeholder, when a server predates S11.2.
            if breakdown.basis != nil {
                Text("Fire is measured against code thresholds. Earthquake and severe weather are FEMA/NOAA-grounded guidance.")
                    .font(.caption2)
                    .foregroundStyle(DS.supporting)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.top, 2)
            }

            if readiness.isScoring {
                ProgressView()
                    .accessibilityLabel("Updating your score.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        // One sentence, not five fragments. VoiceOver reads e.g.
        // "62 out of 100. Preparedness score for the Miller House. Some gaps to close."
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(breakdown.score) out of 100. Preparedness score for "
                            + "\(breakdown.home_name). \(ReadinessStore.band(for: breakdown.score).title).")
        .accessibilityValue(readiness.isScoring ? "Updating" : "")
        .accessibilityAddTraits(.isSummaryElement)
    }

    private func scoreNumber(_ breakdown: ScoreBreakdown) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(breakdown.score)")
                // The design's 72pt hero number below accessibility sizes; `Theme.metric`
                // (a scaling `.largeTitle`) once the user has asked for large text.
                .font(usesRing ? .system(size: 72, weight: .bold, design: .rounded) : Theme.metric)
                .kerning(usesRing ? -2 : 0)
                .foregroundStyle(DS.ink)
                .contentTransition(reduceMotion
                                   ? .identity
                                   : .numericText(value: Double(breakdown.score)))
                .minimumScaleFactor(0.6)
            Text("of 100")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DS.supporting)
        }
        .multilineTextAlignment(.center)
    }

    /// SC 1.4.1: the band must not be carried by the ring's colour alone. A glyph and a phrase
    /// say the same thing to someone who can't tell one band's colour from another's. The band
    /// itself is `ReadinessStore.band(for:)` — the same one the Home card uses.
    private func bandLabel(_ score: Int) -> some View {
        let band = ReadinessStore.band(for: score)
        return Label(band.title, systemImage: band.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(band.textTint)
            .accessibilityHidden(true)  // already spoken by the header's combined label
    }

    /// One of the three S6.7 peril sub-scores, shown under the composite ring. `basis` is
    /// S11.2's evidence tier (ScoreBasisLabel maps it from `ScoreBreakdown.basis`) — nil on a
    /// server that predates it, in which case the row just omits the line rather than
    /// guessing.
    private func subScoreView(label: String, score: Int, basis: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.headline)
                .foregroundStyle(ReadinessStore.band(for: score).textTint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(DS.supporting)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
            if let basis {
                Text(basis)
                    // Dynamic Type (audit 2026-09-25): a fixed 9 pt never grew with the user's
                    // text size. `.caption2` is the smallest style that does.
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .kerning(0.3)
                    .foregroundStyle(DS.supporting)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 80)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) sub-score is \(score)" + (basis.map { ", \($0)" } ?? ""))
    }

    // MARK: - Largest deduction

    /// The backend sends 0 or 1 component: the single largest unresolved deduction, as
    /// `earned_points = 0, max_points = X` (S6.7). Drawn as a progress bar that was always an
    /// empty "0 / X" (audit 2026-09-25); it is what it is — a title and what it costs.
    private func deduction(_ component: ScoreComponent) -> Double {
        max(0, component.max_points - component.earned_points)
    }

    private func componentRow(_ component: ScoreComponent) -> some View {
        let cost = "−\(formatted(deduction(component))) points"
        return VStack(alignment: .leading, spacing: 6) {
            // At accessibility sizes the title and the cost cannot share a line without one of
            // them truncating, so the row stacks instead of shrinking either.
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(component.label).font(.body.weight(.medium)).foregroundStyle(DS.ink)
                    Spacer()
                    Text(cost)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.warning)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.label).font(.body.weight(.medium)).foregroundStyle(DS.ink)
                    Text(cost)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.warning)
                }
            }
            Text(component.detail)
                .font(.subheadline)
                .foregroundStyle(DS.supporting)
            WhyDisclosure(title: component.label, rationale: component.rationale)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(component.label). Costs \(formatted(deduction(component))) points. "
                            + "\(component.detail)")
    }

    /// "30" not "30.0", but "2.14" for fractional per-item values like 15/7.
    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // MARK: - Data

    /// Re-POSTs /score through the shared store, so every screen showing this home updates.
    private func refresh() {
        readiness.rescore(api: apiClient)
    }
}

#Preview {
    NavigationStack {
        ScoreScreen()
    }
    .environment(APIClient())
    .environment(ReadinessStore(library: HomeLibrary(store: HomeDocumentStore.launchStore().store)))
}

/// The "Why" reveal, with a selection notch — `DisclosureGroup`'s own toggle is silent.
private struct WhyDisclosure: View {
    /// What the "Why" is about, so VoiceOver does not hear a bare "Why" with no subject.
    let title: String
    let rationale: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(rationale)
                .font(.footnote)
                .foregroundStyle(DS.supporting)
                .padding(.top, 4)
        } label: {
            Text("Why")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .accessibilityLabel("Why: \(title)")
        }
        .tint(Theme.accentText)
        .onChange(of: isExpanded) { Haptics.selection() }
        .accessibilityHint("Opens to explain how these points are worked out.")
    }
}
