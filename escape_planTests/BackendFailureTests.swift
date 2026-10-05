//  BackendFailureTests.swift
//  The classification that used to live as six disagreeing `catch` ladders across six screens.
//
//  The case that matters most is 502 vs 503. The backend started distinguishing them on
//  2026-08-04 — 502 when an operator must act (no Anthropic credit, bad key), 503 when a retry
//  may work (rate limit, overload) — and the app threw that away. Offering Retry on a 502
//  trains people to press a button that provably cannot work.

import Foundation
import Testing
import XCTest

@testable import escape_plan

@Suite("BackendFailure")
struct BackendFailureTests {

    private func failure(_ status: Int,
                         _ operation: BackendFailure.Operation = .routes) -> BackendFailure {
        BackendFailure(APIClientError.unexpectedResponse(statusCode: status), while: operation)
    }

    @Test("502 means an operator must act, so it never offers Retry")
    func operatorMustAct() {
        let f = failure(502, .assistant)
        #expect(f.kind == .aiUnavailable)
        #expect(f.isRetryable == false)
        #expect(f.suggestsSettings == false, "a dry account is not a settings problem")
    }

    @Test("503 is the retryable twin of 502")
    func retryable() {
        let f = failure(503)
        #expect(f.kind == .serverBusy)
        #expect(f.isRetryable)
    }

    @Test("A failed AI call says what still works")
    func namesTheFallback() {
        // The deterministic half is unaffected by an AI outage — that separation is the
        // project's whole architectural argument, so the UI should say it out loud.
        #expect(failure(502, .assistant).message.contains("escape routes still work"))
        #expect(failure(502, .analysis).message.contains("escape routes still work"))
        // …but routing itself failing has no fallback to promise.
        #expect(failure(502, .routes).message.contains("still work") == false)
    }

    @Test("401 and 403 both point at Settings and offer no Retry")
    func unauthorized() {
        for status in [401, 403] {
            let f = failure(status)
            #expect(f.kind == .unauthorized)
            #expect(f.suggestsSettings)
            #expect(f.isRetryable == false, "retrying with the same bad token cannot help")
        }
    }

    @Test("422 on a scan explains what to do differently")
    func rejectedScan() {
        let f = failure(422, .scanConversion)
        #expect(f.kind == .rejectedInput)
        #expect(f.isRetryable == false, "the same incomplete scan will fail the same way")
        #expect(f.message.contains("perimeter"), "should tell the user how to rescan")
    }

    @Test("Being offline reads as a state, not a fault")
    func offline() {
        let f = BackendFailure(URLError(.notConnectedToInternet), while: .routes)
        #expect(f.kind == .offline)
        #expect(f.isRetryable)
    }

    @Test("An unknown status still produces something actionable")
    func unknownStatus() {
        let f = failure(418)
        #expect(f.kind == .server(statusCode: 418))
        #expect(f.message.contains("418"), "the code belongs in the message for bug reports")
        #expect(f.isRetryable)
    }

    @Test("Every operation names itself, including the two the app never adopted")
    func everyOperationHasANoun() {
        // `.simulation` (POST /evacuate) and `.houseBuilder` (POST /build) were the two calls
        // still running hand-rolled status ladders. A 422's default wording quotes the noun,
        // so an empty or placeholder noun would show up as a broken sentence.
        let operations: [BackendFailure.Operation] =
            [.routes, .scanConversion, .score, .analysis, .assistant, .simulation, .houseBuilder]
        for operation in operations {
            #expect(operation.noun.isEmpty == false)
            #expect(failure(422, operation).message.contains(operation.noun)
                    || operation == .scanConversion,
                    "scan conversion has its own bespoke 422 copy; everything else quotes the noun")
        }
    }

    @Test("A simulation failure leaves the saved plan explicitly untouched")
    func simulationPromisesOnlyWhatIsTrue() {
        // /evacuate answers "what if it starts here?" — a separate question about the same
        // model. Failing it changes nothing about the routes already computed and saved.
        #expect(failure(502, .simulation).message.contains("saved escape routes are unchanged"))
        #expect(failure(503, .simulation).isRetryable)
    }

    @Test("Only offline-flavoured failures invite the what-works-offline note")
    func offlineFlavour() {
        #expect(BackendFailure(URLError(.notConnectedToInternet), while: .routes)
            .isOfflineFlavoured)
        #expect(BackendFailure.showingCachedRoutes(savedAt: Date(), peril: "fire", personName: nil)
            .isOfflineFlavoured)
        #expect(failure(502).isOfflineFlavoured == false)
        #expect(failure(401).isOfflineFlavoured == false)
    }

    @Test("Cached routes are a notice, not an error")
    func cachedRoutes() {
        let f = BackendFailure.showingCachedRoutes(savedAt: Date(timeIntervalSince1970: 0),
                                                  peril: "fire", personName: nil)
        #expect(f.kind == .offline)
        #expect(f.isRetryable, "the user can still try to get live routes")
    }

    @Test("429 from the backend's AI cost guard reads as busy, with Retry")
    func rateLimited() {
        let f = failure(429, .assistant)
        #expect(f.kind == .serverBusy)
        #expect(f.isRetryable)
        #expect(f.message == failure(503, .assistant).message, "one busy message, not two")
    }

    @Test("A local file that won't load never blames the server or the connection")
    func localLoad() {
        struct Corrupt: Error {}
        let f = BackendFailure.localLoad(Corrupt())
        #expect(f.kind == .localData)
        #expect(f.isOfflineFlavoured == false)
        #expect(f.suggestsSettings == false, "no server setting can fix a file on this phone")
        #expect(f.message.contains("server") == false)
        #expect(f.message.contains("connection") == false)
        #expect(f.message.contains("this device"))
    }

    // MARK: - S11.37: honest failures

    @Test("A cancelled request is silent: it is not a fault and the banner draws nothing")
    func cancellationIsSilent() {
        for error: Error in [CancellationError(), URLError(.cancelled)] {
            let f = BackendFailure(error, while: .assistant)
            #expect(f.kind == .cancelled)
            #expect(f.isSilent)
            #expect(f.isRetryable == false)
            #expect(f.isOfflineFlavoured == false, "a cancel is not 'you're offline'")
            #expect(f.suggestsSettings == false)
            #expect(BackendFailureBanner.rendersBanner(for: f) == false)
        }
        #expect(BackendFailureBanner.rendersBanner(for: failure(503)))
        #expect(BackendFailure.isCancellation(URLError(.cancelled)))
        #expect(BackendFailure.isCancellation(URLError(.timedOut)) == false)
        #expect(failure(503).isSilent == false)
    }

    @Test("A timeout is the server waking up, not offline")
    func timeoutIsWakingUp() {
        let f = BackendFailure(URLError(.timedOut), while: .assistant)
        #expect(f.kind == .timedOut)
        #expect(f.message.contains("waking up"))
        #expect(f.message.contains("offline") == false)
        #expect(f.isRetryable)
        #expect(f.isOfflineFlavoured == false)
        #expect(f.suggestsSettings == false)
        #expect(BackendFailure(URLError(.timedOut), while: .houseBuilder).message
            .contains("build this home by hand"), "a slow AI import still says the editor works")
    }

    @Test("Real connection loss keeps the offline copy")
    func connectionLossStaysOffline() {
        for code: URLError.Code in [.notConnectedToInternet, .networkConnectionLost,
                                    .cannotConnectToHost, .dataNotAllowed] {
            let f = BackendFailure(URLError(code), while: .routes)
            #expect(f.kind == .offline, "\(code.rawValue) should read as offline")
            #expect(f.message.contains("offline"))
            #expect(f.message.contains("waking up") == false)
        }
    }

    @Test("A body that will not decode says the app and server disagree, and never blames Settings")
    func decodingErrorIsAppServerMismatch() {
        let decodeErrors: [Error] = [
            decodingError(#"{"rooms":"many"}"#),   // typeMismatch
            decodingError(#"{}"#),                  // keyNotFound
            // "not json" (a cut-off body) is no longer a mismatch since S11.50: ResponseCutOffTests.
        ]
        for error in decodeErrors {
            #expect(error is DecodingError, "the fixture must produce a real DecodingError")
            let f = BackendFailure(error, while: .score)
            #expect(f.kind == .appServerMismatch)
            #expect(f.message.contains("Update the app"))
            #expect(f.message.contains("Settings") == false)
            #expect(f.message.contains("reach the server") == false)
            #expect(f.suggestsSettings == false)
            #expect(f.isRetryable == false, "the same body decodes the same way")
            #expect(f.isOfflineFlavoured == false)
        }
    }

    @Test("A fault on this phone is not blamed on the connection or on Settings")
    func localFaultsAreNotConnectivityProblems() {
        let faults: [Error] = [
            EncodingError.invalidValue(1, .init(codingPath: [], debugDescription: "x")),
            InvalidHomeID(homeID: "../evil"),
            CocoaError(.fileReadNoSuchFile),
        ]
        for error in faults {
            let f = BackendFailure(error, while: .score)
            #expect(f.kind == .localData)
            #expect(f.message.contains("on this phone"))
            #expect(f.message.contains("connection") == false)
            #expect(f.suggestsSettings == false)
            #expect(f.isOfflineFlavoured == false)
        }
        // A real network error must still read as one.
        #expect(BackendFailure(URLError(.notConnectedToInternet), while: .score).kind == .offline)
    }

    @Test("A decoding failure from the chat client is still a mismatch, not a server fault")
    func chatDecodeFailure() {
        let f = BackendFailure(decodingError(#"{"reply":1}"#, as: ChatResponse.self),
                               while: .assistant)
        #expect(f.kind == .appServerMismatch)
    }

    @Test("504 is the server giving up on the AI: retryable, and neither offline nor waking up")
    func serverGaveUp() {
        let f = failure(504, .assistant)
        #expect(f.kind == .serverTimedOut)
        #expect(f.isRetryable)
        #expect(f.message.contains("stopped waiting"))
        #expect(f.message.contains("waking up") == false)
        #expect(f.message.contains("offline") == false)
        #expect(f.message.contains("escape routes still work"), "an AI timeout leaves routing intact")
        #expect(f.message != failure(503, .assistant).message)
        #expect(f.message != BackendFailure(URLError(.timedOut), while: .assistant).message)
    }

    @Test("413 says the input is too large and offers no Retry that cannot work")
    func tooLarge() {
        let operations: [BackendFailure.Operation] =
            [.routes, .scanConversion, .score, .analysis, .assistant, .simulation, .houseBuilder]
        for operation in operations {
            let f = failure(413, operation)
            #expect(f.kind == .rejectedInput)
            #expect(f.isRetryable == false, "the identical body is refused identically")
            #expect(f.message.contains("too large") || f.message.contains("too long")
                    || f.message.contains("larger than"))
            #expect(f.message.contains("server had a problem") == false, "not a server fault")
        }
        #expect(failure(413, .houseBuilder).message.contains("smaller photo"))
        #expect(failure(413, .assistant).message.contains("new chat"))
    }

    @Test("A chat 422 shows the server's own sentence, not the generic one")
    func chatUnprocessableKeepsDetail() {
        let detail = "The conversation is 120,000 characters; the limit is 100,000. Send fewer earlier turns."
        let f = BackendFailure(ChatError.unexpectedStatus(statusCode: 422, detail: detail),
                               while: .assistant)
        #expect(f.kind == .rejectedInput)
        #expect(f.message == detail)
        #expect(f.isRetryable == false)

        let bare = BackendFailure(ChatError.unexpectedStatus(statusCode: 422, detail: nil),
                                  while: .assistant)
        #expect(bare.message == failure(422, .assistant).message, "no detail: the generic 422 line")
        let blank = BackendFailure(ChatError.unexpectedStatus(statusCode: 422, detail: "  "),
                                   while: .assistant)
        #expect(blank.message == bare.message)
        let huge = BackendFailure(
            ChatError.unexpectedStatus(statusCode: 422, detail: String(repeating: "x", count: 400)),
            while: .assistant)
        #expect(huge.message == bare.message, "a long dump is not shown to a family")
        // A detail on any other status never replaces that status's own copy.
        let busy = BackendFailure(ChatError.unexpectedStatus(statusCode: 429, detail: "boom"),
                                  while: .assistant)
        #expect(busy.kind == .serverBusy)
    }

    private func decodingError(_ json: String) -> Error {
        struct Shape: Decodable { let rooms: Int }
        return decodingError(json, as: Shape.self)
    }

    private func decodingError<T: Decodable>(_ json: String, as type: T.Type) -> Error {
        do { _ = try JSONDecoder().decode(type, from: Data(json.utf8)); return CancellationError() }
        catch { return error }
    }

    @Test("An opted-in banner fades, except for a Settings fix, an offline notice, or VoiceOver")
    func bannerAutoHide() {
        #expect(BackendFailureBanner.hidesAutomatically(failure(503), voiceOverRunning: false))
        #expect(BackendFailureBanner.hidesAutomatically(failure(502, .assistant), voiceOverRunning: false))
        #expect(!BackendFailureBanner.hidesAutomatically(failure(401), voiceOverRunning: false),
                "a wrong token needs Settings; the banner is the only thing saying so")
        #expect(!BackendFailureBanner.hidesAutomatically(failure(503), voiceOverRunning: true),
                "a VoiceOver user may not have reached the banner yet")
        #expect(!BackendFailureBanner.hidesAutomatically(
                    BackendFailure(URLError(.notConnectedToInternet), while: .routes), voiceOverRunning: false),
                "offline is what says the routes on screen are saved, not live")
        #expect(!BackendFailureBanner.hidesAutomatically(
                    .showingCachedRoutes(savedAt: Date(), peril: "fire", personName: nil),
                                                         voiceOverRunning: false))
        #expect(BackendFailureBanner.autoHideDelay == .seconds(8))
    }
}

/// Which checklist items open the drill (demo trim, 2026-10-02): only the drill item itself.
@MainActor
struct TaskDestinationTests {
    private func practice(_ id: String) -> ChecklistItem {
        ChecklistItem(id: id, category: .practice, title: "t", detail: "d", done: false, scoring: false)
    }

    @Test("Only the drill item opens the drill; meeting point and re-scan tick off in place")
    func practiceItems() {
        #expect(TaskDestination(practice("practice.drill_recent")) == .drill)
        #expect(TaskDestination(practice("practice.meeting_point")) == .toggle)
        #expect(TaskDestination(practice("rescan.home")) == .toggle)
    }

    @Test("The drill item is ticked by hand (trim 2); engine-audited House items are not")
    func drillItemIsUserTicked() {
        let drill = TaskDestination(practice("practice.drill_recent"))
        #expect(drill.isTickedByUser)
        #expect(drill.actionTitle(done: false) == "Run a drill")
        #expect(TaskDestination.toggle.isTickedByUser)
        let alarm = ChecklistItem(id: "alarm.every_level", category: .smoke_alarm, title: "t",
                                  detail: "d", done: false, scoring: true)
        #expect(TaskDestination(alarm) == .house)
        #expect(!TaskDestination(alarm).isTickedByUser)
    }
}


/// The /chat request carries a timeout above the server's chat deadline (S11.37, AUD-032), and a
/// slow answer reaches the failure classifier as a timeout rather than as "offline".
final class ChatTimeoutTests: XCTestCase {

    private final class ChatSpyProtocol: URLProtocol {
        nonisolated(unsafe) static var timeouts: [TimeInterval] = []
        nonisolated(unsafe) static var outcome: Result<Int, URLError> = .success(200)
        nonisolated(unsafe) static var body = Data()
        private static let lock = NSLock()

        static func reset(_ outcome: Result<Int, URLError>, body: Data = Data()) {
            lock.withLock { timeouts = []; Self.outcome = outcome; Self.body = body }
        }
        static var recorded: [TimeInterval] { lock.withLock { timeouts } }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.withLock { Self.timeouts.append(request.timeoutInterval) }
            switch Self.outcome {
            case .failure(let error):
                client?.urlProtocol(self, didFailWithError: error)
            case .success(let status):
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Self.body)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        override func stopLoading() {}
    }

    private func sendChat(_ outcome: Result<Int, URLError>, body: Data = Data()) async throws -> Error? {
        ChatSpyProtocol.reset(outcome, body: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatSpyProtocol.self]
        let defaults = UserDefaults(suiteName: "ChatTimeoutTests.\(UUID().uuidString)")!
        defaults.set("https://chat-timeout-tests.invalid", forKey: "APIClient.baseURL")
        let client = APIClient(defaults: defaults, session: URLSession(configuration: configuration))
        let home = try FixtureLoader.load(.twostory)
        do {
            _ = try await client.chat(home: home, messages: [ChatMessage(role: .user, content: "hi")])
            return nil
        } catch { return error }
    }

    func testChatRequestWaitsAtLeastTwoMinutes() async throws {
        _ = try await sendChat(.success(503))
        XCTAssertEqual(ChatSpyProtocol.recorded.count, 1)
        let sent = try XCTUnwrap(ChatSpyProtocol.recorded.first)
        XCTAssertGreaterThanOrEqual(sent, 120, "must outlast a 51 s cold start plus the server's 110 s deadline")
        XCTAssertEqual(sent, APIClient.chatTimeout)
    }

    func testSlowChatReadsAsWakingUpNotOffline() async throws {
        let sent = try await sendChat(.failure(URLError(.timedOut)))
        let error = try XCTUnwrap(sent)
        let failure = BackendFailure(error, while: .assistant)
        XCTAssertEqual(failure.kind, .timedOut)
        XCTAssertFalse(failure.isOfflineFlavoured)
    }

    func testCancelledChatReadsAsSilent() async throws {
        let sent = try await sendChat(.failure(URLError(.cancelled)))
        let error = try XCTUnwrap(sent)
        XCTAssertTrue(BackendFailure(error, while: .assistant).isSilent)
    }

    func testChat504ReadsAsServerGaveUp() async throws {
        let sent = try await sendChat(.success(504))
        let error = try XCTUnwrap(sent)
        XCTAssertEqual(BackendFailure(error, while: .assistant).kind, .serverTimedOut)
    }

    func testChatRejectionDetailReachesTheUser() async throws {
        let sentence = "The conversation is 120,000 characters; send fewer earlier turns."
        let body = try JSONSerialization.data(withJSONObject: ["detail": sentence])
        let sent = try await sendChat(.success(422), body: body)
        let error = try XCTUnwrap(sent)
        let failure = BackendFailure(error, while: .assistant)
        XCTAssertEqual(failure.kind, .rejectedInput)
        XCTAssertEqual(failure.message, sentence, "the server's own words, through the real client")
    }
}
