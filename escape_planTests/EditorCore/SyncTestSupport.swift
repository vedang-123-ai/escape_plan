//  SyncTestSupport.swift — a fake /homes backend, in memory.
//
//  `SyncManagerTests` drives the REAL `CloudHomesClient` against this rather than stubbing the
//  client behind a protocol. That choice is deliberate: a protocol double would let the
//  manager's tests pass while the URL path, the Authorization header, the request body shape
//  or the response decoding were wrong — which is exactly the set of mistakes that only show
//  up against a server nobody on this machine can run.
//
//  It implements the two routes' behaviour as `backend/app/api_auth.py` defines it, including
//  the three details S8.4 depends on and that were verified against the DEPLOYED backend on
//  2026-09-16: the id on the wire is `id` not `_id`, `revision` is server-owned and increments
//  on every accepted write, and an unknown `home_id` is a 404 rather than a create.

import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import EditorCore
#else
@testable import escape_plan
#endif

/// A stand-in for `GET /homes` and `POST /homes`, served through `AuthStubURLProtocol`.
final class FakeCloudBackend: @unchecked Sendable {

    struct Record {
        var id: String
        /// Which account owns it. The real backend takes this from the verified token and
        /// never from the request body — `list_for_user(user.id)` / `find_for_user(id, user.id)`
        /// in `backend/app/cloud_repo.py`. Modelled here because a single-tenant fake makes
        /// cross-account tests pass for the wrong reason.
        var userID: String
        var home: HomeModel
        var revision: Int
        var createdAt: Date
        var updatedAt: Date
    }

    private let lock = NSLock()
    private var records: [String: Record] = [:]
    private var nextID = 1
    private var _failNextRequest: Int?
    private var _failNextPost: Int?
    private var _failNextDelete: Int?
    private var _failEveryRequest: Int?
    private var _requestCount = 0
    private var _authorizationHeaders: [String?] = []

    /// Fail the next request with this status, then clear. Lets a test exercise one failing
    /// action inside an otherwise healthy plan.
    var failNextRequest: Int? {
        get { lock.lock(); defer { lock.unlock() }; return _failNextRequest }
        set { lock.lock(); defer { lock.unlock() }; _failNextRequest = newValue }
    }

    /// Fail the next POST with this status, then clear. Unlike `failNextRequest` this lets
    /// the `GET /homes` through, so a test can fail ONE push inside an otherwise healthy plan.
    var failNextPost: Int? {
        get { lock.lock(); defer { lock.unlock() }; return _failNextPost }
        set { lock.lock(); defer { lock.unlock() }; _failNextPost = newValue }
    }

    /// Fail the next DELETE with this status, then clear. Lets a test prove that a refused
    /// deletion is a per-home failure rather than one that takes the whole run down.
    var failNextDelete: Int? {
        get { lock.lock(); defer { lock.unlock() }; return _failNextDelete }
        set { lock.lock(); defer { lock.unlock() }; _failNextDelete = newValue }
    }

    /// Fail EVERY request with this status — the dead-session case.
    var failEveryRequest: Int? {
        get { lock.lock(); defer { lock.unlock() }; return _failEveryRequest }
        set { lock.lock(); defer { lock.unlock() }; _failEveryRequest = newValue }
    }

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }; return _requestCount
    }

    var authorizationHeaders: [String?] {
        lock.lock(); defer { lock.unlock() }; return _authorizationHeaders
    }

    /// Seed a record as if another device had created it.
    @discardableResult
    func seed(_ home: HomeModel,
              revision: Int = 1,
              userID: String = "u-1",
              updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)) -> String {
        lock.lock(); defer { lock.unlock() }
        let id = "srv-\(nextID)"
        nextID += 1
        records[id] = Record(id: id, userID: userID, home: home, revision: revision,
                             createdAt: updatedAt, updatedAt: updatedAt)
        return id
    }

    /// Replace a seeded record's home, bumping its revision the way an accepted write does.
    func mutate(recordID: String, to home: HomeModel) {
        lock.lock(); defer { lock.unlock() }
        guard var record = records[recordID] else { return }
        record.home = home
        record.revision += 1
        record.updatedAt = Date()
        records[recordID] = record
    }

    var storedHomes: [Record] {
        lock.lock(); defer { lock.unlock() }
        return records.values.sorted { $0.id < $1.id }
    }

    func record(withLocalHomeID homeID: String) -> Record? {
        storedHomes.first { $0.home.home_id == homeID }
    }

    /// Install this backend as the transport for a `CloudHomesClient`.
    func install() {
        AuthStubURLProtocol.respond { [weak self] request in
            guard let self else {
                return AuthStubURLProtocol.Exchange(statusCode: 500, body: Data(), error: nil)
            }
            return self.handle(request)
        }
    }

    // MARK: - Routing

    /// The `sub` claim of the presented bearer token — the real backend's `get_current_user`
    /// resolves the same claim and re-reads the user on every request.
    private func subject(of request: URLRequest) -> String? {
        guard let header = request.value(forHTTPHeaderField: "Authorization"),
              header.hasPrefix("Bearer ") else { return nil }
        return AccessToken(raw: String(header.dropFirst("Bearer ".count))).subject
    }

    private func handle(_ request: URLRequest) -> AuthStubURLProtocol.Exchange {
        lock.lock()
        _requestCount += 1
        _authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
        let forcedEvery = _failEveryRequest
        let forcedOnce = _failNextRequest
        if forcedOnce != nil { _failNextRequest = nil }
        var forcedPost: Int?
        if request.httpMethod == "POST", let status = _failNextPost {
            forcedPost = status
            _failNextPost = nil
        }
        if request.httpMethod == "DELETE", let status = _failNextDelete {
            forcedPost = status
            _failNextDelete = nil
        }
        lock.unlock()

        if let status = forcedEvery { return json(status: status, #"{"detail":"forced"}"#) }
        if let status = forcedOnce { return json(status: status, #"{"detail":"forced"}"#) }
        if let status = forcedPost { return json(status: status, #"{"detail":"forced"}"#) }

        let path = request.url?.path ?? ""
        // `/homes` and `/homes/{id}`, and nothing else. Matching a prefix loosely would let a
        // typo'd URL in the client under test route to the right handler and pass.
        let recordID = path.hasPrefix("/homes/") ? String(path.dropFirst("/homes/".count)) : nil
        guard path == "/homes" || (recordID.map { !$0.isEmpty && !$0.contains("/") } ?? false) else {
            return json(status: 404, #"{"detail":"no such route"}"#)
        }
        // No usable token is a 401, exactly as `_UNAUTHORIZED` in `api_auth.py`.
        guard let userID = subject(of: request) else {
            return json(status: 401, #"{"detail":"Could not validate credentials"}"#)
        }
        switch (request.httpMethod, recordID) {
        case ("GET", nil): return list(for: userID)
        case ("POST", nil): return upsert(AuthStubURLProtocol.capturedBody(request), userID: userID)
        case ("DELETE", .some(let id)): return delete(id, userID: userID)
        default: return json(status: 405, #"{"detail":"method not allowed"}"#)
        }
    }

    /// `DELETE /homes/{id}` — 204, or 404 for a home that is not ours. Same-answer-for-both
    /// is the behaviour `api_auth.py` defines: a 403 would confirm the id is real.
    private func delete(_ recordID: String, userID: String) -> AuthStubURLProtocol.Exchange {
        lock.lock(); defer { lock.unlock() }
        guard let existing = records[recordID], existing.userID == userID else {
            return json(status: 404, #"{"detail":"No such home."}"#)
        }
        records.removeValue(forKey: recordID)
        return AuthStubURLProtocol.Exchange(statusCode: 204, body: Data(), error: nil)
    }

    /// Only this user's homes. The user id comes from the token, never from a parameter —
    /// there is no way for a client to ask for anyone else's.
    private func list(for userID: String) -> AuthStubURLProtocol.Exchange {
        let body = storedHomes.filter { $0.userID == userID }.map(encoded).joined(separator: ",")
        return json(status: 200, "[\(body)]")
    }

    private func upsert(_ body: Data, userID: String) -> AuthStubURLProtocol.Exchange {
        struct Request: Decodable { let home: HomeModel; let home_id: String? }
        guard let decoded = try? HomeModel.decoder.decode(Request.self, from: body) else {
            return json(status: 422, #"{"detail":"unprocessable"}"#)
        }

        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if let requestedID = decoded.home_id {
            // The ownership check is part of the lookup, and a record belonging to someone
            // else answers identically to one that does not exist — confirming the difference
            // would leak the existence of other users' homes.
            guard var existing = records[requestedID], existing.userID == userID else {
                return json(status: 404, #"{"detail":"No such home."}"#)
            }
            existing.home = decoded.home
            existing.revision += 1
            existing.updatedAt = now
            records[requestedID] = existing
            return json(status: 201, encoded(existing))
        }

        let id = "srv-\(nextID)"
        nextID += 1
        let created = Record(id: id, userID: userID, home: decoded.home, revision: 1,
                             createdAt: now, updatedAt: now)
        records[id] = created
        return json(status: 201, encoded(created))
    }

    // MARK: - Encoding

    /// Serialised the way the backend does it — `id`, never `_id`.
    private func encoded(_ record: Record) -> String {
        let home = String(decoding: (try? HomeModel.encoder().encode(record.home)) ?? Data(),
                          as: UTF8.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return """
        {"id":"\(record.id)","user_id":"\(record.userID)","home":\(home),"revision":\(record.revision),\
        "created_at":"\(formatter.string(from: record.createdAt))",\
        "updated_at":"\(formatter.string(from: record.updatedAt))"}
        """
    }

    private func json(status: Int, _ body: String) -> AuthStubURLProtocol.Exchange {
        AuthStubURLProtocol.Exchange(statusCode: status, body: Data(body.utf8), error: nil)
    }
}

// MARK: - Home helpers

extension HomeModel {
    /// A copy under a new `home_id`, for building multi-home libraries out of one fixture.
    func renamedCopy(homeID: String, name: String? = nil, modified: Date? = nil) -> HomeModel {
        var copy = self
        copy.home_id = homeID
        if let name { copy.name = name }
        if let modified { copy.meta.modified = modified }
        return copy
    }
}

/// A syntactically valid JWT whose payload is `{"sub":…,"exp":<far future>}`. Built rather than
/// pasted so it can never age into an expired token and start failing the suite in 2027.
func makeTestToken(subject: String = "u-1",
                   expiresAt: Date = Date().addingTimeInterval(3600)) -> AccessToken {
    func segment(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = segment(["alg": "HS256", "typ": "JWT"])
    let payload = segment(["sub": subject, "exp": Int(expiresAt.timeIntervalSince1970)])
    return AccessToken(raw: "\(header).\(payload).not-a-real-signature")
}
