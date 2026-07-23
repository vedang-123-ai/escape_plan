# Test-coverage lane — unit tests for the five-lane merge (no playbook id)

- **Who:** P3 (Claude Code)
- **Date(s):** 2026-07-22
- **Status when I stopped:** all five new test files written and green in both harnesses;
  full gate green except one failure in a *concurrent* S4.2 drill lane's in-flight tests
  (not this lane's — see surprises). No source file under `escape_plan/` touched.

## What happened

Pure test-authoring lane covering the gaps the 2026-07-22 five-lane merge left. Before writing
anything I mapped existing coverage — important, because the lane prompt's assumed gaps
(dragOpening clamp, addStairs/deleteStairs, profile CRUD rejections) were mostly **already
covered** by `HomeModelStoreTests`/`ProfileActionsTests`/`UndoStackTests`. The real holes were
`ScoreModels` (zero tests anywhere), `ChecklistStateStore` (zero tests), RoutePlan's decode
**error** side, `ChatError` mapping, and ConversationStore's corrupt-file/relaunch paths.

New files (42 new test cases total):

1. `escape_planTests/EditorCore/EditActionEdgeCaseTests.swift` — **shared**, runs in the
   `tools/editorcore` SwiftPM harness too (13 tests): dragOpening far-end clamp (t=1),
   out-of-range t (−0.5/1.5) clamps instead of rejecting, boundary width-shrink pinned as
   deliberate behavior, mid-wall drags preserve the parametric ref; addStairs rejects <3-vertex
   and self-intersecting (bowtie) footprints; deleteStairs clears a `.stairs` selection and
   keeps unrelated ones; addProfile rejects duplicate tags (was untested), updateProfile
   rejects empty name / dangling bedroom, deleteFloor refused while profiles sleep there;
   coalesced dragOpening gesture = exactly one undo entry.
2. `escape_planTests/ScoreModelsTests.swift` (8) — first coverage of the /score contract:
   full-breakdown decode, optional `source_citation`/`component` → nil, all five categories,
   strictness pins (missing score / unknown category / truncated component all throw —
   deliberate contrast with RoutePlan's leniency), `ScoreComponent.id == key`, and
   `ScoreRequest` encodes exactly `{home, checklist_state}`.
3. `escape_planTests/RoutePlanDecodeErrorTests.swift` (8) — the error side RoutePlanTests
   lacked: garbage/truncated data, missing required keys (`home_id`, `rooms`, `exit_id`),
   unknown `WaypointKind`/`FindingKind` throw, wrong-type `length_m`, and the non-obvious
   pin that `RoutingConstraints` decoding requires both bools (its defaulted init is
   construction-only sugar).
4. `escape_planTests/ChecklistStateStoreTests.swift` (7) — first coverage: round-trip, empty
   → `[:]`, per-home isolation, whole-state replacement on save, the documented
   `"checklistState.<home_id>"` key scheme, corrupt stored value → `[:]`, relaunch survival
   via a fresh store over the same suite.
5. `escape_planTests/ConversationStoreTests.swift` (6) — corrupt file (garbage AND
   wrong-shape JSON) → nil then save recovers; relaunch keeps message ids/citations exactly;
   re-init over an existing directory doesn't truncate; the per-message append-and-resave
   pattern accumulates the whole thread; `clear()` with no file is a no-op; `ChatError`
   user-facing messages pinned (incl. the "Plan tab still work" reassurance).

## Verification

- `swift test --package-path tools/editorcore` — **128/128** (115 + 13 new).
- `python3 -m pytest backend/tests/ -m "not live" -q` — **196 passed, 11 deselected**.
- `python3 backend/corpus/validate.py` — 11 sources, 6 files, thresholds consistent.
- `xcodebuild test` (iPhone 17 Pro sim, incl. UI tests), with the concurrent drill lane's
  suite excluded via `-skip-testing:escape_planTests/DrillSessionTests` — **231 passed, 0
  failed, TEST SUCCEEDED**. All 42 tests from this lane pass on the simulator.

## Decisions / surprises

- **A concurrent S4.2 drill-mode lane is writing into this same working tree right now**
  (`escape_plan/DrillMode/`, `escape_planTests/DrillModeTests.swift`, both untracked and
  changing mid-run). Its `DrillSessionTests.testFloorCrossingBecomesStairsStepWithoutFlight`
  fails in the full gate — that is in-flight work-in-progress, not a regression from this
  lane, and per scope I did not touch it. Same no-worktree pattern the 2026-07-22
  integration note warned about; flagging again.
- **No product bugs found.** The one behavior worth debating is pre-existing and already in
  decisions.md (S2.2's deliberately unclosed gap): `dragOpening` clamps `t0`/`t1`
  independently, so an opening dragged to a wall end *narrows* (bungalow d_front: span
  0.18 → 0.09) instead of stopping short at full width. `EditActionEdgeCaseTests` pins this
  so any future change is a choice, not drift.
- Existing-coverage discovery above is why the EditActions additions are narrower than the
  lane prompt implied — the merge lanes tested themselves better than assumed.
- No playbook deviations (test-only lane) → no new decisions.md row; no new dependencies →
  `tools-used.md` untouched. No checklist.md change: this lane has no playbook session row,
  and it checks no one else's device-only boxes.

## Questions for teammates

- @P3-drill-lane: `DrillSessionTests.testFloorCrossingBecomesStairsStepWithoutFlight` was red
  at 16:58 while you were mid-session — expected WIP, but make sure it's green before your
  handoff so the next integrator doesn't inherit it as background noise.
- @P2: none of this needs a device — all 42 tests are simulator/macOS-runnable and green.

## Next steps

- Nothing pending from this lane. The device/eyes-on list from the five-lane integration
  note is unchanged.
