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
              updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)) -> String {
        lock.lock(); defer { lock.unlock() }
        let id = "srv-\(nextID)"
        nextID += 1
        records[id] = Record(id: id, home: home, revision: revision,
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
        lock.unlock()

        if let status = forcedEvery { return json(status: status, #"{"detail":"forced"}"#) }
        if let status = forcedOnce { return json(status: status, #"{"detail":"forced"}"#) }
        if let status = forcedPost { return json(status: status, #"{"detail":"forced"}"#) }

        guard request.url?.path == "/homes" else {
            return json(status: 404, #"{"detail":"no such route"}"#)
        }
        switch request.httpMethod {
        case "GET": return list()
        case "POST": return upsert(AuthStubURLProtocol.capturedBody(request))
        default: return json(status: 405, #"{"detail":"method not allowed"}"#)
        }
    }

    private func list() -> AuthStubURLProtocol.Exchange {
        let body = storedHomes.map(encoded).joined(separator: ",")
        return json(status: 200, "[\(body)]")
    }

    private func upsert(_ body: Data) -> AuthStubURLProtocol.Exchange {
        struct Request: Decodable { let home: HomeModel; let home_id: String? }
        guard let decoded = try? HomeModel.decoder.decode(Request.self, from: body) else {
            return json(status: 422, #"{"detail":"unprocessable"}"#)
        }

        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if let requestedID = decoded.home_id {
            guard var existing = records[requestedID] else {
                // 404, not a create — confirming an id exists but belongs to someone else
                // would leak the existence of other users' homes.
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
        let created = Record(id: id, home: decoded.home, revision: 1, createdAt: now, updatedAt: now)
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
        {"id":"\(record.id)","user_id":"u-1","home":\(home),"revision":\(record.revision),\
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
