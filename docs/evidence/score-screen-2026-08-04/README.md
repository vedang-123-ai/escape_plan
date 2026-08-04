# Score screen renders — 2026-08-04

`twostory-score.png` closes the tracker item *"Screenshot the fixed Score screen"* (S3.5),
open since 2026-08-02. Score was broken from 2026-07-27 to 2026-08-02 (an unmapped `egress`
checklist category failed the whole `ScoreBreakdown` decode); the fix was unit-verified but
nobody had watched it render until now.

Captured by `escape_planUITests/ScoreScreenshotUITests` against a local backend on port 8099,
iPhone 17 Pro simulator (iOS 26.5). **TEST SUCCEEDED.**

What it shows — all five components decoded and rendered, no `Couldn't get your score`:

| Component | Points |
|---|---|
| Every room has a way out | 30 / 30 |
| Two ways out of every room | 25 / 25 |
| No open safety findings | 20 / 20 |
| Smoke alarms in place and working | 0 / 15 |
| Plan agreed and practiced | 0 / 10 |
| **Total** | **75 / 100** |

## Two things this picture also documents

1. **The P1 scoring flaw, visibly.** "No open safety findings — 20/20" on a home that has
   never been through `/analyze`. `/score` defaults `findings=[]`, so "we didn't look" and
   "we looked and it's clean" render identically. See the open P1 in `docs/tracker/TODO.md`.

2. **Why the earlier attempts "failed".** The three prior runs were blamed on UI-automation
   flakiness and a 99%-full disk. Disk was a real factor, but the test also asserted
   `navigationBars["Score"]` — and `ScoreScreen` sets
   `.navigationTitle(breakdown?.home_name ?? "Score")`, so "Score" is the *loading* title,
   replaced by the home name as soon as data arrives. The assertion failed on precisely the
   runs that succeeded. Fixed 2026-08-04 to wait on the "How it's scored" section header
   instead. The screenshot above was written by a run that had already "failed" this way —
   which is how the bug was spotted.
