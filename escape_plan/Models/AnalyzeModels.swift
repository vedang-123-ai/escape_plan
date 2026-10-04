// AnalyzeModels.swift
// Swift mirror of the S3.2 /analyze contract (backend/app/ai/agent.py: AnalysisResult /
// Finding). An API response, not the homemodel schema — field names stay snake_case to match
// the backend exactly, like RoutePlan.swift and ScoreModels.swift.
//
// The client renders findings verbatim (severity, finding, recommendation, citation) and
// never derives its own safety judgments. The tool-call trace is server-side demo material;
// the app doesn't render it, so it is deliberately not decoded here — lenient decoding keeps
// this mirror stable if the trace shape evolves.

import Foundation

/// One validated finding from the /analyze endpoint. `evidence` holds tool_use_ids the
/// backend already validated against the trace; the app keeps them for transparency but
/// renders `finding`/`recommendation`/`citation`.
struct AgentFinding: Decodable, Equatable, Identifiable, Hashable {
    var severity: Severity
    var room_ids: [String]
    var finding: String
    var evidence: [String]
    var recommendation: String
    var citation: String

    /// Findings carry no server id; the content itself identifies the row for SwiftUI lists.
    var id: String { "\(severity.rawValue)|\(room_ids.joined(separator: ","))|\(finding)" }

    /// Tolerant like the route enums: a finding is nested inside the /analyze response, so
    /// an unrecognized severity would fail the whole analysis and the user would see none
    /// of the agent's findings. An unranked finding is still a finding worth reading.
    enum Severity: String, Decodable, Hashable {
        case high, med, low
        /// Newer than this build. Sorts as least-severe so it can never masquerade as a
        /// `high` the user should act on first.
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Severity(rawValue: raw) ?? .unknown
        }
    }

    private enum CodingKeys: String, CodingKey {
        case severity, room_ids, finding, evidence, recommendation, citation
    }

    init(severity: Severity, room_ids: [String] = [], finding: String,
         evidence: [String] = [], recommendation: String, citation: String) {
        self.severity = severity
        self.room_ids = room_ids
        self.finding = finding
        self.evidence = evidence
        self.recommendation = recommendation
        self.citation = citation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decode(Severity.self, forKey: .severity)
        room_ids = try container.decodeIfPresent([String].self, forKey: .room_ids) ?? []
        finding = try container.decode(String.self, forKey: .finding)
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        recommendation = try container.decode(String.self, forKey: .recommendation)
        citation = try container.decode(String.self, forKey: .citation)
    }
}

/// POST /analyze response. `truncated` means the agent hit its iteration cap and returned
/// partial results; `dropped` lists findings the server rejected in validation.
struct AnalysisResult: Decodable, Equatable {
    var findings: [AgentFinding]
    var truncated: Bool
    var dropped: [String]

    private enum CodingKeys: String, CodingKey {
        case findings, truncated, dropped
    }

    init(findings: [AgentFinding], truncated: Bool = false, dropped: [String] = []) {
        self.findings = findings
        self.truncated = truncated
        self.dropped = dropped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        findings = try container.decodeIfPresent([AgentFinding].self, forKey: .findings) ?? []
        truncated = try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        dropped = try container.decodeIfPresent([String].self, forKey: .dropped) ?? []
    }
}

// MARK: - Request

/// POST /analyze body — the home and nothing else; thresholds and the corpus live server-side.
struct AnalyzeRequest: Encodable {
    var home: HomeModel
}
