// OnboardingState.swift
// S4.1: state machine for the onboarding flow. Every backend call is tracked as a LoadState,
// so each one has an explicit idle/loading/loaded/failed/offline representation — no
// implicit dead ends. Views render whatever the state is; tasks always leave a terminal
// state behind (the catch blocks below are the guarantee against infinite spinners).

import Foundation
import Observation

/// One backend call's lifecycle. `offline` is distinct from `failed` so the UI can say
/// "you're offline" instead of a generic error when the backend is simply unreachable.
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
        analyzeTask = Task {
            do {
                let result = try await api.analyze(home: home)
                guard !Task.isCancelled else { return }
                analysis = .loaded(result)
            } catch is CancellationError {
            } catch let error where APIClient.isConnectionFailure(error) {
                analysis = .offline
            } catch APIClientError.unexpectedResponse(let statusCode) {
                analysis = .failed(statusCode == 401
                    ? "Backend rejected the request — check the bearer token in Settings."
                    : "AI inspection unavailable right now — your routes and score still work.")
            } catch {
                guard !Task.isCancelled else { return }
                analysis = .failed("AI inspection unavailable right now — your routes and score still work.")
            }
        }
    }

    func runScore(api: APIClient) {
        guard let home = seededHome, !score.isLoading else { return }
        scoreTask?.cancel()
        score = .loading
        scoreTask = Task {
            do {
                let breakdown = try await api.score(home: home, checklistState: [:])
                guard !Task.isCancelled else { return }
                score = .loaded(breakdown)
            } catch is CancellationError {
            } catch let error where APIClient.isConnectionFailure(error) {
                score = .offline
            } catch APIClientError.unexpectedResponse(let statusCode) {
                score = .failed(statusCode == 401
                    ? "Backend rejected the request — check the bearer token in Settings."
                    : "Couldn't compute the score — tap Retry.")
            } catch {
                guard !Task.isCancelled else { return }
                score = .failed("Couldn't compute the score — tap Retry.")
            }
        }
    }

    func cancelWork() {
        analyzeTask?.cancel()
        scoreTask?.cancel()
    }
}
