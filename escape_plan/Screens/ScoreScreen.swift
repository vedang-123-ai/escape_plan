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

    /// The ring tracks the size of the number inside it. At AX sizes we abandon the ring
    /// altogether (see `scoreHeader`), so this only ever has to cover the non-AX range.
    @ScaledMetric(relativeTo: .largeTitle) private var ringDiameter: CGFloat = 148
    @ScaledMetric(relativeTo: .largeTitle) private var ringStroke: CGFloat = 12

    @State private var home: HomeModel?
    @State private var breakdown: ScoreBreakdown?
    @State private var checklistState: [String: Bool] = [:]
    @State private var isLoading = false
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var refreshTask: Task<Void, Never>?

    private let stateStore = ChecklistStateStore()

    var body: some View {
        content
            .navigationTitle(breakdown?.home_name ?? "Score")
            .navigationBarTitleDisplayMode(.inline)
            .task { await initialLoad() }
    }

    @ViewBuilder
    private var content: some View {
        if let breakdown {
            scoreList(breakdown)
        } else if isLoading {
            ProgressView("Scoring…")
                .accessibilityLabel("Working out your preparedness score.")
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Couldn't get your score", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { refresh() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Try again")
                    .accessibilityHint("Asks the server for your preparedness score again.")
            }
        } else {
            ProgressView()
                .accessibilityLabel("Loading your preparedness score.")
        }
    }

    private func scoreList(_ breakdown: ScoreBreakdown) -> some View {
        List {
            Section {
                scoreHeader(breakdown)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .accessibilityLabel("Score may be out of date. \(errorMessage)")
                    Button("Retry") { refresh() }
                        .font(.caption)
                        .minimumTapTarget()
                        .accessibilityLabel("Retry")
                        .accessibilityHint("Asks the server for an up-to-date score.")
                }
            }

            Section {
                ForEach(breakdown.components) { component in
                    componentRow(component)
                }
            } header: {
                Text("How it's scored").accessibilityAddTraits(.isHeader)
            }

            checklistSections(breakdown)
        }
    }

    // MARK: - Score header

    /// Below accessibility sizes the score is a ring; at AX1 and above the ring is dropped for
    /// a full-width bar. A ring cannot grow with 310% text without either clipping the number
    /// or eating the whole screen, and shrinking the number to fit would defeat the point of
    /// asking for large text — so the *shape* gives way, not the text.
    private var usesRing: Bool { dynamicTypeSize < .accessibility1 }

    private func scoreHeader(_ breakdown: ScoreBreakdown) -> some View {
        VStack(spacing: 10) {
            if usesRing {
                ZStack {
                    Circle()
                        .stroke(scoreTint(breakdown.score).opacity(0.15), lineWidth: ringStroke)
                    Circle()
                        .trim(from: 0, to: max(0.02, Double(breakdown.score) / 100))
                        .stroke(scoreTint(breakdown.score),
                                style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        // Reduce Motion: the ring still moves to the new value, it just gets
                        // there in one step instead of springing past it.
                        .animation(reduceMotion ? .linear(duration: 0) : .spring(duration: 0.8),
                                   value: breakdown.score)
                    scoreNumber(breakdown)
                }
                .frame(width: ringDiameter, height: ringDiameter)
                .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    scoreNumber(breakdown)
                    ProgressView(value: Double(breakdown.score), total: 100)
                        .tint(scoreTint(breakdown.score))
                }
                .padding(.top, 4)
            }

            bandLabel(breakdown.score)

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
        VStack(spacing: 0) {
            Text("\(breakdown.score)")
                // Was `.system(size: 52)` — a hard-coded point size ignores Dynamic Type
                // entirely. `Theme.metric` is `.largeTitle` rounded/bold, so it scales.
                .font(Theme.metric)
                .foregroundStyle(scoreTint(breakdown.score))
                .contentTransition(reduceMotion
                                   ? .identity
                                   : .numericText(value: Double(breakdown.score)))
                .minimumScaleFactor(0.6)
            Text("of 100")
                .font(.caption)
                .foregroundStyle(Theme.supporting)
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

    // MARK: - Breakdown

    private func componentRow(_ component: ScoreComponent) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(component.detail)
                    .font(.caption)
                Text(component.rationale)
                    .font(.caption2)
                    .foregroundStyle(Theme.supporting)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(component.detail) \(component.rationale)")
        } label: {
            componentLabel(component)
        }
        .accessibilityHint("Opens to explain how these points are worked out.")
    }

    @ViewBuilder
    private func componentLabel(_ component: ScoreComponent) -> some View {
        let points = "\(formatted(component.earned_points)) of "
            + "\(formatted(component.max_points)) points"
        VStack(alignment: .leading, spacing: 6) {
            // At accessibility sizes "Smoke alarms" and "12 / 20" cannot share a line without
            // one of them truncating, so the row stacks instead of shrinking either.
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(component.label).font(.subheadline)
                    Spacer()
                    Text("\(formatted(component.earned_points)) / \(formatted(component.max_points))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.supporting)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.label).font(.subheadline)
                    Text("\(formatted(component.earned_points)) / \(formatted(component.max_points))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.supporting)
                }
            }
            ProgressView(value: component.earned_points, total: component.max_points)
                .tint(scoreTint(breakdown?.score ?? 0))
                .accessibilityHidden(true)  // the value is already in the row's label
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(component.label). \(points).")
    }

    /// "30" not "30.0", but "2.14" for fractional per-item values like 15/7.
    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // MARK: - Checklist

    /// A whitelist: a category missing from here decodes fine and then renders nowhere.
    /// Keep it exhaustive over `ChecklistCategory` — `ScoreModelsTests` asserts that it is,
    /// because a silently dropped section is how an R310 egress warning goes invisible.
    static let categoryOrder: [(ChecklistCategory, String)] = [
        (.smoke_alarm, "Smoke alarms"),
        (.practice, "Practice"),
        (.routes, "Routes"),
        (.egress, "Escape windows"),
        (.agent_finding, "Findings"),
        (.recommendation, "Recommendations"),
        (.other, "Other"),
    ]

    @ViewBuilder
    private func checklistSections(_ breakdown: ScoreBreakdown) -> some View {
        ForEach(Self.categoryOrder, id: \.0) { category, header in
            let items = breakdown.checklist.filter { $0.category == category }
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        checklistRow(item)
                    }
                } header: {
                    Text(header).accessibilityAddTraits(.isHeader)
                } footer: {
                    if !items.contains(where: \.scoring) {
                        Text("These don't change the score.")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func checklistRow(_ item: ChecklistItem) -> some View {
        // One sentence per row. Without the combine, VoiceOver reads the title, the detail and
        // the citation id as three separate stops before it ever reaches the switch.
        let spoken = spokenChecklist(item)
        if item.scoring {
            Toggle(isOn: binding(for: item)) {
                checklistLabel(item)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityValue((checklistState[item.id] ?? item.done) ? "Done" : "Not done")
            .accessibilityHint("Double tap to mark this "
                               + ((checklistState[item.id] ?? item.done) ? "not done" : "done")
                               + ". Your preparedness score updates straight away.")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.supporting)
                    .accessibilityHidden(true)
                checklistLabel(item)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("For information. \(spoken)")
        }
    }

    private func spokenChecklist(_ item: ChecklistItem) -> String {
        var parts = [item.title, item.detail]
        if let citation = item.source_citation {
            parts.append("Source: \(citation)")
        }
        return parts.joined(separator: ". ")
    }

    private func checklistLabel(_ item: ChecklistItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(item.scoring ? AnyShapeStyle(.primary)
                                              : AnyShapeStyle(Theme.supporting))
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(Theme.supporting)
            if let citation = item.source_citation {
                // Was `.tertiary`, which resolves to ~1.74:1 on white — invisible to anyone
                // with reduced contrast sensitivity, on the one string that proves the advice
                // came from FEMA rather than from a language model.
                Text(citation)
                    .font(.caption2)
                    .foregroundStyle(Theme.supporting)
            }
        }
    }

    private func binding(for item: ChecklistItem) -> Binding<Bool> {
        Binding(
            get: { checklistState[item.id] ?? item.done },
            set: { newValue in
                checklistState[item.id] = newValue
                stateStore.save(checklistState, homeID: homeID)
                if newValue { Haptics.tick() }
                refresh()
            }
        )
    }

    // MARK: - Data

    private func initialLoad() async {
        guard breakdown == nil, !isLoading else { return }
        checklistState = stateStore.load(homeID: homeID)
        isLoading = true
        defer { isLoading = false }
        do {
            home = try HomeDocumentStore().load(homeID: homeID, as: HomeModel.self)
        } catch {
            errorMessage = "Couldn't load this home: \(error)"
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
            withAnimation(.snappy) {
                breakdown = new
                errorMessage = nil
            }
        } catch is CancellationError {
            // A newer toggle superseded this request.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = BackendFailure(error, while: .score).message
        }
    }
}

#Preview {
    NavigationStack {
        ScoreScreen(homeID: "preview-home")
    }
    .environment(APIClient())
}
