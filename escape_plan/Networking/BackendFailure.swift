//  BackendFailure.swift
//  Networking — one place that decides what a backend failure means to the user.
//
//  Before this, six screens each hand-rolled their own `catch` ladder over raw status codes
//  (HouseScreen, HomeScreen, the old DrillScreen, BuildFromPlanView, OnboardingState, the chat
//  client), and they disagreed: some special-cased 401, some didn't; every one of them
//  offered a Retry button regardless of whether retrying could possibly help.
//
//  The backend distinguishes these cases properly as of 2026-08-04 — an app-level
//  `anthropic.APIError` handler returns **502** when an operator must act (no credit, bad
//  key) and **503** when a retry may work (rate limit, overload, network). That distinction
//  was being thrown away here, because `APIClientError` only carried a status code and every
//  screen collapsed it to one generic sentence.
//
//  Foundation only: no SwiftUI, so the classification is unit-testable without a view.

import Foundation

/// A backend failure translated into something a person can act on.
struct BackendFailure: Equatable {

    /// What actually went wrong, in the only terms the UI needs to branch on.
    enum Kind: Equatable {
        /// No usable connection — URLError, or the request never reached us.
        case offline
        /// 401/403 — the shared bearer token is missing or wrong. Settings fixes it.
        case unauthorized
        /// 502 — the server reached the AI and the AI refused: no credit, bad key,
        /// misconfiguration. **Retrying cannot help**; a human has to change something.
        case aiUnavailable
        /// 503 or 429 — rate limited, overloaded, or a transient network fault upstream.
        /// Retrying is exactly the right move. 429 is the backend's own AI cost guard
        /// (backend/app/rate_limit.py, 2026-09-25): too many assistant calls from this device, or
        /// every AI slot busy. Same advice either way — wait a moment.
        case serverBusy
        /// This device could not read its own saved copy of the home. Nothing was sent to the
        /// server, so "couldn't reach the server" would be a lie; the fix, if any, is local.
        case localData
        /// 422 — we sent something the server could not use. Usually a scan too incomplete
        /// to convert; retrying the same input will fail the same way.
        case rejectedInput
        /// Any other non-200.
        case server(statusCode: Int)
    }

    /// The operation that failed, which supplies the noun and the honest fallback line.
    /// Nothing here promises a capability the app doesn't have.
    enum Operation {
        case routes
        case scanConversion
        case score
        case analysis
        case assistant
        /// POST /evacuate — "what if the fire starts here?". Distinct from `.routes` because a
        /// failed simulation leaves the saved plan completely intact, and saying so is the
        /// difference between a broken app and an unavailable extra.
        case simulation
        /// POST /build — the LLM house builder behind "Import a plan". AI-backed, so it can be
        /// down while everything deterministic is fine.
        case houseBuilder

        var noun: String {
            switch self {
            case .routes: return "your escape routes"
            case .scanConversion: return "the scan"
            case .score: return "your preparedness score"
            case .analysis: return "the home inspection"
            case .assistant: return "the assistant"
            case .simulation: return "the fire simulation"
            case .houseBuilder: return "the draft home"
            }
        }

        /// What still works when this particular thing doesn't. Only operations that can fail
        /// while the deterministic half is fine have one — which is the whole point of keeping
        /// routing out of the model. Nothing here promises a capability the app doesn't have:
        /// `.routes` and `.scanConversion` genuinely need the server, so they promise nothing.
        var fallback: String? {
            switch self {
            case .analysis, .assistant:
                return "Your escape routes still work."
            case .score:
                return "Your escape routes still work."
            case .simulation:
                // The simulation is an extra question asked of the same engine; the saved
                // plan it was asked about is untouched.
                return "Your saved escape routes are unchanged."
            case .houseBuilder:
                // Honest and true offline: the editor is entirely local.
                return "You can still build this home by hand in the 3D editor."
            case .routes, .scanConversion:
                return nil
            }
        }
    }

    var kind: Kind
    var message: String
    /// Whether a Retry button should be offered at all. Showing one on a 502 trains people to
    /// mash a button that cannot work.
    var isRetryable: Bool
    /// Whether to point the user at Settings.
    var suggestsSettings: Bool
    var symbol: String

    /// True when the reason is "no connection" (including the cached-routes notice), which is
    /// the only case where listing what still works offline is useful rather than noise.
    var isOfflineFlavoured: Bool { kind == .offline }

    // MARK: - Classification

    init(_ error: Error, while operation: Operation) {
        let fallback = operation.fallback.map { " " + $0 } ?? ""

        // The chat client throws its own error type (it keeps the server's 422 detail); the
        // user-facing meaning is decided here, once, like every other endpoint's.
        if let chatError = error as? ChatError {
            self.init(APIClientError.unexpectedResponse(statusCode: chatError.statusCode),
                      while: operation)
            return
        }

        if error is CancellationError {
            // Callers should filter these out before constructing a failure; treat as busy
            // rather than inventing an alarming message.
            self.init(kind: .serverBusy,
                      message: "That took too long. Try again.",
                      isRetryable: true, suggestsSettings: false,
                      symbol: "arrow.clockwise")
            return
        }

        guard case APIClientError.unexpectedResponse(let statusCode) = error else {
            let urlError = error as? URLError
            let offline = urlError.map {
                [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .timedOut, .dataNotAllowed].contains($0.code)
            } ?? false
            if offline {
                self.init(kind: .offline,
                          message: "You're offline. Getting \(operation.noun) needs a "
                                 + "connection — reconnect and try again.",
                          isRetryable: true, suggestsSettings: false,
                          symbol: "wifi.slash")
            } else {
                self.init(kind: .server(statusCode: -1),
                          message: "Couldn't reach the server. Check your connection, or the "
                                 + "server address in Settings.",
                          isRetryable: true, suggestsSettings: true,
                          symbol: "exclamationmark.triangle")
            }
            return
        }

        switch statusCode {
        case 401, 403:
            self.init(kind: .unauthorized,
                      message: "The server didn't accept the access token — check it in Settings.",
                      isRetryable: false, suggestsSettings: true,
                      symbol: "key.slash")

        case 422:
            let detail: String
            switch operation {
            case .scanConversion:
                detail = "The scan couldn't be turned into a floor plan — it may be incomplete. "
                       + "Try scanning again, walking the full perimeter of each room."
            default:
                detail = "The server couldn't use what we sent for \(operation.noun)."
            }
            self.init(kind: .rejectedInput, message: detail,
                      isRetryable: false, suggestsSettings: false,
                      symbol: "questionmark.folder")

        case 502:
            // The operator-must-act case. Deliberately no Retry.
            self.init(kind: .aiUnavailable,
                      message: "AI features are unavailable right now — the server needs "
                             + "attention.\(fallback)",
                      isRetryable: false, suggestsSettings: false,
                      symbol: "sparkles.slash")

        case 429, 503:
            self.init(kind: .serverBusy,
                      message: "The server is busy. Try again in a moment.",
                      isRetryable: true, suggestsSettings: false,
                      symbol: "clock.arrow.circlepath")

        default:
            self.init(kind: .server(statusCode: statusCode),
                      message: "The server had a problem (\(statusCode)). Try again in a moment.",
                      isRetryable: true, suggestsSettings: false,
                      symbol: "exclamationmark.triangle")
        }
    }

    private init(kind: Kind, message: String, isRetryable: Bool,
                 suggestsSettings: Bool, symbol: String) {
        self.kind = kind
        self.message = message
        self.isRetryable = isRetryable
        self.suggestsSettings = suggestsSettings
        self.symbol = symbol
    }

    /// A home document on this device that would not load or decode. Deliberately not routed
    /// through `init(_:while:)`: that classifier reads any non-HTTP error as a connection
    /// problem, which told people with a corrupt file to check their Wi-Fi (audit 2026-09-25).
    static func localLoad(_ error: Error) -> BackendFailure {
        BackendFailure(
            kind: .localData,
            message: "Couldn't open this home's saved file on this device. Your other homes "
                   + "are unaffected; try choosing it again, or re-create it from a scan.",
            isRetryable: false, suggestsSettings: false,
            symbol: "doc.badge.exclamationmark")
    }

    /// Not a failure: routes are being shown from the offline cache. Same banner treatment so
    /// there is one notice component rather than two that drift apart. Names the peril and
    /// the person the saved plan was computed for (S11.36), because "your last saved routes"
    /// used to be true of any plan: nil `personName` is the whole household.
    static func showingCachedRoutes(savedAt: Date, peril: String,
                                    personName: String?) -> BackendFailure {
        BackendFailure(
            kind: .offline,
            message: "You're offline — showing your last saved \(peril) routes for "
                   + (personName ?? "everyone") + " from "
                   + savedAt.formatted(date: .abbreviated, time: .shortened) + ".",
            isRetryable: true, suggestsSettings: false,
            symbol: "arrow.down.circle")
    }
}
