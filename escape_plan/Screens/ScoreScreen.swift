// ScoreScreen.swift
// S3.5 preparedness score: overall 0–100 score, the five-component weighted breakdown,
// and the actionable checklist. Pushed per-home from HomeScreen (not a tab — the score is
// per-home data, and a sixth tab would overflow into iOS's "More" list; see docs/decisions.md).
//
// No score math happens on this device. Every toggle persists the checklist state locally
// (ChecklistStateStore) and re-POSTs /score; the displayed number and breakdown are always
// the backend's, so they match docs/preparedness-score-weights.md by construction.

import SwiftUI

struct ScoreScreen: View {
    let homeID: String

    @Environment(APIClient.self) private var apiClient

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
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Couldn't get your score", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { refresh() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView()
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
                        .foregroundStyle(.red)
                    Button("Retry") { refresh() }
                        .font(.caption)
                }
            }

            Section("How it's scored") {
                ForEach(breakdown.components) { component in
                    componentRow(component)
                }
            }

            checklistSections(breakdown)
        }
    }

    // MARK: - Score header

    private func scoreHeader(_ breakdown: ScoreBreakdown) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(scoreTint(breakdown.score).opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: max(0.02, Double(breakdown.score) / 100))
                    .stroke(scoreTint(breakdown.score),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.8), value: breakdown.score)
                VStack(spacing: 0) {
                    Text("\(breakdown.score)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreTint(breakdown.score))
                        .contentTransition(.numericText(value: Double(breakdown.score)))
                    Text("of 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 148, height: 148)
            .padding(.top, 4)
            if isUpdating {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func scoreTint(_ score: Int) -> Color {
        switch score {
        case 80...: .green
        case 50..<80: .orange
        default: .red
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
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(component.label)
                        .font(.subheadline)
                    Spacer()
                    Text("\(formatted(component.earned_points)) / \(formatted(component.max_points))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: component.earned_points, total: component.max_points)
                    .tint(scoreTint(breakdown?.score ?? 0))
            }
            .padding(.vertical, 2)
        }
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
                    Text(header)
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
        if item.scoring {
            Toggle(isOn: binding(for: item)) {
                checklistLabel(item)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                checklistLabel(item)
            }
        }
    }

    private func checklistLabel(_ item: ChecklistItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(item.scoring ? .primary : .secondary)
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let citation = item.source_citation {
                Text(citation)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
            errorMessage = "The score couldn't update — check your connection and try again. (\(error.localizedDescription))"
        }
    }
}

#Preview {
    NavigationStack {
        ScoreScreen(homeID: "preview-home")
    }
    .environment(APIClient())
}
