//  AuthStubURLProtocol.swift — a stubbed transport for AuthClient's tests.
//
//  Modelled on `OfflineStubProtocol` (escape_planTests/OfflineIntegrityTests.swift) with one
//  difference: that one calls `URLProtocol.registerClass` and so affects `URLSession.shared`
//  process-wide, which is why its suite must be `.serialized`. This one is installed on a
//  private `URLSessionConfiguration`, so it only ever sees requests from the client under test.
//
//  The captured-request handling is not incidental. URLSession hands a URLProtocol subclass a
//  request whose `httpBody` is nil, having moved the bytes into `httpBodyStream` — so the
//  obvious `request.httpBody` assertion silently reads nil and a body test passes against
//  nothing at all. `capturedBody` drains the stream instead.

import Foundation

final class AuthStubURLProtocol: URLProtocol {

    struct Exchange {
        var statusCode: Int
        var body: Data
        var error: Error?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) -> Exchange)?
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    /// A URLSession that routes only through this stub.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func respond(_ handler: @escaping (URLRequest) -> Exchange) {
        lock.lock(); defer { lock.unlock() }
        Self.handler = handler
        Self.requests = []
    }

    /// Convenience for the common "one canned response" case.
    static func respond(status: Int, json: String = "{}") {
        respond { _ in Exchange(statusCode: status, body: Data(json.utf8), error: nil) }
    }

    static func fail(with error: Error) {
        respond { _ in Exchange(statusCode: 0, body: Data(), error: error) }
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = nil
        requests = []
    }

    static var capturedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    static var lastRequest: URLRequest? { capturedRequests.last }

    /// The request body, read from `httpBodyStream` when URLSession has moved it there.
    static func capturedBody(_ request: URLRequest?) -> Data {
        guard let request else { return Data() }
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    static var lastBodyString: String { String(decoding: capturedBody(lastRequest), as: UTF8.self) }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let exchange = handler(request)
        if let error = exchange.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: exchange.statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: exchange.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
