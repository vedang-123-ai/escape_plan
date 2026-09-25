// ScoreScreen.swift
// S3.5 preparedness score: overall 0–100 score, the five-component weighted breakdown,
// and the actionable checklist. Pushed per-home from HomeScreen (not a tab — the score is
// per-home data, and a sixth tab would overflow into iOS's "More" list; see docs/decisions.md).
//
// No score math happens on this device. Every toggle persists the checklist state locally
// (ChecklistStateStore) and re-POSTs /score; the displayed number and breakdown are always
// the backend's, so they match docs/preparedness-score-weights.md by construction.

//
// Accessibility (lane D1): the ring is the app's most colour-dependent surface, so it does
// three things it didn't before — it says its band in words ("Some gaps"), it scales its
// geometry with Dynamic Type and drops the ring entirely at accessibility sizes, and it reads
// as ONE VoiceOver sentence instead of "75", "of 100", and an unlabelled circle.

import SwiftUI

struct ScoreScreen: View {
    let homeID: String

    @Environment(APIClient.self) private var apiClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var home: HomeModel?
    @State private var breakdown: ScoreBreakdown?
    @State private var checklistState: [String: Bool] = [:]
    @State private var isLoading = false
    @State private var isUpdating = false
    /// The whole classified failure, not `.message`. Flattening it here was how a 502 ("no
    /// credit — an operator must act") and a 503 ("busy — try again") ended up rendering the
    /// same sentence with the same Retry button.
    @State private var failure: BackendFailure?
    /// Local load problems (a home document that won't decode) aren't backend failures and
    /// must not be dressed as one.
    @State private var loadErrorMessage: String?
    @State private var refreshTask: Task<Void, Never>?

    private let stateStore = ChecklistStateStore()

    var body: some View {
        content
            .dsPage()
            .navigationTitle(breakdown?.home_name ?? "Score")
            .navigationBarTitleDisplayMode(.inline)
            .task { await initialLoad() }
    }

    @ViewBuilder
    private var content: some View {
        if let breakdown {
            scoreList(breakdown)
        } else if isLoading {
            LoadingTipView(label: "Scoring…")
        } else if let loadErrorMessage {
            ContentUnavailableView {
                Label("Couldn't open this home", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadErrorMessage)
            }
        } else if let failure {
            ContentUnavailableView {
                Label("Couldn't get your score", systemImage: failure.symbol)
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

                if let failure {
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
                    .tint(scoreTint(breakdown.score))
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

            if isUpdating {
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
                            + "\(breakdown.home_name). \(bandDescription(breakdown.score)).")
        .accessibilityValue(isUpdating ? "Updating" : "")
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
    /// say the same thing to someone who can't tell the green ring from the amber one.
    private func bandLabel(_ score: Int) -> some View {
        Label(bandDescription(score), systemImage: bandSymbol(score))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(scoreTextTint(score))
            .accessibilityHidden(true)  // already spoken by the header's combined label
    }

    /// The score ring is the biggest colour surface in the app outside the 3D view, so it has
    /// to obey the same rule: no route orange in chrome. The mid band uses `Theme.caution`
    /// (amber), not SwiftUI's `.orange`. These are FILL colours (ring stroke, progress bar) and
    /// are held to WCAG's 3:1 non-text bar; `scoreTextTint` is the text-safe sibling.
    private func scoreTint(_ score: Int) -> Color {
        switch score {
        case 80...: Theme.accent
        case 50..<80: Theme.caution
        default: Theme.warning
        }
    }

    /// Same three bands, but the accent band uses the darkened/lightened `accentText` so the
    /// band caption clears 4.5:1 in both appearances.
    private func scoreTextTint(_ score: Int) -> Color {
        switch score {
        case 80...: Theme.accentText
        case 50..<80: Theme.caution
        default: Theme.warning
        }
    }

    private func bandDescription(_ score: Int) -> String {
        switch score {
        case 80...: "Well prepared"
        case 50..<80: "Some gaps to close"
        default: "Needs work"
        }
    }

    private func bandSymbol(_ score: Int) -> String {
        switch score {
        case 80...: "checkmark.shield.fill"
        case 50..<80: "exclamationmark.triangle.fill"
        default: "xmark.octagon.fill"
        }
    }

    /// One of the three S6.7 peril sub-scores, shown under the composite ring. `basis` is
    /// S11.2's evidence tier (ScoreBasisLabel maps it from `ScoreBreakdown.basis`) — nil on a
    /// server that predates it, in which case the row just omits the line rather than
    /// guessing.
    private func subScoreView(label: String, score: Int, basis: String? = nil) -> some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.headline)
                .foregroundStyle(scoreTextTint(score))
            Text(label)
                .font(.caption2)
                .foregroundStyle(DS.supporting)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
            if let basis {
                Text(basis)
                    .font(.system(size: 9, weight: .semibold))
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

    // MARK: - Breakdown

    /// Colour by how much of the component is earned (the design's thresholds): ≥70 % accent,
    /// ≥40 % caution, else warning. Fills, held to 3:1; the text beside them uses text-safe
    /// siblings.
    private func componentTint(_ component: ScoreComponent) -> Color {
        guard component.max_points > 0 else { return DS.supporting }
        let ratio = component.earned_points / component.max_points
        return ratio >= 0.7 ? Theme.accent : (ratio >= 0.4 ? Theme.caution : Theme.warning)
    }

    private func componentTextTint(_ component: ScoreComponent) -> Color {
        componentTint(component) == Theme.accent ? Theme.accentText : componentTint(component)
    }

    private func componentRow(_ component: ScoreComponent) -> some View {
        let points = "\(formatted(component.earned_points)) of "
            + "\(formatted(component.max_points)) points"
        let pointsText = "\(formatted(component.earned_points)) / \(formatted(component.max_points))"
        return VStack(alignment: .leading, spacing: 6) {
            // At accessibility sizes "Smoke alarms" and "12 / 20" cannot share a line without
            // one of them truncating, so the row stacks instead of shrinking either.
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(component.label).font(.body.weight(.medium)).foregroundStyle(DS.ink)
                    Spacer()
                    Text(pointsText)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(componentTextTint(component))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.label).font(.body.weight(.medium)).foregroundStyle(DS.ink)
                    Text(pointsText)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(componentTextTint(component))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.track)
                    Capsule()
                        .fill(componentTint(component))
                        .frame(width: component.max_points > 0
                               ? geo.size.width * CGFloat(min(1, component.earned_points / component.max_points))
                               : 0)
                }
            }
            .frame(height: 4)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
            Text(component.detail)
                .font(.subheadline)
                .foregroundStyle(DS.supporting)
            WhyDisclosure(rationale: component.rationale)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(component.label). \(points). \(component.detail)")
    }

    /// "30" not "30.0", but "2.14" for fractional per-item values like 15/7.
    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // MARK: - Data

    private func initialLoad() async {
        guard breakdown == nil, !isLoading else { return }
        checklistState = stateStore.load(homeID: homeID)
        isLoading = true
        defer { isLoading = false }
        do {
            home = try HomeDocumentStore().load(homeID: homeID, as: HomeModel.self)
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = "Couldn't load this home: \(error)"
            return
        }
        await fetchScore()
    }

    /// Cancels any in-flight request and re-POSTs /score with the current checklist state.
    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await fetchScore() }
    }

    private func fetchScore() async {
        guard let home else {
            // First load failed before the model decoded; retry the whole load.
            await initialLoad()
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        do {
            let new = try await apiClient.score(home: home, checklistState: checklistState)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .linear(duration: 0) : .snappy) {
                breakdown = new
                if let cache = try? ScoreCache() { cache.save(new, for: homeID) }
                failure = nil
            }
        } catch is CancellationError {
            // A newer toggle superseded this request.
        } catch {
            guard !Task.isCancelled else { return }
            failure = BackendFailure(error, while: .score)
        }
    }
}

#Preview {
    NavigationStack {
        ScoreScreen(homeID: "preview-home")
    }
    .environment(APIClient())
}

/// The "Why" reveal, with a selection notch — `DisclosureGroup`'s own toggle is silent.
private struct WhyDisclosure: View {
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
        }
        .tint(Theme.accentText)
        .onChange(of: isExpanded) { Haptics.selection() }
        .accessibilityHint("Opens to explain how these points are worked out.")
    }
}
