// OnboardingFlowView.swift
// S4.1: the golden-path container — seed a starter home from the twostory fixture, surface
// "N items need review", confirm into the Plan step (routes render in the embedded
// PlanScreen; /analyze and /score run in the background), then land in the normal tab shell.
// Every backend call renders an explicit loading / loaded / failed / offline state; nothing
// here can dead-end.

import SwiftUI

struct OnboardingFlowView: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var state = OnboardingState()
    /// Set when "Review in Editor" is tapped; the editor is the existing S2.1/S2.2 screen.
    @State private var editingHomeID: String?

    var onFinished: () -> Void

    /// The welcome hero and the "You're set" tick are decorative — they repeat what the
    /// headline beside them already says. They stay a fixed size (and stay hidden from
    /// VoiceOver) rather than growing with Dynamic Type, because at AX5 a 64pt glyph that
    /// scales would push the "Take the tour" button off-screen. What we do instead is DROP
    /// them entirely at accessibility sizes, giving the space back to the text.
    private var showsDecorativeArt: Bool { dynamicTypeSize < .accessibility1 }

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
            // Reduce Motion: steps still change, they just cut rather than cross-fade.
            .animation(reduceMotion ? nil : .default, value: state.step)
        }
        .onDisappear { state.cancelWork() }
    }

    // MARK: - Step 1: welcome + seed

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            if showsDecorativeArt {
                welcomeArt
            }
            Text("Escape Plan")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Map your home, and every room gets a way out. Practice it together, "
                 + "before you ever need it.")
                .font(.title3)
                .foregroundStyle(Theme.supporting)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            if let seedError = state.seedError {
                // Seeding is fully local; this only fires if Documents itself is broken.
                Label(seedError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .accessibilityLabel("Couldn't set up the demo home. \(seedError)")
            }
            Text("Scanning with the camera needs an iPhone Pro — this tour uses a demo home "
                 + "we prepared, so you can try everything right now.")
                .font(.caption)
                .foregroundStyle(Theme.supporting)
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
            .accessibilityLabel("Take the tour")
            .accessibilityHint("Loads a demo home so you can try escape routes right now, "
                               + "without scanning anything.")
            Button("Skip — I'll map my own home") { onFinished() }
                .font(.subheadline)
                .padding(.bottom)
                .minimumTapTarget()
                .accessibilityLabel("Skip the tour")
                .accessibilityHint("Goes straight to the app so you can scan or build your "
                                   + "own home.")
        }
    }

    /// Fixed-size decoration, hidden from VoiceOver and dropped entirely at AX sizes.
    private var welcomeArt: some View {
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
                            .foregroundStyle(Theme.supporting)
                    } else {
                        ForEach(items) { item in
                            reviewRow(item)
                        }
                    }
                } header: {
                    Text(items.isEmpty
                         ? "Scan check"
                         : "\(items.count) item\(items.count == 1 ? "" : "s") need\(items.count == 1 ? "s" : "") review")
                        .accessibilityAddTraits(.isHeader)
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
                    .accessibilityLabel("Review in editor")
                    .accessibilityHint("Opens the 3D editor so you can correct the "
                                       + "\(items.count) uncertain item\(items.count == 1 ? "" : "s").")
                }
                Button {
                    state.step = .plan
                    state.startInspection(api: apiClient)
                } label: {
                    Text(items.isEmpty ? "Continue" : "Confirm & Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(items.isEmpty ? "Continue" : "Confirm and continue")
                .accessibilityHint(items.isEmpty
                                   ? "Works out the escape routes for this home."
                                   : "Accepts these items as they are and works out the "
                                     + "escape routes.")
            }
            .padding()
        }
        .navigationTitle("Review your scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One row, one sentence. The confidence percentage is meaningless read on its own, and
    /// the amber glyph carries no information a screen reader can use — hence the explicit
    /// "the scan was only 60 percent sure".
    private func reviewRow(_ item: ReviewItem) -> some View {
        HStack {
            Image(systemName: icon(for: item.kind))
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.kind.rawValue): \(item.name)")
                    .font(.subheadline)
                Text(item.floorName).font(.caption).foregroundStyle(Theme.supporting)
            }
            Spacer()
            if let confidence = item.confidence {
                Text("\(Int(confidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.caution)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenReview(item))
    }

    private func spokenReview(_ item: ReviewItem) -> String {
        var sentence = "\(item.kind.rawValue) \(item.name), \(item.floorName)."
        if let confidence = item.confidence {
            sentence += " The scan was only \(Int(confidence * 100)) percent sure about this."
        } else {
            sentence += " Needs review."
        }
        return sentence
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
            .accessibilityHint("Finishes the tour.")
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Inspecting your home for fire-safety issues.")
                .accessibilityAddTraits(.updatesFrequently)
            case .loaded(let result):
                if result.findings.isEmpty {
                    Label("Inspection finished — no issues found.", systemImage: "checkmark.seal")
                        .font(.caption)
                        .accessibilityLabel("Inspection finished. No fire-safety issues found.")
                } else {
                    Label("\(result.findings.count) safety finding\(result.findings.count == 1 ? "" : "s")",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.caution)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("Inspection found \(result.findings.count) "
                                            + "fire-safety issue\(result.findings.count == 1 ? "" : "s").")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(result.findings) { finding in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(finding.finding).font(.caption)
                                    Text(finding.recommendation)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.supporting)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(finding.finding). "
                                                    + "What to do: \(finding.recommendation)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // A fixed 110pt box clips its own scroll content at AX sizes; scaling it
                    // with the text keeps roughly two findings visible at every size.
                    .frame(maxHeight: findingsHeight)
                }
            case .failed(let message):
                statusRow(symbol: "exclamationmark.triangle", text: message,
                          spoken: "Safety inspection failed. \(message)",
                          retryLabel: "Retry the safety inspection",
                          retryable: state.analysisFailure?.isRetryable ?? true) {
                    state.runAnalyze(api: apiClient)
                }
            case .offline:
                statusRow(symbol: "wifi.exclamationmark",
                          text: "Offline — the safety inspection will run when you're back online.",
                          spoken: "You're offline. The safety inspection will run when you're "
                                  + "back online.",
                          retryLabel: "Retry the safety inspection") {
                    state.runAnalyze(api: apiClient)
                }
            }

            Divider()

            switch state.score {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Computing preparedness score…").font(.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Computing your preparedness score.")
                .accessibilityAddTraits(.updatesFrequently)
            case .loaded(let breakdown):
                Label("Preparedness score: \(breakdown.score)/100",
                      systemImage: "checkmark.shield")
                    .font(.caption.bold())
                    .accessibilityLabel("Preparedness score: \(breakdown.score) out of 100.")
            case .failed(let message):
                statusRow(symbol: "exclamationmark.triangle", text: message,
                          spoken: "Couldn't compute your preparedness score. \(message)",
                          retryLabel: "Retry the preparedness score",
                          retryable: state.scoreFailure?.isRetryable ?? true) {
                    state.runScore(api: apiClient)
                }
            case .offline:
                statusRow(symbol: "wifi.exclamationmark",
                          text: "Offline — score needs the backend.",
                          spoken: "You're offline. The preparedness score needs the server.",
                          retryLabel: "Retry the preparedness score") {
                    state.runScore(api: apiClient)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    /// The findings box scales with the text inside it instead of clipping at a fixed 110pt.
    @ScaledMetric(relativeTo: .caption) private var findingsHeight: CGFloat = 110

    /// A failed/offline strip: glyph, message, Retry. Reads as one sentence, and Retry keeps a
    /// 44pt target even though its label is caption-sized (SC 2.5.8).
    ///
    /// `retryable` defaults to true because the offline states genuinely are. A *failed* state
    /// passes the classifier's own verdict: a 502 means an operator has to change something, so
    /// offering Retry there trains people to mash a button that cannot work.
    private func statusRow(symbol: String, text: String, spoken: String,
                           retryLabel: String, retryable: Bool = true,
                           retry: @escaping () -> Void) -> some View {
        // At AX sizes a caption, a glyph and a Retry button cannot share one line.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                statusMessage(symbol: symbol, text: text, spoken: spoken)
                if retryable { retryButton(retryLabel, retry) }
            }
            VStack(alignment: .leading, spacing: 6) {
                statusMessage(symbol: symbol, text: text, spoken: spoken)
                if retryable { retryButton(retryLabel, retry) }
            }
        }
    }

    private func statusMessage(symbol: String, text: String, spoken: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(text).font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func retryButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button("Retry", action: action)
            .font(.caption.bold())
            .minimumTapTarget()
            .accessibilityLabel(label)
    }

    // MARK: - Step 4: done

    private var done: some View {
        VStack(spacing: 16) {
            Spacer()
            if showsDecorativeArt {
                // Decorative: "You're set" is right underneath it. Fixed size, hidden.
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
            Text("You're set")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
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
            .accessibilityLabel("Finish")
            .accessibilityHint("Closes the tour and opens the app.")
        }
    }
}

#Preview {
    OnboardingFlowView(onFinished: {})
        .environment(APIClient())
}
