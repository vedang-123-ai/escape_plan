# Tracker reconciliation + config declutter

- **Who:** Anish + Claude (Opus 5)
- **Date(s):** 2026-09-08
- **Status when I stopped:** `BLOCKERS.md` is live and is the board. `CLAUDE.md` is lean and
  self-contained. Three stale blockers closed with evidence. One real blocker remains (bearer
  token) and it is the owner's to clear.

## What happened

Started as "how close are we to done", turned into "the tracker doesn't know what's done".

**Verified rather than inherited.** Re-ran the cheap suites: backend **348** pass (13
live-deselected), EditorCore **270** pass, corpus valid (**17** sources, **8** files). All green.
iOS not run — it needs a multi-minute simulator launch and wasn't the question. Disk is no longer
the constraint the old stamp described (39% used, 19 GB free), so the simulator is available again.

**Found four sessions marked open that had already shipped.** S6.4 (`household_items()` at
`backend/app/scoring/checklist.py:618`), S6.5 (the interview in `escape_plan/Onboarding/`), S6.6
(`HomeScreen.swift` rendering the checklist natively), S6.7 (composite score, merged in `732a5c8`).
All nine S6 sessions now have code in the tree. What's left for the arc is verification.

**Probed the deployed backend instead of trusting the note about it.** `/openapi.json` reports
schema 2.0 with `Household` and `peril`, and all nine routes including `/evacuate`. Local `main`
and `origin/main` are identical. Two "redeploy Render" items were false.

**Built `docs/tracker/BLOCKERS.md`** — the ranked board of everything blocking or unverified, in
five sections: owner-only ship blockers, device-gated work, known defects from the S6 review,
flake/process, and the submission path. `CLAUDE.md` now carries the standing rule that anything
found undone goes there in the same session.

**Cut the always-on context roughly in half.** `CLAUDE.md` went from 137 lines plus 86 lines of
`@`-referenced `rules/global/` to ~120 self-contained lines with a routing table. `rules/global/`
was deleted and its four live references updated. The SessionStart hook went from a 45-line
verbatim recital to 6 lines.

## Decisions / surprises

- **`/health`'s `v1.0` is meaningless** — a hardcoded FastAPI `app.version`, not a deploy signal.
  It is what made the deployed backend look stale on 2026-09-07 and it cost a wrong diagnosis.
  Fixed at the source: `demo-preflight.py` stopped printing it and gained `check_deployed_schema()`,
  which compares the deployed `HomeModel.schema_version` against the checkout and fails loudly on a
  mismatch. Needs no auth, so it runs without the bearer token. Verified: **PASS, schema 2.0,
  9 routes**.
- **Deleted `rules/global/` rather than just un-`@`-referencing it.** Un-referencing would have
  fixed the context cost; it would have left two copies of the conventions, which is exactly how
  this repo's docs drifted into contradicting each other in nine places. One copy, in `CLAUDE.md`.
- **Dropped the hook's "repeat this block verbatim" mandate.** It forced a fixed opening on every
  session regardless of what was asked. The traps it recited live in `CLAUDE.md`, which loads
  anyway. The handoff is still armed and still nags — just in six lines.
- **Marked only what was actually reported for LiDAR.** The trip closed "scan a real space" and
  "real scan → `/convert` → renders". It did not close double-scan, messy-scan, idempotency, or
  artifact capture, so those stay open. Sweeping them along would have been the same habit this
  session was cleaning up.
- **The `.env` read-guard held.** Probed for the bearer token; `settings.json` denied it. Correct
  behaviour, and the token was not lifted by any other route.

## Questions for teammates

- **@Anish — the bearer token is the only thing blocking a green preflight.** Create
  `escape_plan/BackendConfig.local.json` as `{"bearer_token": "<shared token>"}` and re-run
  `python3 scripts/demo-preflight.py`. Everything else in it passes.
- The Anthropic top-up is still outstanding and still blocks anything on camera that shows the
  assistant.

## Next steps

1. Owner: bearer token, then Anthropic credits.
2. The device pass — `BLOCKERS.md` §2, in order, starting with the four camera-feel checks. That
   is the critical path to filming and nothing in it has ever been done.
3. Run the iOS suite once for a current number; the 598/0/8 on record predates the Swift in tree.
