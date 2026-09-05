# S6 arc — merge integration and prompt audit

- **Who:** P3
- **Date(s):** 2026-09-05
- **Status when I stopped:** S6 arc integrated onto `main`, audited, and **approved**. Three broken
  references fixed; scope locks updated in lockstep across five files. **No S6 session was run** —
  no code, schema or test was touched at any point in this session.

## What happened

Not a feature session — a merge and a docs audit.

**Merge.** `main` had diverged 1-and-1: one local activity-log commit against Anish's 14-file S6
readiness-pivot commit (`7a3d1a5`). There was no conflict in the working tree at the start; it
appeared during integration, in `docs/tracker/activity-log.md`, which both sides had appended to.
Rebased local onto `origin/main` and resolved by chronological union — my 08-26→22:16 entries, then
Anish's 22:29 entry. Verified rather than eyeballed: ancestor 66 headers + my 6 + their 1 = 73 in
the result, and a per-side `comm` check confirmed no entry from either side was dropped. Tagged
`backup-before-integrate-20260905-153324` before rewriting anything.

**Audit.** Read all ten S6 files (874 lines), then extracted every `backend/…`, `escape_plan/…`,
`docs/…`, `schema/…`, `.claude/…` reference across them — 46 distinct — and checked each against
the tree. Seven did not resolve; five of those are files the sessions themselves create
(`routing/perils/`, the two new corpus files, the two new mapping docs), which is correct. The
other two were real, plus one bogus agent name found by a separate check:

- S6.8 → `escape_plan/Drill/` — the module is `escape_plan/DrillMode/` (all four files it names
  are there).
- S6.9 → `escape_plan/Screens/ShareSheet.swift` — it is in `Export/`.
- S6.9 → "run the security-reviewer agent". No such agent. `.claude/agents/quality/` holds
  doc-auditor, grounding-auditor, lane-integrator, schema-contract-guardian, session-auditor,
  swift-scenekit-reviewer. The built-in `/security-review` skill was meant.

These matter more than ordinary doc drift because the S6 files are explicitly written to be pasted
verbatim into a fresh session that will not have any of this context.

## Decisions / surprises

**Did not resolve the `CLAUDE.md` scope contradiction, on purpose.** `CLAUDE.md` says "fire only …
other disasters" is out of scope; the S6 arc adds earthquake and severe weather; both files
auto-load into every session. The obvious "fix" is to flip the scope line — but `decisions.md`
parks the arc as a proposal and `TODO.md`'s first line *is* the pivot-or-finish decision, so
flipping it would record a team ruling nobody has made. Instead the contradiction is named in place,
the existing lock is kept in force, and the note says to amend the line once the decision exists
rather than work around it. Resolving a doc conflict is hygiene; resolving this one is the pivot.

**Surprise worth passing on:** the arc's "what already exists — extend it, do not rebuild it" table
is the best thing in it, and it is incomplete in exactly the place it costs most. `escape_plan/Export/`
is already a full PDF pipeline (`EscapePlanPDF`, `FloorPlanDrawing`, `PlanProjection`, `PlanInk`,
`PDFText`, `EscapePlanExporter`) and `RouteNarration.swift` is pure Foundation and already documented
as having two callers by design. S6.9's snapshot is a third caller and a re-target of that renderer,
not a new one. Added to S6-9.md. If anything else in the arc looks like new construction, check
`Export/` and `RouteNarration` first.

**Left alone deliberately:** `06-pivot-intro.md`'s dependency map draws S6.3 → S6.6, but S6-6.md's
header lists prereqs as S6.4 + S6.5 only. S6.6 renders `no_viable_safe_room`, which only S6.3
produces, so the map looks right and the header looks thin — but editing a prereq declaration either
strands a session or makes one wait for nothing, so it is a TODO line rather than a silent edit.

## Questions for teammates

- @Anish — S6.6 prereqs: does it need S6.3 landed (it renders `no_viable_safe_room`), or is the
  intent that it renders those findings only once S6.3 exists and degrades before then, the way it
  already does for S6.7's composite score?
- @Anish — the arc is written as "proposal, not approved". Who makes the pivot-or-finish call, and
  does the open UI/UX handoff in `START-HERE.md` close or pause if it goes to pivot?

## Addendum — approved same session

The owner approved the pivot before this session ended. Scope is now fire + earthquake + severe
weather. Every place asserting the old lock was found by grep and updated together: `CLAUDE.md`,
`.claude/rules/global/conventions.md` (both auto-load into every session),
`playbook/01-product-spec.md` (two lines), and `06-pivot-intro.md`'s status line. A separate
`docs/decisions.md` row records the approval rather than editing the scoping row above it, so the
sequence stays readable: the arc was written before it was sanctioned, and that ordering is worth
being able to see later.

`docs/demo/script-v1.md` was deliberately NOT rewritten. It still pitches fire-only and its truth
ledger cites the lock that just changed, but rewriting a demo script for software that does not
exist yet would be inventing the demo. It is a TODO line against the S5.1 accuracy pass instead.

## Next steps

1. **S6.1 and S6.2 are the only two that can start immediately.** S6.2 (corpus) is independent of
   everything else and needs no schema, so it parallelises with S6.1 cleanly.
2. **Decide what happens to the `START-HERE.md` handoff** — it is still `handoff_status: active`,
   so every session still opens by being told to finish the camera feel and the device pass. That
   work did not stop being real (S6.6 replaces the Home tab, it does not touch the camera rig), but
   it now competes with a 56h arc for the weeks before Oct 24. Not decided here.
3. Nothing was pushed. `main` is ahead of `origin/main` by five commits.
