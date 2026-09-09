# S6 — Parallel execution brief (for an orchestrating agent)

Two artefacts live here:

1. **The heavy orchestration prompt** — paste into Antigravity (or any agent runner with
   subagents). It executes the whole S6 arc in dependency waves, with file-ownership fences,
   a build/review/fix loop per lane, and verified gates between waves.
2. **The light Opus audit prompt** — the orchestration run is REQUIRED to emit a filled-in copy
   of this as its final deliverable. Paste that into Claude Opus afterwards. It is deliberately
   cheap: it verifies claims against the tree instead of re-reading the whole repo.

---

## ARTEFACT 1 — THE ORCHESTRATION PROMPT (paste this into Antigravity)

```text
You are the ORCHESTRATOR for the S6 "readiness arc" in the Escape Plan repository
(Congressional App Challenge 2026, deadline Oct 24 2026). You will not write feature code
yourself. You will dispatch subagents in dependency waves, verify their work against the tree
rather than against their reports, and integrate the results.

════════════════════════════════════════════════════════════════════════
PHASE 0 — BOOTSTRAP. Do all of this before dispatching a single subagent.
════════════════════════════════════════════════════════════════════════

Read in full, in this order:
  1. CLAUDE.md (root) — self-contained; the scoped rules under .claude/rules/ load on demand
  2. docs/playbook/06-pivot-intro.md          ← the arc's charter and locked decisions
  3. docs/playbook/S6-1.md … S6-9.md          ← nine self-contained session prompts
  4. docs/tracker/TODO.md                      ← the S6 section, and the still-open items
  5. docs/decisions.md                         ← at minimum the 2026-09-05 entries
  6. docs/profile-constraint-mappings.md       ← the house style for a deterministic rule table
  7. .claude/rules/paths/schema.md and corpus.md

Then establish a REAL baseline. Do not take the tracker's word for it:
  - python3 -m pytest backend/tests/ -m "not live"
  - swift test --package-path tools/editorcore
  - python3 backend/corpus/validate.py
  - xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -derivedDataPath .build-orch CODE_SIGNING_ALLOWED=NO
  - Record the true iOS count from the RESULT BUNDLE, never the console tail:
      xcrun xcresulttool get test-results summary --path <bundle>

Write the four baseline numbers down. Every later "still green" claim is measured against them.
If the baseline is red, STOP and report — do not build on an unknown floor.

════════════════════════════════════════════════════════════════════════
PHASE 1 — TRAPS. These have already cost this project real sessions.
════════════════════════════════════════════════════════════════════════

Brief EVERY subagent you dispatch on the ones relevant to its lane:

  T1. backend/app/scoring/checklist.py ALREADY EXISTS — deterministic generation, stable ids,
      ChecklistState (id→done) persisted on the home document. S6.4 EXTENDS it. A parallel
      checklist implementation is a failed session.
  T2. ScoreScreen.swift ALREADY RENDERS that checklist with toggles via ChecklistStateStore.
      S6.6 lifts and extends it. When the arc is done there must be exactly ONE checklist renderer.
  T3. backend/app/routing/hazard.py ALREADY MEANS fire-origin spread simulation. The word
      "hazard" is taken. Multi-peril work goes in backend/app/routing/perils/.
  T4. escape_plan/Export/ IS ALREADY A COMPLETE PDF PIPELINE — EscapePlanPDF, FloorPlanDrawing,
      PlanProjection, PlanInk, PDFText, EscapePlanExporter — and RouteNarration already turns
      engine waypoints into ordered English. S6.9 re-targets these. A second renderer will drift
      from the printed plan it must match.
  T5. THE ANTHROPIC ACCOUNT IS OUT OF CREDITS. /explain, /analyze and /chat returning 502 is
      EXPECTED and is a billing problem. No subagent may "fix" the AI layer. Any lane that needs
      a live model call to function has been designed wrong — S6.5's interview in particular MUST
      work with zero network calls.
  T6. SourceKit and VS Code CANNOT INDEX this project. They report errors that do not exist.
      Trust xcodebuild only. Never let a subagent "fix" a phantom diagnostic.
  T7. iOS runs are ~1-in-3 environmental flake ("Application failed preflight checks"). Re-run a
      red ONCE before believing it. True counts come from xcresulttool, not the console.
  T8. A PreToolUse hook asks for confirmation before edits to schema/homemodel.schema.json. That
      is the process working. Only the S6.1 lane may touch it.
  T9. A pre-commit hook BLOCKS commits containing Anthropic key material. Never stage .env or a
      token file. escape_plan/BackendConfig.local.json is gitignored and currently MISSING on this
      machine — backend calls will 401 until the owner supplies the token. That is not a bug to fix.
  T10. THE PARALLEL-LANE LESSON (docs/decisions.md, fire-origin split): two lanes each finished
      correct halves and the feature did not exist, because the integration point lived in a file
      fenced to the other lane. EVERY seam in this plan has a NAMED OWNER below. Honour them.

════════════════════════════════════════════════════════════════════════
PHASE 2 — THE WAVE PLAN. Dispatch strictly wave by wave.
════════════════════════════════════════════════════════════════════════

Isolation: give each lane its own git worktree. VERIFY THE WORKTREE ACTUALLY EXISTS before
dispatching into it (a prior session assumed worktrees that were never created and lost the work).

── WAVE 1 ── two lanes, zero file overlap ──────────────────────────────
  LANE A = S6.1 (schema 2.0). OWNS: schema/homemodel.schema.json, schema/fixtures/**,
           backend/app/models.py, escape_plan/Models/**, and the docs it must update.
  LANE B = S6.2 (corpus: earthquake + severe weather). OWNS: backend/corpus/** ONLY.
  Seam: none. These cannot collide.
  GATE: schema-contract-guardian agent clean; validate.py exits 0; a 1.1 document still loads;
        all four suites at or above baseline.

── WAVE 2 ── two lanes, backend vs iOS ─────────────────────────────────
  LANE C = S6.3 (peril engine). OWNS: backend/app/routing/perils/**, and is the ONLY lane
           permitted to edit backend/app/routing/engine.py, plan.py and the /routes handler in
           backend/app/main.py.
  LANE D = S6.5 (household interview, iOS). OWNS: escape_plan/Onboarding/**,
           escape_plan/Screens/ProfileEditorView.swift, ProfilesScreen.swift, and ContentView.swift.
  Seam: none in code. Lane C must publish its finding type names (no_viable_safe_room, the
        earthquake cover-point shape) into docs/peril-objective-mappings.md BEFORE finishing,
        because Wave 3 consumes them.
  GATE: /routes with no `peril` field is byte-identical to the pre-S6.3 response (assert it);
        determinism test passes; interview completes in airplane mode; suites green.

── WAVE 3 ── three lanes ───────────────────────────────────────────────
  LANE E = S6.4 (checklist rule table). OWNS: backend/app/scoring/checklist.py and
           docs/household-checklist-mappings.md. Consumes Lane C's finding types.
  LANE F = S6.8 (earthquake + severe-weather drills). OWNS: escape_plan/DrillMode/**.
  LANE G = S6.9 (responder snapshot). OWNS: escape_plan/Export/** and the sharing section of
           escape_plan/Screens/SettingsScreen.swift.
  Seam: F and G are both iOS but own disjoint directories. SettingsScreen belongs to G alone in
        this wave — if F needs a settings toggle, it files a request to G, it does not edit.
  GATE: every drill string's citation resolves; no drill ever renders "triangle of life"
        (assert by test); the snapshot contains zero names (assert over generated bytes);
        no network call results from the snapshot feature; checklist ids stable across recompute.

── WAVE 4 ── two lanes, and THE ONE REAL COLLISION ─────────────────────
  LANE H = S6.7 (composite score). OWNS: backend/app/scoring/score.py,
           docs/preparedness-score-weights.md, and the /score response contract.
           ** BACKEND ONLY. Lane H does NOT touch any Swift file. **
  LANE I = S6.6 (checklist becomes the Home tab). OWNS: ALL iOS screens in this wave, explicitly
           INCLUDING escape_plan/Screens/ScoreScreen.swift.
  Seam: ScoreScreen. S6.6 and S6.7 both want it. LANE I OWNS IT. Lane H defines the new /score
        fields and hands Lane I the contract; Lane I does the rendering. This is the exact seam
        that failed before — do not split it.
  Note: S6-6.md's header lists prereqs as S6.4+S6.5, but its acceptance requires rendering
        no_viable_safe_room, which only S6.3 produces. The dependency map is right and the header
        is wrong. Treat S6.3 as a real prereq and correct the header as part of Lane I.
  GATE: composite reproducible BY HAND from the weights doc on two fixtures; an unresolved
        high-severity finding caps the composite; zero dead taps on the Home tab; suites green.

════════════════════════════════════════════════════════════════════════
PHASE 3 — THE PER-LANE LOOP. Every subagent runs this, no exceptions.
════════════════════════════════════════════════════════════════════════

Dispatch each lane with: its S6-<n>.md prompt VERBATIM, its file-ownership fence, the relevant
traps from Phase 1, and this loop:

  1. READ    — the session file, plus every existing file it says to read. Do not skim T1–T4.
  2. PLAN    — write the plan before touching code. Name every file you will create or edit and
               confirm each is inside your fence. If you need a file outside it, STOP and report
               to the orchestrator; do not reach across.
  3. TEST    — write the failing tests first. The acceptance criteria in the session file are the
               specification; turn each into at least one test.
  4. BUILD   — smallest change that passes. Match surrounding code style, comment density, naming.
  5. VERIFY  — run the suites your lane touches. Backend lanes: pytest + validate.py. iOS lanes:
               xcodebuild, re-running a red ONCE, with counts from xcresulttool.
  6. REVIEW  — dispatch a REVIEWER SUBAGENT with fresh eyes over your diff. Backend lanes use the
               grounding-auditor (citations resolve, no invented guidance, AI computes nothing) and
               for S6.1 the schema-contract-guardian. iOS lanes use swift-scenekit-reviewer. The
               reviewer must be given the diff and the acceptance criteria and asked for
               CONFIRMED / PLAUSIBLE findings with a failure scenario each.
  7. FIX     — address every CONFIRMED finding. Argue back in writing on any you reject.
  8. RE-VERIFY — full suites again after fixes.
  9. REPORT  — to the orchestrator: what you built, the four suite numbers, what the reviewer
               found and what you did about it, what you did NOT do and why, and every rough edge
               you noticed but left. EVIDENCE, not adjectives. "Tests pass" without counts is not
               a report.

  HARD RULES for every lane:
   - Never claim done without having run the thing. "The code exists" is not verification.
   - Never introduce a new colour. Theme.swift's semantic scale only. Route orange is reserved for
     lit routes and exits; advisory chrome uses dark amber.
   - Never let the AI compute a route, a shelter, or a checklist item. Deterministic engine only.
   - Never ship a safety claim without a [cite: ...] that resolves in backend/corpus/sources.json.
   - Never label an engineering constant as a corpus threshold. Say which it is, in the code.
   - CameraRigModel stays pure — no SceneKit, no UIKit (it is symlinked into a Foundation-only
     SwiftPM package).
   - Never re-enable allowsCameraControl.

════════════════════════════════════════════════════════════════════════
PHASE 4 — GATES. You verify. You do not trust reports.
════════════════════════════════════════════════════════════════════════

After each wave, BEFORE dispatching the next:
  - Merge the wave's worktrees. Expect docs/tracker/activity-log.md to conflict every time;
    resolve by chronological union.
  - Re-run all four suites yourself on the merged tree. Compare to baseline. A count that went
    DOWN without an explanation is a regression, not a rounding error.
  - Re-run any red ONCE (T7) before treating it as real.
  - Dispatch a lane-integrator subagent to confirm the wave's lanes actually cohere — specifically
    that each seam's owner delivered the integration, and that no feature exists only as two
    correct halves (T10).
  - Walk the wave's acceptance criteria yourself. Tick nothing you did not personally observe.
  - If a gate fails: fix forward in a dedicated lane. Do NOT start the next wave on a red gate.

════════════════════════════════════════════════════════════════════════
PHASE 5 — CLOSE OUT. Mandatory. A session without this did not happen.
════════════════════════════════════════════════════════════════════════

Per completed session:
  - docs/tracker/TODO.md — remove only what was personally verified; ADD everything discovered.
  - docs/tracker/notes/<date>-s6-<n>-<slug>.md — copy _TEMPLATE.md. Include the real suite counts.
  - docs/decisions.md — every deviation from the session file, with the reasoning.
  - docs/tools-used.md — any new dependency (CAC originality requirement).
Arc-level:
  - Update docs/playbook/06-pivot-intro.md's status line to reflect what is actually built.
  - Fix S6-6.md's prereq header (see Wave 4).
  - docs/demo/script-v1.md still pitches a fire-only product and its truth-ledger row 17 cites the
    superseded scope lock. Rewrite it ONLY against what actually shipped. Do not describe software
    that does not exist.

════════════════════════════════════════════════════════════════════════
PHASE 6 — FINAL DELIVERABLE (this is not optional)
════════════════════════════════════════════════════════════════════════

Your last output must be a single fenced code block containing ARTEFACT 2 below, with every
<PLACEHOLDER> replaced by real values from this run. The human will paste it into Claude Opus for
an independent audit. Fill it honestly — including the things that went badly. An audit prompt that
hides a shortcut is worse than no audit, because it buys false confidence before a deadline.
```

---

## ARTEFACT 2 — THE OPUS AUDIT PROMPT (template; the run above fills it in)

Deliberately light. It verifies claims against the tree with targeted commands instead of reading
the repository, so it stays cheap while still catching the failure modes this project actually has.

```text
You are auditing work you did not do. Be adversarial. The author is motivated to believe it works;
you are not. Verify against the tree — never accept a claim in a doc or a report as evidence.

WHAT WAS CLAIMED
Sessions completed: <LIST, e.g. S6.1, S6.2, S6.3>
Commits: <SHA RANGE>
Claimed suite counts: backend <N>, EditorCore <N>, iOS <N pass / N fail / N skipped>, corpus <N sources / N files>
Known-incomplete / deliberately skipped: <LIST, or "none claimed" — and be suspicious of "none">

RUN THESE FIRST. Report the real numbers next to the claimed ones.
  python3 -m pytest backend/tests/ -m "not live" -q | tail -5
  swift test --package-path tools/editorcore 2>&1 | tail -5
  python3 backend/corpus/validate.py
  xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath .build-audit CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  # iOS count MUST come from the bundle, not the console:
  xcrun xcresulttool get test-results summary --path <bundle>
A red iOS run is ~1-in-3 environmental flake — re-run once before reporting it as a failure.

THEN CHECK EXACTLY THESE INVARIANTS. Each is a known way this repo breaks.

 1. SCHEMA LOCKSTEP. If schema_version changed: do schema/homemodel.schema.json,
    backend/app/models.py and the Swift Codable structs agree on every new field's name, type and
    optionality? Does a pre-bump (1.1) document still load? Run the schema-contract-guardian agent.
 2. GROUNDING. Every new user-facing safety string carries a [cite: id] that resolves in
    backend/corpus/sources.json. Spot-check five citations against what the source actually says.
    Any claim with no source is a defect, not a style issue.
 3. THE AI COMPUTES NOTHING. grep the new code paths: no model call decides a route, a shelter, a
    safe room, or which checklist items apply. The interview extracts facts; that is its entire job.
 4. CONSTANT HONESTY. Every new numeric constant is labelled in code as either a corpus threshold
    (with a citation) or an engineering choice (explicitly, no citation). A number dressed as a
    safety threshold without a source is a defect.
 5. DETERMINISM / PURITY. New routing and scoring code is pure — no I/O, no globals. Same input
    twice → byte-identical output. Is there a test asserting it?
 6. BACK-COMPAT. POST /routes with no `peril` field returns exactly the pre-S6.3 response. Is
    there a test pinning that, or only a claim?
 7. CHECKLIST ID STABILITY. Recomputing the checklist yields identical ids, so persisted done-state
    survives. Is it tested, or asserted?
 8. NO SECOND IMPLEMENTATION. Exactly one checklist generator (backend/app/scoring/checklist.py),
    one checklist renderer, one PDF pipeline (escape_plan/Export/). Grep for duplicates — a
    parallel implementation is the single most likely failure of a multi-lane run.
 9. COLOUR DISCIPLINE. No new colours outside Theme.swift's semantic scale. Route orange appears
    only on lit routes and exits, never in chrome.
10. PRIVACY. If the responder snapshot shipped: no names, no device id, and no address the user did
    not type, in EITHER output format. Verify over generated bytes, not by reading the generator.
11. NO SILENT FALLBACKS. no_viable_route / no_viable_safe_room must surface as findings, never be
    downgraded to a "best available" route or shelter. Grep for any least-bad substitution.
12. SEAM INTEGRITY (the historical failure). For each feature touched by two lanes, is it actually
    reachable in the app — or does it exist as two correct halves nobody wired together? Trace at
    least one full path from UI entry point to engine and back.
13. DOC TRUTH. Do docs/tracker/TODO.md, the session notes and docs/decisions.md describe what is
    actually in the tree? This repo has a documented history of the tracker contradicting itself.
    Flag any box ticked for something you cannot observe.

OUTPUT
Findings only, most severe first, each with: file:line, one-sentence defect, a concrete failure
scenario (inputs → wrong result), and CONFIRMED (you reproduced it) or PLAUSIBLE (you reasoned it).
Then one line: SHIP / FIX FIRST / DO NOT SHIP, and the single thing you would fix before filming.
Do not fix anything yourself. Do not restate what is correct — only what is wrong or unproven.
```
