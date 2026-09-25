//  ScoreBand.swift
//  escape_plan — Readiness (audit remediation, 2026-09-25)
//
//  Which of the three bands a preparedness score falls in. Home and Score each had their own
//  thresholds (85/60 and 80/50), so a 55 read "Nearly ready" on one tab and "Needs work" on the
//  next. One definition now, written down in docs/preparedness-score-weights.md § Bands.
//
//  Foundation-only: this folder is symlinked into tools/editorcore, so the thresholds are
//  tested under `swift test` with no simulator. Colours live with the views
//  (`ScoreBand.tint` in Screens/ReadinessStore.swift).

import Foundation

enum ScoreBand: Equatable, CaseIterable {
    /// 85–100. The gauge's success flourish fires at the same 85.
    case wellPrepared
    /// 60–84.
    case someGaps
    /// 0–59. The backend's high-severity cap (40) always lands here, as the weights doc says.
    case needsWork

    static let wellPreparedFloor = 85
    static let someGapsFloor = 60

    init(score: Int) {
        switch score {
        case Self.wellPreparedFloor...: self = .wellPrepared
        case Self.someGapsFloor..<Self.wellPreparedFloor: self = .someGaps
        default: self = .needsWork
        }
    }

    /// The words, so the band never rests on colour alone (SC 1.4.1).
    var title: String {
        switch self {
        case .wellPrepared: return "Well prepared"
        case .someGaps: return "Some gaps to close"
        case .needsWork: return "Needs work"
        }
    }

    /// An SF Symbol that says the same thing as `title`.
    var symbol: String {
        switch self {
        case .wellPrepared: return "checkmark.shield.fill"
        case .someGaps: return "exclamationmark.triangle.fill"
        case .needsWork: return "xmark.octagon.fill"
        }
    }
}
