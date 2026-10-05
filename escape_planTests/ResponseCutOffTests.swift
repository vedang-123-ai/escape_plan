//  ResponseCutOffTests.swift
//  S11.50: an answer lost on the way is not an app-version problem and not an operator problem.
//
//  Two cases used to read wrong. A 502 from the proxy in front of the server (Render's edge
//  cutting a slow request) said "the server needs attention" with no Retry, because the app's own
//  deliberate 502 says that. A 200 whose body was cut off mid-transfer said "Update the app". Both
//  are a dropped answer: retryable, and neither the app version nor Settings is to blame.

import Foundation
import XCTest

@testable import escape_plan

final class ResponseCutOffTests: XCTestCase {

    // MARK: - Telling the app's 502 from a proxy's

    func testOnlyTheAppsOwnJSONDetailMakesA502TheOperatorCase() {
        let appBody = Data(#"{"detail": "The AI service rejected the request: credit balance too low"}"#.utf8)
        guard case .unexpectedResponse(502) = APIClientError.forStatus(502, body: appBody) else {
            return XCTFail("the server's own 502 must stay the operator-must-act case")
        }
        let proxyBodies = [Data("<html><body>502 Bad Gateway</body></html>".utf8), Data(),
                           Data(#"{"error": "upstream"}"#.utf8), Data(#"{"detail": ["x"]}"#.utf8)]
        for body in proxyBodies {
            guard case .gatewayFailure(502) = APIClientError.forStatus(502, body: body) else {
                return XCTFail("a 502 without the app's {detail: text} is a proxy's: \(String(decoding: body, as: UTF8.self))")
            }
        }
        // Other statuses are untouched whatever the body.
        guard case .unexpectedResponse(503) = APIClientError.forStatus(503, body: Data("<html>".utf8)) else {
            return XCTFail("503 reads the same from a proxy or the app")
        }
    }

    func testAProxy502IsRetryableAndBlamesNobody() {
        for operation: BackendFailure.Operation in [.routes, .score, .analysis, .assistant, .houseBuilder] {
            let f = BackendFailure(APIClientError.gatewayFailure(statusCode: 502), while: operation)
            XCTAssertEqual(f.kind, .responseCutOff)
            XCTAssertTrue(f.isRetryable, "a dropped connection is exactly when Retry helps")
            XCTAssertFalse(f.suggestsSettings)
            XCTAssertTrue(f.message.contains("cut off"))
            XCTAssertFalse(f.message.contains("needs attention"), "no operator has to act")
            XCTAssertFalse(f.message.contains("Update the app"))
        }
        XCTAssertTrue(BackendFailure(APIClientError.gatewayFailure(statusCode: 502), while: .assistant)
            .message.contains("escape routes still work"), "the AI half failing leaves routing intact")
        // The server's own 502 is unchanged.
        XCTAssertEqual(BackendFailure(APIClientError.unexpectedResponse(statusCode: 502), while: .assistant).kind,
                       .aiUnavailable)
    }

    // MARK: - A cut-off body is not a shape mismatch

    private func decodeError(_ body: String) -> Error {
        do { _ = try JSONDecoder().decode(ScoreBreakdown.self, from: Data(body.utf8)); return CancellationError() }
        catch { return error }
    }

    func testABodyCutOffMidTransferIsRetryableNotUpdateTheApp() {
        let cut = [#"{"home_id": "a", "home_name": "A", "sco"#, "", "<html>502 Bad Gateway</html>"]
        for body in cut {
            let error = decodeError(body)
            XCTAssertTrue(error is DecodingError, "fixture must be a real DecodingError")
            let f = BackendFailure(error, while: .score)
            XCTAssertEqual(f.kind, .responseCutOff, "body: \(body)")
            XCTAssertTrue(f.isRetryable)
            XCTAssertFalse(f.message.contains("Update the app"))
            XCTAssertFalse(f.suggestsSettings)
        }
    }

    func testAWholeBodyOfTheWrongShapeIsStillAMismatch() {
        let wrongShape = [
            #"{"home_id": 1}"#,                                             // typeMismatch
            #"{"home_id": "a"}"#,                                           // keyNotFound
            #"{"home_id": "a", "home_name": "A", "score": null}"#,          // valueNotFound
        ]
        for body in wrongShape {
            let f = BackendFailure(decodeError(body), while: .score)
            XCTAssertEqual(f.kind, .appServerMismatch, "body: \(body)")
            XCTAssertFalse(f.isRetryable)
        }
        // dataCorrupted too, but inside valid JSON (a value the app cannot read): still a mismatch.
        struct Stamped: Decodable { let at: Date }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var nested: Error = CancellationError()
        do { _ = try decoder.decode(Stamped.self, from: Data(#"{"at": "last tuesday"}"#.utf8)) } catch { nested = error }
        guard case DecodingError.dataCorrupted = nested else { return XCTFail("fixture must be dataCorrupted: \(nested)") }
        XCTAssertEqual(BackendFailure(nested, while: .score).kind, .appServerMismatch)
    }

    // MARK: - Through the real client

    private final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var body = Data()
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func client(status: Int, body: Data) -> APIClient {
        StubProtocol.status = status
        StubProtocol.body = body
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let defaults = UserDefaults(suiteName: "ResponseCutOffTests.\(UUID().uuidString)")!
        defaults.set("https://cut-off-tests.invalid", forKey: "APIClient.baseURL")
        return APIClient(defaults: defaults, session: URLSession(configuration: configuration))
    }

    private func failure(_ status: Int, _ body: String, chat: Bool) async throws -> BackendFailure {
        let api = client(status: status, body: Data(body.utf8))
        let home = try FixtureLoader.load(.twostory)
        do {
            if chat {
                _ = try await api.chat(home: home, messages: [ChatMessage(role: .user, content: "hi")])
            } else {
                _ = try await api.score(home: home, checklistState: [:])
            }
            XCTFail("the stub never answers 200 with a valid body")
            throw CancellationError()
        } catch {
            return BackendFailure(error, while: chat ? .assistant : .score)
        }
    }

    func testEndToEndProxy502AndCutBodiesOnScoreAndChat() async throws {
        for chat in [false, true] {
            let proxy = try await failure(502, "<html>Bad Gateway</html>", chat: chat)
            XCTAssertEqual(proxy.kind, .responseCutOff, chat ? "chat" : "score")
            let own = try await failure(502, #"{"detail": "The AI service rejected the request: no credit"}"#, chat: chat)
            XCTAssertEqual(own.kind, .aiUnavailable, chat ? "chat" : "score")
            let cut = try await failure(200, #"{"reply": "Get out and st"#, chat: chat)
            XCTAssertEqual(cut.kind, .responseCutOff, chat ? "chat" : "score")
        }
    }
}
