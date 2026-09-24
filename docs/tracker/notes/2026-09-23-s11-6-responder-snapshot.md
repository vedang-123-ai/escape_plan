# S11.6 — Responder Snapshot v2, "Share with your fire department"

- **Who:** P3 (Claude)
- **Date(s):** 2026-09-23
- **Status when I stopped:** All five mission items implemented and typechecked. `swift test
  --package-path tools/editorcore` green at 522 (up from 516 baseline). Could not run the
  Xcode test suite or generate an actual PDF — no simulator on this machine and the user has
  forbidden booting one. Not merged, not pushed, per instructions.

## What happened

Resumed after a mid-session disk-full (ENOSPC) interruption that the orchestrator fixed
(~44 GiB freed). The two commits made before the interruption (`SnapshotHazardSummary.swift`
+ its EditorCore tests) survived untouched. Picked up exactly where the write to
`ResponderSnapshotJSON.swift` had failed, and committed in small (~10-20 line) steps from
there per the orchestrator's revised instructions.

Built, in order:
1. `SnapshotHazardSummary.swift` (Foundation-only, symlinked into EditorCore) — counts
   `ChecklistItem` findings by category + rule id with citation. Reads the SAME checklist
   the Score screen does (`backend/app/scoring/checklist.py` via `ScoreBreakdown.checklist`)
   rather than re-deriving from `RoutePlan`/`ObjectHazard`, so there is exactly one notion of
   "hazard" in the app. Deliberately excludes `mitigation.secure.*` / per-home
   `mitigation.<slug>` items — those are earthquake-prep suggestions, not findings the engine
   detected on this home.
2. `ResponderSnapshotJSON.swift` — added `SnapshotConsentDecision{acknowledgedAt,
   includeOccupantNames}`, renamed `lastScannedAt` to `asOf` (wire key `"as_of"`), added fixed
   `stalenessNote`/`tacticalDisclaimer` strings (same wording used by both the JSON and the
   PDF), `consent`, `hazardSummary`, and an opt-in `names: [String]?` on `VulnerableOccupant`.
3. `ResponderSnapshotExtractor.extract(from:consent:)` — now pure (reads its clock from
   `document.generatedAt`, not `Date()`); threads consent into whether occupant names are
   populated; computes `hazardSummary` from the cached `ScoreBreakdown.checklist`.
4. `EscapePlanExporter.writeResponderSnapshot(preview:consent:...)` — `consent` is required,
   not defaulted, so a caller cannot generate a snapshot without going through `ConsentSheet`.
5. `ConsentSheet.swift` rewritten: renamed to "Share with your fire department", explains
   what's included/excluded in plain language, adds an "Include occupant names" toggle
   (default off), `onAccept` now hands back a `SnapshotConsentDecision` instead of `Void`.
6. `EscapePlanPDF.swift` — every responder-snapshot page now prints the same fixed
   staleness/disclaimer wording as the JSON, plus an "As of (last scan)" line and a
   whole-home hazard-summary block (`category.ruleID: count [cite: ...]`) on the overview
   page. Uses `ResponderSnapshotExtractor.staleWindow` instead of a second hardcoded 30-day
   constant.
7. `ShareWithFireDepartmentCard.swift` — new, self-contained SwiftUI view (see signature
   below). Shows consent fresh on every tap, generates + shares, and a "Clear my snapshot"
   action.
8. Narrow edit to `SettingsScreen.swift`'s Responder Snapshot section (now titled "Share with
   your fire department" there too) so its "Share" button also asks consent per share, not
   just once at enable-time.
9. Updated `escape_planTests/ResponderSnapshotTests.swift` for the new signatures, plus new
   tests for: as_of/disclaimer/consent always present with the right JSON keys; names present
   only when opted in and the PDF staying anonymous regardless; `hazardSummary` equal to
   `SnapshotHazardSummary.summarize` applied to the same checklist, on all three stock
   fixtures (bungalow/apartment/twostory).

## Decisions / surprises

- **No aggregate "clutter score."** Already logged in `docs/decisions.md`. The hazard summary
  is a list of `{category, ruleID, count, citation}` rows, never a single number.
- **Narrow SettingsScreen exception**, also logged in `docs/decisions.md`.
- **PDF never shows occupant names, regardless of consent.** The names opt-in only affects the
  JSON. Reasoning: paper can be left lying around; the JSON is the file a department would
  actually record. Not explicitly in the session file, but consistent with "occupant privacy"
  mission #5 read conservatively — flagging this interpretation here in case it should be
  revisited.
- **Surprise:** the backend already had `citation` on `RouteFinding`/`ChecklistItem` end to
  end, and `ChecklistItem`'s id already encodes the rule id (`hazard.<rule_id>.<object_id>`,
  `routes.<kind>.<room_id>`, `egress.window.<opening_id>`). That made the hazard summary a
  pure rollup rather than new engine-facing logic — no new citation plumbing needed.
- **Disk-full mid-session.** Not my doing (the whole boot volume was at 100%, not this repo).
  Per the orchestrator's revised instructions, the plan going forward for any future ENOSPC is:
  stop immediately, commit what's staged, report, never delete anything unprompted.

## Questions for teammates

- @S11.7: the narrow SettingsScreen exception (Responder Snapshot section only) is logged in
  `docs/decisions.md` — flag if it collides with anything you're mid-way through there.
- @orchestrator: `ShareWithFireDepartmentCard`'s init needs a `HomeDocumentStore` or an
  `EscapePlanExporter` and a `homeID` — whatever `HomeScreen.swift` already has in scope for
  the existing "Printable Plan" entry point should cover it (see `ExportPlanSheet` for the
  precedent this mirrors).

## Next steps

1. **Wire `ShareWithFireDepartmentCard` into `HomeScreen.swift`** (S11.5 territory — not done
   here). Exact signature:
   ```swift
   ShareWithFireDepartmentCard(homeID: String, store: HomeDocumentStore)
   // or, if a caller already holds an EscapePlanExporter:
   ShareWithFireDepartmentCard(homeID: String, exporter: EscapePlanExporter)
   ```
   Drop it wherever the existing "Printable Plan" / export entry point lives; it needs nothing
   else from the environment.
2. Run the actual acceptance items that need a simulator (see BLOCKERS block below) once one
   is available and the user has said it's OK to use it.
3. Confirm the swift-scenekit-reviewer findings (recorded below once back) were fully
   addressed.

---

## BLOCKERS block — paste into BLOCKERS.md

#### S11.6

- **Device/simulator-gated, unverified:** exporting an actual PDF from the `twostory` fixture
  and eyeballing the as-of/staleness/disclaimer lines and hazard-summary block on the printed
  page. `EscapePlanPDF.swift` imports UIKit and renders through `UIGraphicsPDFRenderer`/
  `UIFont` — this cannot run without a simulator, and the user has forbidden booting one on
  this machine. The PDF *content* changes were made and typechecked
  (`scripts/typecheck-ios.sh` green, 163 app files) but never visually verified. Owned by
  S11.8 per the orchestrator's instruction, or whoever next has simulator access.
- **`escape_planTests/ResponderSnapshotTests.swift` (mine, updated this session) and the rest
  of `escape_planTests`/`escape_planUITests` were never executed**, only typechecked
  (`ok escape_planTests (74 files)`, `ok escape_planUITests (9 files)`). No simulator on this
  machine. Whoever has one should run `xcodebuild test -only-testing:escape_planTests/
  ResponderSnapshotTests` at minimum before trusting these assertions.
- **Backend/Python side of the hazard summary was never run.** There is no local venv on this
  machine (BLOCKERS §4, pre-existing). `SnapshotHazardSummaryTests.swift` and
  `ResponderSnapshotTests.testHazardSummaryMatchesEngineChecklistOnStockFixtures` pin the
  id-shape contract against a reading of `backend/app/scoring/checklist.py`, not against a
  live `build_checklist()` run on the stock fixtures. If checklist.py's id format ever changes
  without a corresponding Swift-side update, these tests would not catch it — they'd need the
  venv to run `pytest backend/tests/test_checklist_hazards.py` alongside them.
- **Design call needing review, not yet cross-checked with anyone:** the PDF never prints
  occupant names even when the resident opts in via consent — only the JSON does. This was my
  own conservative reading of mission #5 ("counts by room, never names, unless the resident
  explicitly opts in"), not something the session file pinned down explicitly. Worth a second
  look before demo/pitch material references it.
- **swift-scenekit-reviewer findings:** see the session note body above / decisions.md if any
  follow-up landed after this note was written — the review was launched but its results are
  not folded into this note's text (written before the review returned; check the session's
  final chat report for what it said and what was changed in response).
