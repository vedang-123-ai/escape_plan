// OnboardingState.swift
// S4.1: state machine for the onboarding flow. Every backend call is tracked as a LoadState,
// so each one has an explicit idle/loading/loaded/failed/offline representation — no
// implicit dead ends. Views render whatever the state is; tasks always leave a terminal
// state behind (the catch blocks below are the guarantee against infinite spinners).

import Foundation
import Observation

/// One backend call's lifecycle. `offline` is distinct from `failed` so the UI can say
/// "you're offline" instead of a generic error when the backend is simply unreachable.
///
/// `failed`'s payload is deliberately the *rendered sentence* rather than the `BackendFailure`
/// itself: `OnboardingFlowView` pattern-matches this case and feeds the payload straight into a
/// `String` parameter, and that file is owned by another lane. The classified value is carried
/// alongside on `OnboardingState` (`analysisFailure` / `scoreFailure`) so nothing is lost —
/// see the note on `analysisFailure` for the one behaviour still blocked on that view.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
    case offline

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

@Observable
@MainActor
final class OnboardingState {
    enum Step {
        case welcome
        case review
        case plan
        case done
    }

    var step: Step = .welcome

    /// The home document seeded from the twostory fixture (nil until seeding runs).
    private(set) var seededHome: HomeModel?
    private(set) var seedError: String?

    var analysis: LoadState<AnalysisResult> = .idle
    var score: LoadState<ScoreBreakdown> = .idle

    /// The classified failure behind `analysis`, kept whole.
    ///
    /// This is the single source of truth for whether Retry can help: a 502 means the server
    /// needs an operator and `isRetryable` is false. `OnboardingFlowView` currently renders a
    /// Retry row for every non-loaded state; wiring it to this value is a two-line change in
    /// that file, which this lane does not own.
    private(set) var analysisFailure: BackendFailure?
    /// Same, for `score`.
    private(set) var scoreFailure: BackendFailure?

    private var analyzeTask: Task<Void, Never>?
    private var scoreTask: Task<Void, Never>?

    var reviewItems: [ReviewItem] {
        seededHome.map(ReviewItem.items(in:)) ?? []
    }

    // MARK: - Seeding (local, no network)

    /// Seeds the demo home once; re-entering the welcome step reuses the existing seed.
    func seedIfNeeded() {
        guard seededHome == nil else { return }
        do {
            seededHome = try FixtureSeeder.seedDemoHome(into: try HomeDocumentStore())
            seedError = nil
        } catch {
            seedError = "Couldn't create the demo home: \(error.localizedDescription)"
        }
    }

    /// Re-reads the seeded home from disk after the editor saved changes, so N and the plan
    /// step reflect what the user actually confirmed.
    func reloadSeededHome() {
        guard let homeID = seededHome?.home_id else { return }
        seededHome = (try? HomeDocumentStore().load(homeID: homeID, as: HomeModel.self))
            ?? seededHome
    }

    // MARK: - Background inspection (plan step)

    /// Kicks off /analyze and /score together. Idempotent while in flight; Retry calls it
    /// again after a failure.
    func startInspection(api: APIClient) {
        runAnalyze(api: api)
        runScore(api: api)
    }

    func runAnalyze(api: APIClient) {
        guard let home = seededHome, !analysis.isLoading else { return }
        analyzeTask?.cancel()
        analysis = .loading
        analysisFailure = nil
        analyzeTask = Task {
            do {
                let result = try await api.analyze(home: home)
                guard !Task.isCancelled else { return }
                analysis = .loaded(result)
                analysisFailure = nil
            } catch is CancellationError {
            } catch let error where APIClient.isConnectionFailure(error) {
                // `.offline` keeps its own row, which says the inspection will run once the
                // connection is back — but the classified value is recorded too.
                analysisFailure = BackendFailure(error, while: .analysis)
                analysis = .offline
            } catch {
                guard !Task.isCancelled else { return }
                // The hand-rolled `statusCode == 401 ? … : …` ladder is gone. The classifier
                // knows that 401 points at Settings, that 502 cannot be retried away, and that
                // an AI outage leaves routes and the score intact — and says all three.
                let failure = BackendFailure(error, while: .analysis)
                analysisFailure = failure
                analysis = .failed(failure.message)
            }
        }
    }

    func runScore(api: APIClient) {
        guard let home = seededHome, !score.isLoading else { return }
        scoreTask?.cancel()
        score = .loading
        scoreFailure = nil
        scoreTask = Task {
            do {
                let breakdown = try await api.score(home: home, checklistState: [:])
                guard !Task.isCancelled else { return }
                score = .loaded(breakdown)
                scoreFailure = nil
            } catch is CancellationError {
            } catch let error where APIClient.isConnectionFailure(error) {
                scoreFailure = BackendFailure(error, while: .score)
                score = .offline
            } catch {
                guard !Task.isCancelled else { return }
                let failure = BackendFailure(error, while: .score)
                scoreFailure = failure
                score = .failed(failure.message)
            }
        }
    }

    func cancelWork() {
        analyzeTask?.cancel()
        scoreTask?.cancel()
    }
}
