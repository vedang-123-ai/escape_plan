//  AuthSession.swift
//  escape_plan — S8.3 auth
//
//  Who is signed in, and every transition that changes that answer.
//
//  All of the decision-making lives here rather than in LoginView/SignupView, which is what
//  makes it testable on a machine with no simulator: the three SwiftUI files are thin enough
//  that what they can get wrong is layout, not behaviour.
//
//  The app is local-first and stays that way — everything except cloud sync works with no
//  account at all, so nothing in this type may ever block the rest of the app. See
//  `shouldPresentGate` and docs/decisions.md, 2026-09-15.

import Foundation
import Observation

@Observable
@MainActor
final class AuthSession {

    enum State: Equatable {
        case signedOut
        case signedIn(AuthenticatedUser)

        var user: AuthenticatedUser? {
            if case .signedIn(let user) = self { return user }
            return nil
        }
        var isSignedIn: Bool { user != nil }
    }

    private(set) var state: State = .signedOut

    /// A request is in flight — drives the button spinner, and blocks double submission.
    private(set) var isWorking = false

    /// The last thing that went wrong, for the view to render. Settable so a form can clear it
    /// when the user starts typing again.
    var failure: AuthFailure?

    /// Set when sign-in succeeded but the token could not be written to the Keychain. The user
    /// IS signed in — for this launch only — and deserves to know the session will not survive
    /// a restart, which is a different thing from a failure.
    private(set) var persistenceWarning: String?

    /// Whether the root should show the auth gate. False once the user signs in, and false once
    /// they have chosen to continue without an account — the app is fully usable either way, so
    /// this is an invitation, never a wall.
    var shouldPresentGate: Bool { !state.isSignedIn && !hasDismissedGate }

    private(set) var hasDismissedGate: Bool

    /// The current token, for S8.4 to attach to its own requests.
    private(set) var token: AccessToken?

    var baseURL: URL {
        get { client.baseURL }
        set { client.baseURL = newValue }
    }

    private let client: AuthClient
    private let store: TokenStore
    private let defaults: UserDefaults

    static let hasLaunchedKey = "auth.hasLaunchedBefore"
    static let cachedUserKey = "auth.cachedUser"
    static let gateDismissedKey = "auth.gate.dismissed"

    init(client: AuthClient, store: TokenStore, defaults: UserDefaults = .standard) {
        self.client = client
        self.store = store
        self.defaults = defaults
        self.hasDismissedGate = defaults.bool(forKey: Self.gateDismissedKey)

        // Restore HERE, not from the first view's .task.
        //
        // `.task` runs after the first frame, so restoring there means a signed-in user sees
        // the auth gate for a frame and then watches it cross-fade away on every single
        // launch. Restoring during construction means `shouldPresentGate` is already correct
        // the first time any view reads it. It is safe to do in an initialiser precisely
        // because `restore()` is synchronous, local and offline — it reads the Keychain and
        // UserDefaults and nothing else.
        //
        // Calling `restore()` again afterwards is harmless (the first-launch purge is flagged,
        // and the rest is a pure re-read), which is what lets the tests drive it explicitly.
        restore()
    }

    // MARK: - Launch

    /// Decide who is signed in using only what is on the device. Synchronous and offline-safe
    /// on purpose: the first screen must not wait on a network call, least of all one against
    /// a server that may be cold-starting. `refresh()` confirms with the server afterwards.
    func restore() {
        purgeKeychainOnFirstLaunch()

        guard let raw = store.load() else { return signedOutState() }

        let token = AccessToken(raw: raw)
        // Locally-known-expired: don't show an account that the next request will lose.
        guard !token.isExpired() else { return signedOutState() }
        // A token we cannot attribute to anyone is not something to show a signed-in screen
        // for; start clean rather than invent an account.
        guard let user = cachedUser() else { return signedOutState() }

        self.token = token
        state = .signedIn(user)
    }

    /// On iOS a Keychain item OUTLIVES the app that wrote it — delete the app, reinstall it,
    /// and the old token is still there. Without this, a reinstall silently resumes a session
    /// the user may have deleted the app to get out of. UserDefaults does not survive, which
    /// is exactly what makes it the right place for the "have I ever run before" flag.
    private func purgeKeychainOnFirstLaunch() {
        guard !defaults.bool(forKey: Self.hasLaunchedKey) else { return }
        try? store.delete()
        defaults.removeObject(forKey: Self.cachedUserKey)
        defaults.set(true, forKey: Self.hasLaunchedKey)
    }

    /// Confirm the session against the server, and find out if the account is gone.
    ///
    /// The backend re-reads the user on every request, so a deleted account stops working
    /// immediately rather than when its token expires — this is how the app notices.
    func refresh() async {
        guard state.isSignedIn, let token else { return }
        do {
            let user = try await client.me(token: token)
            cache(user)
            state = .signedIn(user)
        } catch let failure as AuthFailure where failure.kind == .invalidCredentials {
            // The server refused the token: revoked, expired, or the account was deleted.
            signOut()
        } catch {
            // Offline, timed out, server trouble. Keep the session — signing someone out
            // because their train went into a tunnel loses their place for no reason.
        }
    }

    // MARK: - Transitions

    func signIn(email: String, password: String) async {
        let email = AuthValidation.normalise(email: email)
        guard checkLocally(email: email, password: password) else { return }

        await working {
            let token = try await self.client.login(email: email, password: password)
            // login returns only a token; /auth/me is how we learn who it belongs to.
            let user = try await self.client.me(token: token)
            self.adopt(token: token, user: user)
        }
    }

    /// Register, then log in.
    ///
    /// Two round trips because `/auth/register` answers 201 with a `UserPublic` and no token —
    /// the backend issues tokens only from `/auth/login`. The user object from the first call
    /// is reused, so this is two requests rather than three.
    func register(email: String, password: String) async {
        let email = AuthValidation.normalise(email: email)
        guard checkLocally(email: email, password: password) else { return }

        await working {
            let user = try await self.client.register(email: email, password: password)
            let token = try await self.client.login(email: email, password: password)
            self.adopt(token: token, user: user)
        }
    }

    func signOut() {
        try? store.delete()
        defaults.removeObject(forKey: Self.cachedUserKey)
        token = nil
        state = .signedOut
        failure = nil
        persistenceWarning = nil
        // Offer the gate again — signing out is a request to be asked.
        setGateDismissed(false)
    }

    /// "Continue without an account". Remembered, so the gate does not nag on every launch.
    func continueWithoutAccount() {
        failure = nil
        setGateDismissed(true)
    }

    // MARK: - Plumbing

    private func checkLocally(email: String, password: String) -> Bool {
        if let problem = AuthValidation.problem(email: email, password: password) {
            failure = problem
            return false
        }
        return true
    }

    /// Runs one credential operation, owning the spinner and the error slot so no caller has
    /// to remember to reset either. Double submission is dropped rather than queued.
    private func working(_ operation: @escaping () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        persistenceWarning = nil
        defer { isWorking = false }

        do {
            try await operation()
        } catch let authFailure as AuthFailure {
            failure = authFailure
        } catch {
            failure = AuthFailure(transport: error)
        }
    }

    private func adopt(token: AccessToken, user: AuthenticatedUser) {
        self.token = token
        cache(user)
        state = .signedIn(user)
        setGateDismissed(true)

        do {
            try store.save(token.raw)
        } catch {
            // Signed in, but only for this launch. Worth saying so — a session that silently
            // evaporates on restart reads as the app forgetting the account.
            persistenceWarning = "You're signed in, but this device couldn't save your session "
                               + "— you may need to sign in again next time."
        }
    }

    private func signedOutState() {
        try? store.delete()
        defaults.removeObject(forKey: Self.cachedUserKey)
        token = nil
        state = .signedOut
    }

    private func setGateDismissed(_ dismissed: Bool) {
        hasDismissedGate = dismissed
        defaults.set(dismissed, forKey: Self.gateDismissedKey)
    }

    // MARK: - Cached identity
    //
    // The account's id and email, so a relaunch can show who is signed in without waiting on
    // the network. Not secret — the token is the credential, and that is in the Keychain.

    private func cache(_ user: AuthenticatedUser) {
        guard let data = try? JSONEncoder.authCache.encode(user) else { return }
        defaults.set(data, forKey: Self.cachedUserKey)
    }

    private func cachedUser() -> AuthenticatedUser? {
        guard let data = defaults.data(forKey: Self.cachedUserKey) else { return nil }
        return try? JSONDecoder.authCache.decode(AuthenticatedUser.self, from: data)
    }
}

extension JSONEncoder {
    static let authCache: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let authCache: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
