//  ScoreBasisLabel.swift
//  escape_plan — Readiness (S11.5)
//
//  Maps `ScoreBreakdown.basis` (S11.2, ScoreModels.swift:172) to the exact two-tier label the
//  product spec requires: fire is fully code-quantified; earthquake and tornado are
//  FEMA/NOAA-grounded readiness modules (CLAUDE.md "Scope lock", 01-product-spec.md §4).
//  Nothing else may appear here — that boundary is the whole point, so a labelling slip cannot
//  quietly blur "three equally quantified pillars", which the spec explicitly forbids implying.
//  Foundation-only, symlinked into tools/editorcore.

import Foundation

enum ScoreBasisLabel {
    /// nil when the server predates S11.2 (`basis` omitted entirely) or names a peril/value
    /// this build does not recognise. Showing nothing is the honest failure mode; inventing a
    /// tier is not.
    static func label(for peril: String, basis: [String: String]?) -> String? {
        guard let raw = basis?[peril] else { return nil }
        switch raw {
        case "code_quantified": return "Code-quantified"
        case "guidance_based": return "Guidance-based"
        default: return nil
        }
    }
}
