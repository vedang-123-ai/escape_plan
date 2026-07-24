// OnboardingFlowView.swift
// S4.1: the golden-path container — seed a starter home from the twostory fixture, surface
// "N items need review", confirm into the Plan step (routes render in the embedded
// PlanScreen; /analyze and /score run in the background), then land in the normal tab shell.
// Every backend call renders an explicit loading / loaded / failed / offline state; nothing
// here can dead-end.

import SwiftUI

struct OnboardingFlowView: View {
    @Environment(APIClient.self) private var apiClient
    @State private var state = OnboardingState()
    /// Set when "Review in Editor" is tapped; the editor is the existing S2.1/S2.2 screen.
    @State private var editingHomeID: String?

    var onFinished: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch state.step {
                case .welcome: welcome
                case .review: review
                case .plan: plan
                case .done: done
                }
            }
            .navigationDestination(item: $editingHomeID) { homeID in
                HouseScreen(homeID: homeID) { state.reloadSeededHome() }
            }
        }
        .onDisappear { state.cancelWork() }
    }

    // MARK: - Step 1: welcome + seed

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.12))
                    .frame(width: 148, height: 148)
                Image(systemName: "house.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint.opacity(0.35))
                    .offset(y: -4)
                Image(systemName: "figure.run")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                    .offset(x: 26, y: 14)
            }
            .accessibilityHidden(true)
            Text("Escape Plan").font(.largeTitle.bold())
            Text("Map your home, and every room gets a way out. Practice it together, "
                 + "before you ever need it.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            if let seedError = state.seedError {
                // Seeding is fully local; this only fires if Documents itself is broken.
                Label(seedError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Scanning with the camera needs an iPhone Pro — this tour uses a demo home "
                 + "we prepared, so you can try everything right now.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                state.seedIfNeeded()
                if state.seededHome != nil { state.step = .review }
            } label: {
                Text("Take the tour")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            Button("Skip — I'll map my own home") { onFinished() }
                .font(.subheadline)
                .padding(.bottom)
        }
    }

    // MARK: - Step 2: review low-confidence items

    private var review: some View {
        let items = state.reviewItems
        return VStack(spacing: 0) {
            List {
                Section {
                    if items.isEmpty {
                        Label("Everything looks good — no items need review.",
                              systemImage: "checkmark.seal")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { item in
                            HStack {
                                Image(systemName: icon(for: item.kind))
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(item.kind.rawValue): \(item.name)")
                                        .font(.subheadline)
                                    Text(item.floorName).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let confidence = item.confidence {
                                    Text("\(Int(confidence * 100))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text(items.isEmpty
                         ? "Scan check"
                         : "\(items.count) item\(items.count == 1 ? "" : "s") need\(items.count == 1 ? "s" : "") review")
                } footer: {
                    if !items.isEmpty {
                        Text("The scan wasn't fully confident about these. Fix them in the editor, or continue — nothing is dropped silently.")
                    }
                }
            }
            VStack(spacing: 10) {
                if !items.isEmpty {
                    Button {
                        editingHomeID = state.seededHome?.home_id
                    } label: {
                        Text("Review in Editor").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    state.step = .plan
                    state.startInspection(api: apiClient)
                } label: {
                    Text(items.isEmpty ? "Continue" : "Confirm & Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Review your scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func icon(for kind: ReviewItem.Kind) -> String {
        switch kind {
        case .room: return "square.dashed"
        case .opening: return "door.left.hand.open"
        case .stairs: return "stairs"
        }
    }

    // MARK: - Step 3: plan + background inspection

    private var plan: some View {
        VStack(spacing: 0) {
            // The real unified house screen: fetches /routes itself, with its own cold-start
            // banner, retry, and (S4.1) cached-plan offline fallback.
            HouseScreen()
            inspectionPanel
            Button {
                state.step = .done
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding([.horizontal, .bottom])
            .padding(.top, 8)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The /analyze + /score status strip. Every state is explicit; Retry re-runs just the
    /// failed call.
    private var inspectionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state.analysis {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Inspecting your home for fire-safety issues…").font(.caption)
                }
            case .loaded(let result):
                if result.findings.isEmpty {
                    Label("Inspection finished — no issues found.", systemImage: "checkmark.seal")
                        .font(.caption)
                } else {
                    Label("\(result.findings.count) safety finding\(result.findings.count == 1 ? "" : "s")",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(result.findings) { finding in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(finding.finding).font(.caption)
                                    Text(finding.recommendation)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                }
            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).font(.caption)
                    Button("Retry") { state.runAnalyze(api: apiClient) }.font(.caption.bold())
                }
            case .offline:
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                    Text("Offline — the safety inspection will run when you're back online.")
                        .font(.caption)
                    Button("Retry") { state.runAnalyze(api: apiClient) }.font(.caption.bold())
                }
            }

            Divider()

            switch state.score {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Computing preparedness score…").font(.caption)
                }
            case .loaded(let breakdown):
                Label("Preparedness score: \(breakdown.score)/100",
                      systemImage: "checkmark.shield")
                    .font(.caption.bold())
            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).font(.caption)
                    Button("Retry") { state.runScore(api: apiClient) }.font(.caption.bold())
                }
            case .offline:
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                    Text("Offline — score needs the backend.").font(.caption)
                    Button("Retry") { state.runScore(api: apiClient) }.font(.caption.bold())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    // MARK: - Step 4: done

    private var done: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're set").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 8) {
                Label("Your home lives in the Home tab", systemImage: "house")
                Label("Escape routes are on the House tab", systemImage: "figure.run")
                Label("Ask questions in the Assistant tab", systemImage: "bubble.left.and.bubble.right")
                if state.score.value != nil {
                    Label("Track your preparedness score from a home's swipe menu",
                          systemImage: "checkmark.shield")
                }
            }
            .font(.callout)
            Spacer()
            Button {
                onFinished()
            } label: {
                Text("Finish").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding([.horizontal, .bottom])
        }
    }
}

#Preview {
    OnboardingFlowView(onFinished: {})
        .environment(APIClient())
}
