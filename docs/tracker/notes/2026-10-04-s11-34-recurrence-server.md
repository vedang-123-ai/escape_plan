# S11.34 — Checklist recurrence works through /score (server)

- **Who:** Claude (Lane E, backend)
- **Date(s):** 2026-10-04
- **Status when I stopped:** server half merged to main; deploy not confirmed; S11.35 (app) not started.

## What happened
`/score` now accepts ISO-8601 completion timestamps per checklist item, passes the server clock, and reports each item's `recurrence_days` and `completed_at`. `alarm.test_monthly` recurs every 30 days from the corpus line "Test every alarm monthly". 21 new HTTP tests in `backend/tests/test_recurrence.py`. Full suite 1045 passed after merging origin/main; corpus valid.

Mutation checks: eight edits to the code each made a named test fail, then were restored (list in BLOCKERS, "S11.34 findings"). One edit survived: `.days < N` vs `timedelta(days=N)`, which are equal for non-negative ages. A reviewer said the first stretches the window; it does not. I kept the `timedelta` form and wrote the boundary test as a pin, not a mutation proof.

## Decisions / surprises
- Legacy `true` stays done (STEP 0 option a). Logged in decisions.md with the monthly-test and `completed_at` rows.
- The monthly test is scoring, so a lapse lowers the score. Flagged in BLOCKERS as an owner decision.
- Future timestamps (more than 1 day ahead) are not done. A timestamp on a non-recurring item is ignored.
- Surprise: another session shared this working tree. Its uncommitted edits to `converter.py`, `main.py` and two test files appeared and then vanished mid-session, and once removed my `now=` line from `/score` (I re-added it and re-ran everything). I committed only my own files by path.

## Questions for teammates
@S11.35 owner: contract is in BLOCKERS under "S11.34 findings". Do not ship before the deploy shows this commit on `/health`.

## Next steps
Confirm the deploy is live (`/health` commit), then start S11.35.
