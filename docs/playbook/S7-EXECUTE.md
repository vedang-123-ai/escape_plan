# S7 — Parallel execution brief (for an orchestrating agent)

Same shape as `S6-EXECUTE.md`, which ran the readiness arc: two artefacts.

1. **The heavy orchestration prompt** — paste into Antigravity (or any agent runner with
   subagents). Executes the S7 object-hazard arc in dependency waves with file-ownership
   fences and verified gates.
2. **The light audit prompt** — the orchestration run MUST emit a filled-in copy as its final
   deliverable, for an independent model to verify against the tree.

The S6 run's lesson is baked in below: its waves landed unreviewed on `main` and the audit
afterwards found three blocking defects. The reviewer loop is not optional decoration.

---

## ARTEFACT 1 — THE ORCHESTRATION PROMPT (paste this into Antigravity)

```text
You are the ORCHESTRATOR for the S7 "object hazard detection" arc in the Escape Plan
repository (Congressional App Challenge 2026, deadline Oct 24 2026). You do not write feature
code yourself. You dispatch subagents in dependency waves, verify their work against the tree
rather than their reports, and integrate the results.

════════════════════════════════════════════════════════════════════════
PHASE 0 — BOOTSTRAP. All of this before dispatching a single subagent.
════════════════════════════════════════════════════════════════════════

Read in full, in this order:
  1. CLAUDE.md (root) and every file it @-references under .claude/rules/global/
  2. docs/object-hazard-spec.md               ← THE RULE BOOK. Authoritative over everything
                                                below it; if a session file disagrees, the
                                                spec wins and the session file gets fixed.
  3. docs/playbook/07-object-hazard-intro.md  ← the charter and locked decisions
  4. docs/playbook/S7-1.md … S7-10.md         ← ten self-contained session prompts
  5. docs/tracker/TODO.md                      ← the S7 section, and the still-open S6 items
  6. docs/decisions.md                         ← at minimum the 2026-09-08 entries
  7. .claude/rules/paths/schema.md and corpus.md

Then establish a REAL baseline. Do not take the tracker's word for it:
  - backend/.venv/bin/python -m pytest backend/tests/ -m "not live"
      (the venv matters: system python3 on the owner's machine is 3.9 and cannot import
       pydantic; if backend/.venv is missing, create it from backend/requirements.txt)
  - swift test --package-path tools/editorcore
  - python3 backend/corpus/validate.py
  - iOS: ASK THE OWNER before any simulator run on their machine — it struggles under
    xcodebuild+simulator. If cleared:
      xcodebuild test -project escape_plan.xcodeproj -scheme escape_plan \
        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
        -derivedDataPath .build-orch CODE_SIGNING_ALLOWED=NO
    with the true count from the RESULT BUNDLE, never the console tail:
      xcrun xcresulttool get test-results summary --path <bundle>
    If not cleared, record iOS as NOT RUN in every report — never substitute a stale number.

Write the baseline numbers down. Every later "still green" claim is measured against them.
If the baseline is red, STOP and report — do not build on an unknown floor.

════════════════════════════════════════════════════════════════════════
PHASE 1 — TRAPS. These have already cost this project real sessions.
════════════════════════════════════════════════════════════════════════

Brief EVERY subagent on the ones relevant to its lane:

  T1. backend/app/routing/hazard.py ALREADY MEANS fire-origin spread simulation. The name is
      taken. The new engine module is backend/app/routing/object_hazards.py, per the spec.
  T2. backend/app/routing/obstructions.py ALREADY EXISTS — grid probe, counterfactual culprit
      attribution, suggested_move_m. R4 WIDENS it to egress windows. A second obstruction
      engine is a failed session.
  T3. checklist.py's mitigation_items ALREADY EMITS a generic "secure it" item per heavy
      object. S7.5's specific hazards SUPERSEDE it per object. Two strap-it items for one
      wardrobe is a defect the audit will catch.
  T4. FurnitureFixture.swift's switch over ObjectCategory is EXHAUSTIVE. New enum cases
      without renderer arms stop the app compiling — S7.1 owns adding placeholder arms in the
      same change as the enum.
  T5. THE CONTRACT-COST DECISION IS LOCKED: schema 2.1 is the arc's ONLY contract change. No
      new ItemCategory, no new FindingKind. A lane that "just adds a category" has violated a
      charter decision — stop it.
  T6. THE ANTHROPIC ACCOUNT MAY BE DRY. 502 from /explain, /analyze, /chat is billing, not
      code. No lane may depend on a live model call; live tests are written -m live and skip.
  T7. SourceKit and VS Code CANNOT INDEX this project. Trust xcodebuild only. Never let a
      subagent fix a phantom diagnostic.
  T8. iOS runs are ~1-in-3 environmental flake. Re-run a red ONCE before believing it. Counts
      from xcresulttool. And ASK THE OWNER before simulator runs on their machine (see Phase 0).
  T9. A PreToolUse hook asks for confirmation on schema/homemodel.schema.json edits — the
      process working. Only the S7.1 lane touches the schema. A pre-commit hook blocks
      Anthropic key material; never stage .env or token files.
  T10. THE PARALLEL-LANE LESSON (docs/decisions.md, fire-origin split): two lanes finished
      correct halves and the feature did not exist, because the integration point lived in a
      file fenced to the other lane. Every seam below has a NAMED OWNER. Honour them.
  T11. GEOMETRY PRIORITIZES, NEVER EXCUSES (spec §2). Any lane that suppresses the generic
      secure-it item for a far-from-everything unsecured wardrobe has inverted the rule.
  T12. Every user-facing safety sentence needs a [cite: id] resolving in
      backend/corpus/sources.json; every numeric constant is labelled cited-threshold or
      ENGINEERING CONSTANT. The spec's finding contract — number, threshold, citation,
      action — is checkable and will be checked.

════════════════════════════════════════════════════════════════════════
PHASE 2 — THE WAVE PLAN. Dispatch strictly wave by wave.
════════════════════════════════════════════════════════════════════════

Isolation: one git worktree per lane. VERIFY THE WORKTREE EXISTS before dispatching into it.

── WAVE 1 ── two lanes, zero file overlap ──────────────────────────────
  LANE A = S7.1 (schema 2.1). OWNS: schema/homemodel.schema.json, schema/fixtures/**,
           backend/app/models.py, backend/app/schema_migrator.py, escape_plan/Models/**,
           escape_plan/Renderer/Fixtures/FurnitureFixture.swift (T4), and its docs.
  LANE B = S7.2 (corpus). OWNS: backend/corpus/** ONLY.
  Seam: none. These cannot collide.
  GATE: schema-contract-guardian clean; validate.py exits 0 with the new thresholds file
        checked; a 1.1 AND a 2.0 document still load; suites at/above baseline; the seeded
        fixtures contain BOTH sides of every rule (positive + planted negative).

── WAVE 2 ── three lanes ───────────────────────────────────────────────
  LANE C = S7.3 (scan objects). OWNS: escape_plan/Capture/** (incl. Export/),
           backend/app/convert/**, backend/scripts/triage_scan.py, schema/fixtures/scans/**.
  LANE D = S7.4 (rules engine). OWNS: backend/app/routing/object_hazards.py (new),
           backend/app/routing/obstructions.py, backend/tests/test_object_hazards.py, and is
           the only Wave-2 lane permitted to touch backend/app/routing/** at all.
  LANE E = S7.6 (hazard hunt). OWNS: escape_plan/Editor/**, escape_plan/Screens/HouseScreen.swift,
           the hunt's new UI files, and DollhouseScene.swift's makeObject elevation placement.
  Seams: C and E are both iOS but own disjoint directories; the Xcode project file will
         merge-conflict — resolve by union, both lanes add files. D consumes A's fixtures and
         B's thresholds read-only. If E needs a renderer change beyond makeObject placement,
         it files a request — Wave 4 owns renderer polish.
  GATE: v2 export still converts identically (test, not claim); converter idempotent; engine
        deterministic; every planted NEGATIVE fixture case asserted silent; R4 emits
        blocked_opening on the seeded window fixture with no sentence calling it a door;
        suites at/above baseline.

── WAVE 3 ── one lane (the integration point is deliberately unsplit) ──
  LANE F = S7.5 (surfacing). OWNS: backend/app/scoring/checklist.py, score-related docs
           (docs/preparedness-score-weights.md), backend/app/ai/agent.py, and their tests.
  Seam: none — which is the point. Checklist + score + agent all read Lane D's engine, and
        splitting them re-creates the exact two-halves failure T10 describes.
  GATE: supersession works (one strap-it item per object, old checkmarks carried); citation
        resolution test walks the new items; the score-cap round trip passes; the agent tool
        returns engine fields verbatim; NO Swift enum needed editing (T5 — if it did, stop
        and escalate before merging).

── WAVE 4 ── one lane + the human ──────────────────────────────────────
  LANE G = S7.7 (3D emphasis + device pass). OWNS: escape_plan/Renderer/**,
           escape_plan/Screens/** as needed for finding→focus, docs/evidence/**.
  The device half NEEDS A HUMAN WITH AN IPHONE. The orchestrator's job is to land the
  code half, then hand the owner the exact on-device checklist from S7-7.md and WAIT.
  Do not mark S7.7 done on the code half alone — the arc's real-scan verification debt
  (S7.3's) is collected here.
  GATE: no new colour literals in the diff; RenderOrder untouched for non-hazard objects;
        unit-testable halves tested; the device checklist either executed with evidence
        filed or explicitly recorded as BLOCKED ON HARDWARE in TODO.md.

── STRETCH WAVE ── only if the core arc is green and time remains ──────
  S7.8 (re-scan diff), then S7.9 → S7.10 (Vision, sequential — S7.9's feasibility spike
  gates S7.10 and a NO-GO cuts it). Cut order if behind: S7.10, S7.9, S7.8 — per the charter.

════════════════════════════════════════════════════════════════════════
PHASE 3 — THE PER-LANE LOOP. Every subagent runs this, no exceptions.
════════════════════════════════════════════════════════════════════════

Dispatch each lane with: its S7-<n>.md prompt VERBATIM, its fence, the relevant traps, and:

  1. READ    — the session file, the spec sections it names, every existing file it says to
               read. Do not skim T1–T4.
  2. PLAN    — name every file you will create or edit; confirm each is inside your fence.
               Outside the fence → STOP and report; do not reach across.
  3. TEST    — failing tests first; each acceptance criterion becomes at least one test.
  4. BUILD   — smallest change that passes; match surrounding style.
  5. VERIFY  — run your lane's suites (backend lanes: venv pytest + validate.py; iOS lanes:
               EditorCore always, xcodebuild only owner-cleared).
  6. REVIEW  — dispatch a reviewer subagent with fresh eyes over the diff: backend lanes →
               grounding-auditor (S7.1 also schema-contract-guardian); iOS lanes →
               swift-scenekit-reviewer. Reviewer gets the diff + acceptance criteria, returns
               CONFIRMED / PLAUSIBLE findings with a failure scenario each.
  7. FIX     — every CONFIRMED finding; argue rejections in writing.
  8. RE-VERIFY, then
  9. REPORT  — what you built, the suite numbers, reviewer findings and outcomes, what you
               did NOT do and why, rough edges left. Evidence, not adjectives.

  HARD RULES for every lane: never claim done without running the thing; no new colours
  (Theme.swift scale only, route orange reserved); the AI computes no distance, severity,
  route or shelter; no uncited safety claim; no unlabelled constant; CameraRigModel stays
  pure; never re-enable allowsCameraControl.

════════════════════════════════════════════════════════════════════════
PHASE 4 — GATES. You verify. You do not trust reports.
════════════════════════════════════════════════════════════════════════

After each wave, BEFORE the next: merge the worktrees (docs/tracker/activity-log.md conflicts
every time — chronological union); re-run the suites yourself on the merged tree against
baseline; re-run any red once; dispatch lane-integrator to confirm the seams actually cohere
(T10); walk the wave's acceptance criteria yourself and tick nothing you did not observe.
A count that went DOWN without explanation is a regression. A red gate blocks the next wave.

════════════════════════════════════════════════════════════════════════
PHASE 5 — CLOSE OUT. Mandatory. A session without this did not happen.
════════════════════════════════════════════════════════════════════════

Per session: docs/tracker/TODO.md (remove only what you verified; add what you found);
docs/tracker/notes/<date>-s7-<n>-<slug>.md from _TEMPLATE.md with real counts;
docs/decisions.md for every deviation; docs/tools-used.md for any new dependency (S7.9's
Vision entry included). Arc-level: update 07-object-hazard-intro.md's status line to what is
actually built; if any session deviated from docs/object-hazard-spec.md, the spec was either
wrong (fix it, say so) or the session was (fix that) — they may not silently disagree.

════════════════════════════════════════════════════════════════════════
PHASE 6 — FINAL DELIVERABLE (not optional)
════════════════════════════════════════════════════════════════════════

Your last output is a single fenced code block containing ARTEFACT 2 below with every
<PLACEHOLDER> filled from this run — honestly, including what went badly. The S6 arc landed
unreviewed and the audit found three blocking defects; this artefact exists so that cannot
happen twice.
```

---

## ARTEFACT 2 — THE AUDIT PROMPT (template; the run above fills it in)

```text
You are auditing work you did not do. Be adversarial. Verify against the tree — never accept
a claim in a doc or report as evidence. The rule book is docs/object-hazard-spec.md; the
charter is docs/playbook/07-object-hazard-intro.md.

WHAT WAS CLAIMED
Sessions completed: <LIST>
Commits: <SHA RANGE>
Claimed suite counts: backend <N>, EditorCore <N>, iOS <N or NOT RUN>, corpus <N sources / N files>
Known-incomplete / deliberately skipped: <LIST — be suspicious of "none">

RUN THESE FIRST. Report real numbers next to claimed ones.
  backend/.venv/bin/python -m pytest backend/tests/ -m "not live" -q | tail -5
  swift test --package-path tools/editorcore 2>&1 | tail -5
  python3 backend/corpus/validate.py
  # iOS only with the owner's go-ahead on their machine; counts from xcresulttool, never
  # the console tail; a red run is ~1-in-3 flake — re-run once.

THEN CHECK EXACTLY THESE INVARIANTS. Each is a known way this repo breaks.

 1. SCHEMA LOCKSTEP. schema 2.1: do the JSON Schema, pydantic and Swift agree on
    elevation_m/mounted/new categories (names, types, defaults)? Do a 1.1 AND a 2.0 document
    still load? Run schema-contract-guardian.
 2. CONTRACT COST. Grep for new ItemCategory or FindingKind values anywhere. Finding one is a
    charter violation, not a style issue.
 3. GROUNDING. Every hazard sentence a user can see carries a citation that resolves in
    sources.json. Spot-check five against what the source actually says. Every new
    sources.json URL: fetch it — a dead URL with a fresh retrieved date shipped once already.
 4. CONSTANT HONESTY. Every numeric threshold is either cited (with source) or labelled an
    ENGINEERING CONSTANT in object_hazard_thresholds.json. Grep the engine for bare numeric
    literals and demand a justification for each.
 5. THE AI COMPUTES NOTHING. check_object_hazards returns engine fields verbatim; the prompt
    forbids estimation; no model call decides any distance, severity, or hazard.
 6. NEGATIVE CASES. For each rule: does a test assert SILENCE on the planted non-hazard
    (secured bookcase, distant heater)? A rules engine tested only on positives is untested.
 7. SUPERSESSION. One object with a topple hazard → exactly ONE strap-it checklist item, and
    a pre-existing generic checkmark carries forward. Test, or claim?
 8. R4 WORDING. Trigger the window-blockage path on the seeded fixture; read every sentence
    it emits. Any "door" for a window is a defect. Non-egress windows stay silent.
 9. DETERMINISM / ID STABILITY. Engine output and checklist ids identical across two runs on
    the same home. Tested?
10. SCAN HONESTY. secured is never inferred from a scan; low-confidence objects are flagged,
    never dropped; the v2 (object-less) export converts exactly as before; dropped RoomPlan
    categories are logged, not vanished.
11. GEOMETRY EXCUSES NOTHING. An unsecured tall wardrobe far from beds/routes still yields
    the generic mitigation.secure item. Verify on a fixture.
12. COLOUR DISCIPLINE. No new colour literals; route orange only on routes/exits.
13. SEAM INTEGRITY. Trace one full path: scan fixture → /convert → objects → /score →
    hazard.<rule>.<id> item → (if S7.7 shipped) tap → camera focus. Reachable, or two halves?
14. DOC TRUTH. TODO.md, notes, decisions.md and the spec describe the tree that exists. The
    spec and the code may not disagree; if they do, which one lied?

OUTPUT
Findings only, most severe first: file:line, one-sentence defect, concrete failure scenario,
CONFIRMED or PLAUSIBLE. Then one line — SHIP / FIX FIRST / DO NOT SHIP — and the single thing
you would fix before filming. Do not fix anything yourself. Do not restate what is correct.
```
