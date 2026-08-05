//  BackendFailureTests.swift
//  The classification that used to live as six disagreeing `catch` ladders across six screens.
//
//  The case that matters most is 502 vs 503. The backend started distinguishing them on
//  2026-08-04 — 502 when an operator must act (no Anthropic credit, bad key), 503 when a retry
//  may work (rate limit, overload) — and the app threw that away. Offering Retry on a 502
//  trains people to press a button that provably cannot work.

import Foundation
import Testing

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

    @Test("Cached routes are a notice, not an error")
    func cachedRoutes() {
        let f = BackendFailure.showingCachedRoutes(savedAt: Date(timeIntervalSince1970: 0))
        #expect(f.kind == .offline)
        #expect(f.isRetryable, "the user can still try to get live routes")
    }
}
