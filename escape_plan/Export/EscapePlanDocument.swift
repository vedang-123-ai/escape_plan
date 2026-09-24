//  EscapePlanDocument.swift
//  escape_plan — Export module
//
//  Everything the printable plan and the responder snapshot are rendered from.
//
//  WHY THIS IS ITS OWN FILE: it used to live at the top of `EscapePlanPDF.swift`, which
//  imports UIKit for `UIGraphicsPDFRenderer`. That put the *input* type to the whole export
//  path inside a UIKit file, so nothing downstream of it could be symlinked into
//  `tools/editorcore` — the Foundation-only package that is the only suite this project can
//  actually RUN without a simulator. The consequence was not theoretical: S11.6's tests for
//  "the snapshot always carries as_of and the disclaimer" and "occupant names are absent
//  unless consent opts in" sat in the app target and had never executed once.
//
//  The type itself never needed UIKit — it is a HomeModel, an optional RoutePlan, some dates
//  and flags. Extracted 2026-09-24 so `ResponderSnapshotExtractor` and this can join the
//  package. Keep it Foundation-only: adding a UIKit/SwiftUI/CoreGraphics import here silently
//  removes that test coverage again (`.claude/rules/paths/editorcore.md`).

import Foundation

/// Everything the printable plan is rendered from.
struct EscapePlanDocument {
    var home: HomeModel
    /// The engine's routes. Nil is a supported, honest state.
    var plan: RoutePlan?
    /// When `plan` was fetched from the engine (from the offline route cache), if known.
    var routesComputedAt: Date?
    var meetingPoint: String = ""
    var generatedAt: Date = Date()
    var scoreResponse: ScoreBreakdown?
    var isResponderSnapshot: Bool = false

    var hasRoutes: Bool { plan != nil }
}
