//  AuthFailure.swift
//  escape_plan — S8.3 auth
//
//  What went wrong signing in, in terms a person can act on.
//
//  Deliberately NOT a new case on `BackendFailure.Operation` (Networking/BackendFailure.swift).
//  That type is shared by six screens and is built around one axis — "can retrying help, and
//  should we point at Settings?" — for endpoints guarded by the shared bearer token. Auth
//  speaks a different vocabulary on the same status codes:
//
//    401  there it means "the build's shared token is wrong, open Settings".
//         here it means "that password is wrong", and Settings cannot help.
//    409  BackendFailure has no case for it at all.
//    503  there it means "busy, try again in a moment".
//         here it means the OPERATOR has not configured cloud sync — retrying forever
//         will not fix an unset MONGODB_URI, and saying "busy" would be a lie.
//
//  Bending the shared type to cover both would blur the distinction it exists to draw.
//  See docs/decisions.md, 2026-09-15.

import Foundation

struct AuthFailure: Error, Equatable {

    enum Kind: Equatable {
        /// No usable connection.
        case offline
        /// The request ran out of time. Its own case because the backend is on Render's free
        /// tier, which sleeps: the first request after an idle period can take the better part
        /// of a minute, and telling that user "you're offline" sends them to fix their wifi.
        case timedOut
        /// 401 — wrong email or password. The server deliberately does not say which.
        case invalidCredentials
        /// 409 — that address already has an account.
        case emailAlreadyRegistered
        /// 422 — the server rejected the email or the password as unusable.
        case rejectedInput
        /// 503 — cloud sync is not configured on this deployment.
        case cloudSyncUnavailable
        /// The request was cancelled by us, not refused by anyone.
        case serverBusy
        /// Anything else.
        case server(statusCode: Int)
    }

    var kind: Kind
    /// Shown to the user verbatim.
    var message: String
    /// Whether a Retry button should appear at all. Offering one on a wrong password trains
    /// people to mash a button instead of fixing the typo.
    var isRetryable: Bool
    var symbol: String

    // MARK: - From a transport error

    init(transport error: Error) {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                self.init(kind: .timedOut,
                          message: "The server took too long to answer. It may be waking up "
                                 + "after being idle — try again in a moment.",
                          isRetryable: true, symbol: "clock.arrow.circlepath")
                return
            case .cancelled:
                // The caller went away (view dismissed, task cancelled). Not the user's
                // problem and not worth a scary sentence about the server address.
                self.init(kind: .serverBusy,
                          message: "That was cancelled.",
                          isRetryable: true, symbol: "arrow.clockwise")
                return
            case .notConnectedToInternet, .networkConnectionLost,
                 .cannotConnectToHost, .dataNotAllowed, .cannotFindHost:
                self.init(kind: .offline,
                          message: "You're offline. Signing in needs a connection — "
                                 + "your saved homes and escape routes still work without one.",
                          isRetryable: true, symbol: "wifi.slash")
                return
            default:
                break
            }
        }
        self.init(kind: .server(statusCode: -1),
                  message: "Couldn't reach the server. Check your connection, or the server "
                         + "address in Settings.",
                  isRetryable: true, symbol: "exclamationmark.triangle")
    }

    // MARK: - From a response

    /// `body` is the raw response data, used only to pull out which FIELD a 422 objected to.
    ///
    /// The server's own wording is never shown, for two reasons. It is accurate and unhelpful
    /// on a signup form ("String should have at least 8 characters"), and each pydantic error
    /// carries an `input` key echoing the rejected value — which for a password error is the
    /// password. Surfacing the server's message verbatim would print it on screen.
    init(statusCode: Int, body: Data? = nil) {
        switch statusCode {
        case 401:
            self.init(kind: .invalidCredentials,
                      message: "That email and password don't match an account.",
                      isRetryable: false, symbol: "person.crop.circle.badge.exclamationmark")

        case 409:
            self.init(kind: .emailAlreadyRegistered,
                      message: "That email already has an account. Try signing in instead.",
                      isRetryable: false, symbol: "person.crop.circle.badge.checkmark")

        case 422:
            self.init(kind: .rejectedInput,
                      message: Self.rejectionMessage(body: body),
                      isRetryable: false, symbol: "exclamationmark.bubble")

        case 503:
            self.init(kind: .cloudSyncUnavailable,
                      message: "Accounts aren't available on this server right now. "
                             + "Everything on this device keeps working without one.",
                      isRetryable: false, symbol: "icloud.slash")

        default:
            self.init(kind: .server(statusCode: statusCode),
                      message: "The server had a problem (\(statusCode)). Try again in a moment.",
                      isRetryable: true, symbol: "exclamationmark.triangle")
        }
    }

    private init(kind: Kind, message: String, isRetryable: Bool, symbol: String) {
        self.kind = kind
        self.message = message
        self.isRetryable = isRetryable
        self.symbol = symbol
    }

    // MARK: - FastAPI's two error shapes

    /// FastAPI returns `{"detail": "some string"}` for HTTPException (401/404/409/503) but
    /// `{"detail": [{"loc": [...], "msg": "..."}]}` for a 422 validation error. Code that
    /// assumes `detail` is a String throws on the one status where the body is worth reading.
    private static func rejectionMessage(body: Data?) -> String {
        let generic = "The server couldn't use that email and password."
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let items = object["detail"] as? [[String: Any]]
        else { return generic }

        // `loc` is ["body", "<field>"]; the field is the only part worth surfacing.
        // Reported in the server's own order, so when both fields are wrong the user is sent
        // to the first one on the form rather than the last one we happened to check.
        for field in items.compactMap({ ($0["loc"] as? [Any])?.last as? String }) {
            switch field {
            case "email": return "That doesn't look like an email address."
            case "password": return "That password can't be used — it must be at least 8 characters."
            default: continue
            }
        }
        return generic
    }
}

extension AuthFailure {
    /// A problem found before the request was sent (see `AuthValidation`). Shares the
    /// `.rejectedInput` kind with a server-side 422 because it is the same situation from the
    /// user's point of view — the difference is only how quickly we noticed.
    init(localProblem message: String) {
        self.init(kind: .rejectedInput, message: message,
                  isRetryable: false, symbol: "exclamationmark.bubble")
    }
}
