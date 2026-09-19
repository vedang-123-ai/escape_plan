# Everything still to do (long-tail backlog)

> **[`BLOCKERS.md`](BLOCKERS.md) is the board. Read it first.** This file holds only what is real but not on the
> critical path. If the two disagree, `BLOCKERS.md` wins. Reset 2026-09-18 for the S11 arc: the previous 1,000-line
> history lives in git (`git show archive/pre-s11-origin:docs/tracker/TODO.md`, and `archive/pre-s11-main` for the
> local variant with the S10.1 bug log), and finished work is in `notes/` and `docs/decisions.md`.

**Rules.** Only things not yet done live here. Check a box only after you verified it yourself. Every line names its
next action. Lines carried over from the archive are marked *(archive)*: verify they are still true before working on them.

## The plan

The S11 arc is [`../playbook/README.md`](../playbook/README.md): 13 sessions in three lanes, each on its own branch.

| Lane | Sessions |
| --- | --- |
| A: backend, corpus, AI | S11.1 corpus depth, S11.2 peril scoring, S11.3 hazard QA, S11.4 AI layer |
| B: iOS product surfaces | S11.5 readiness Home, S11.6 responder snapshot, S11.7 accounts demoted |
| C: verification and device (simulator + iPhone) | S11.8 iOS verification, S11.9 camera and frame rate, S11.10 real scan and AR Drill |
| All | S11.11 integration gate, S11.12 pitch v2, S11.13 film and submit |

## Owner-only (nobody else can clear these)

- [ ] Top up the Anthropic account. `/explain`, `/analyze`, `/chat` and `/build` return 502 until then, and the 13 live tests plus the
      never-run `agent_bungalow_blocked` golden stay blocked. Then run the live suite (S11.4 writes the command).
- [ ] Create `escape_plan/BackendConfig.local.json` (`{"bearer_token": "..."}`, gitignored) on every build machine, and confirm the
      token in `.env` matches the deployed backend (BLOCKERS §1). Set `ANTHROPIC_API_KEY` on Render.
- [ ] Merge `s11-0-baseline` to `main` and push (BLOCKERS, S11 section), so the other two people can branch.
- [ ] Apply the pending `.claude/settings.json` and hook edits listed in BLOCKERS (S11 section).
- [ ] Decide the fate of `../wt-s6-1`, `origin/s6-1-schema-2-0` and the `~/.gemini` worktrees (BLOCKERS, S11 section).

## Carried from the archive (verify first)

- [ ] *(archive)* Enum-parity contract test: object categories in JSON Schema, pydantic and Swift.
- [ ] *(archive)* A milder tint for `narrows_route` findings (Theme colour, no new colours).
- [ ] *(archive)* Decide what the Beta tab does in a Release build (`BetaScreen`); it is a tester surface today.
- [ ] *(archive)* `escape_plan/CLAUDE.md` is compiled into the app bundle by the synchronized root group; confirm and exclude it.
- [ ] *(archive)* Scan the same space twice and check the two models reconcile; commit real scan exports (S11.10 covers the
      first two exports).
- [ ] *(archive)* `setOpeningWidth` exists in the reducer with no UI entry point; tapping a person figure in 3D does not select
      them (`PeopleLayer.profileID(forHit:)` exists and is tested; it needs an `onPersonTapped` hook).
- [ ] *(archive)* The S3.1 p95 latency goal is formally unmet but deferred.
- [ ] *(archive)* Photo-assist (Vision) was a NO-GO in S7.9; do not reopen without evidence (`docs/decisions-object-detection-future.md`
      is written in S11.3).
