//  SyncFailure.swift
//  escape_plan — S8.4 cloud sync
//
//  What went wrong syncing, in terms the Home tab can render and the manager can act on.
//
//  A third error type alongside `BackendFailure` and `AuthFailure`, for the same reason
//  `AuthFailure` is a second one: the status codes are shared but the vocabulary is not, and
//  the RESPONSE to them differs.
//
//    401  BackendFailure: "the build's shared token is wrong, open Settings".
//         AuthFailure:    "that password is wrong".
//         here:           "your session expired" — the app must drop the token and re-auth.
//                         Neither of the other two triggers that, and showing a signed-in user
//                         "wrong password" for a token that simply aged out is nonsense.
//    404  here it means the server no longer has a home this device thinks it synced. That is
//         recoverable without telling anyone: forget the stale remote id and re-create.
//    422  here it means the SERVER rejected this home's shape — a real possibility if the
//         deployed backend's schema_version has drifted from the app's. It must never be
//         retried in a loop, and it must name the home so the user is not told "sync failed"
//         about a library where 11 of 12 homes went up fine.

import Foundation

struct SyncFailure: Error, Equatable {

    enum Kind: Equatable {
        case offline
        case timedOut
        /// 401 — the JWT is gone, expired or rejected. The caller signs out.
        case sessionExpired
        /// 404 — the remote record this device remembered is gone.
        case homeMissing
        /// 422 — the server would not accept this home's shape.
        case rejectedByServer
        /// 503 — cloud sync is not configured on this deployment.
        case cloudSyncUnavailable
        /// A 2xx whose body could not be decoded.
        case unreadableResponse
        case server(statusCode: Int)
    }

    var kind: Kind
    /// Shown to the user verbatim.
    var message: String
    var isRetryable: Bool
    var symbol: String

    /// Whether the session itself is no longer usable, so the app must stop syncing rather
    /// than retry. Exactly one case, named rather than compared at each call site.
    var requiresReauthentication: Bool { kind == .sessionExpired }

    init(kind: Kind, message: String, isRetryable: Bool, symbol: String) {
        self.kind = kind
        self.message = message
        self.isRetryable = isRetryable
        self.symbol = symbol
    }

    // MARK: - From a transport error

    init(transport error: Error) {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                self.init(kind: .timedOut,
                          message: "The server took too long to answer. It may be waking up "
                                 + "after being idle — sync will try again.",
                          isRetryable: true, symbol: "clock.arrow.circlepath")
                return
            case .cancelled:
                self.init(kind: .offline,
                          message: "Sync was cancelled.",
                          isRetryable: true, symbol: "arrow.clockwise")
                return
            case .notConnectedToInternet, .networkConnectionLost,
                 .cannotConnectToHost, .dataNotAllowed, .cannotFindHost:
                self.init(kind: .offline,
                          message: "You're offline. Your homes are saved on this device and "
                                 + "will sync when you're back on a connection.",
                          isRetryable: true, symbol: "wifi.slash")
                return
            default:
                break
            }
        }
        self.init(kind: .server(statusCode: -1),
                  message: "Couldn't reach the server. Your homes are safe on this device.",
                  isRetryable: true, symbol: "exclamationmark.icloud")
    }

    // MARK: - From a response

    init(statusCode: Int) {
        switch statusCode {
        case 401:
            self.init(kind: .sessionExpired,
                      message: "Your session expired. Sign in again to keep syncing.",
                      isRetryable: false, symbol: "person.crop.circle.badge.exclamationmark")
        case 404:
            self.init(kind: .homeMissing,
                      message: "That home is no longer on the server.",
                      isRetryable: true, symbol: "questionmark.folder")
        case 422:
            self.init(kind: .rejectedByServer,
                      message: "The server wouldn't accept this home. It may be running an "
                             + "older version of the app's home format.",
                      isRetryable: false, symbol: "exclamationmark.triangle")
        case 503:
            self.init(kind: .cloudSyncUnavailable,
                      message: "Cloud sync isn't available on this server right now. "
                             + "Everything still works on this device.",
                      isRetryable: false, symbol: "icloud.slash")
        default:
            self.init(kind: .server(statusCode: statusCode),
                      message: "The server returned an unexpected error (\(statusCode)). "
                             + "Your homes are safe on this device.",
                      isRetryable: true, symbol: "exclamationmark.icloud")
        }
    }

    static let unreadableResponse = SyncFailure(
        kind: .unreadableResponse,
        message: "The server sent back something this version of the app can't read.",
        isRetryable: false, symbol: "exclamationmark.triangle")
}
