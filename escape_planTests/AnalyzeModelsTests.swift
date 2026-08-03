//  AnalyzeModelsTests.swift
//  escape_planTests
//
//  The /analyze contract on the client (backend/app/ai/agent.py: AnalysisResult / Finding).
//  This file did not exist before 2026-08-02 — AnalyzeModels shipped untested, which is part
//  of why the sibling `egress` decode break in ScoreModels went unnoticed for six days.
//
//  Same policy as ScoreModels and RoutePlan: strict about structure the backend promised,
//  tolerant about enum values it may add later. A finding is nested inside the response, so
//  one unrecognized severity would cost the user every finding the agent produced.

import XCTest
@testable import escape_plan

final class AnalyzeModelsTests: XCTestCase {

    private func decode(_ json: String) throws -> AnalysisResult {
        try HomeModel.decoder.decode(AnalysisResult.self, from: Data(json.utf8))
    }

    private func findingJSON(severity: String) -> String {
        """
        {
          "severity": "\(severity)",
          "room_ids": ["r_bed_kids"],
          "finding": "The Kids' Bedroom window is too narrow to climb out of.",
          "evidence": ["toolu_01"],
          "recommendation": "Replace it with an egress-compliant window.",
          "citation": "irc-2021-r310"
        }
        """
    }

    private func resultJSON(_ findings: [String]) -> String {
        """
        { "findings": [\(findings.joined(separator: ","))],
          "truncated": false, "dropped": [] }
        """
    }

    // MARK: - Happy path

    func testEveryKnownSeverityDecodes() throws {
        let result = try decode(resultJSON(["high", "med", "low"].map(findingJSON)))
        XCTAssertEqual(result.findings.map(\.severity), [.high, .med, .low])
    }

    func testFindingFieldsSurviveDecoding() throws {
        let result = try decode(resultJSON([findingJSON(severity: "high")]))
        let finding = try XCTUnwrap(result.findings.first)
        XCTAssertEqual(finding.room_ids, ["r_bed_kids"])
        XCTAssertEqual(finding.citation, "irc-2021-r310")
        XCTAssertEqual(finding.evidence, ["toolu_01"])
    }

    // MARK: - Tolerance

    /// The regression guard. An unranked finding is still a finding worth reading; losing
    /// the entire agent analysis over one unrecognized word is not a trade worth making.
    func testUnknownSeverityDegradesInsteadOfKillingTheAnalysis() throws {
        let result = try decode(resultJSON([
            findingJSON(severity: "high"),
            findingJSON(severity: "catastrophic"),
        ]))
        XCTAssertEqual(result.findings.count, 2, "the whole analysis must still decode")
        XCTAssertEqual(result.findings[1].severity, .unknown)
        // The prose the user actually reads is untouched.
        XCTAssertTrue(result.findings[1].finding.contains("too narrow"))
    }

    /// `.unknown` must not be mistaken for something urgent. It sorts last, so a finding
    /// this build can't rank never displaces a real `high` at the top of the list.
    func testUnknownSeverityIsNeverTreatedAsUrgent() {
        XCTAssertNotEqual(AgentFinding.Severity.unknown, .high)
        XCTAssertEqual(AgentFinding.Severity.unknown.rawValue, "unknown")
    }

    // MARK: - Structure stays strict

    func testMissingRequiredFindingFieldThrows() {
        let truncated = #"{ "severity": "high", "finding": "no recommendation field" }"#
        XCTAssertThrowsError(try decode(resultJSON([truncated])),
                             "a field the backend promised is a contract break, not drift")
    }

    func testAbsentOptionalCollectionsDefaultRatherThanThrow() throws {
        let minimal = """
        { "severity": "low", "finding": "Minor.",
          "recommendation": "Do the thing.", "citation": "usfa-escape-plans" }
        """
        let finding = try XCTUnwrap(try decode(resultJSON([minimal])).findings.first)
        XCTAssertEqual(finding.room_ids, [])
        XCTAssertEqual(finding.evidence, [])
    }
}
