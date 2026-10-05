# Audit follow-up — /score deadline, and a parallel-work collision

- **Who:** P3
- **Date(s):** 2026-10-03 to 2026-10-05
- **Status when I stopped:** One-finding fix merged. Two duplicate session implementations
  discarded (preserved on local tags/branches, never pushed).

## What happened

I built S11.29 and S11.33 in parallel worktrees on 2026-10-03. Both were finished, gated and
committed locally. While they were in flight, teammates **independently built and merged both
of the same two sessions**, plus about twenty others — `origin/main` went from `d6e3ff9` to
`f3cd237` (84 commits) across two days.

I compared rather than assumed, and the merged versions win on the points that matter:

- **Merged S11.33 uses ImageIO/CoreGraphics with no UIKit**, so its `ImagePreparationTests`
  **run without a simulator**. That is exactly the blocker that left my version's 17 tests
  written-but-never-executed. It also reads `backend/app/limits.py` to keep the client and
  server image caps in lockstep, where I had hardcoded the server's number. And it got a real
  `swift-scenekit-reviewer` run, which mine could not — that agent died on a session rate limit.
- **Merged S11.29 uses `anthropic.Timeout` with a separate connect timeout** rather than one
  float, which is strictly better. It reached the same conclusions mine did on the things that
  had a right answer: `max_retries=1`, per-endpoint deadlines read off the Swift
  `timeoutInterval` values, a 504 on expiry, and the budget still counting calls rather than
  tokens because `rate_limit.py` was out of scope.

So I discarded both of mine. They are on tags `local-duplicate-s11-29-33` and
`local-s11-29-33-preCollision` and branches `s11-29-ai-deadlines` / `s11-33-photo-jpeg`.
Nothing was pushed.

**One thing survived.** The `grounding-auditor` run on my S11.29 found a defect the merged
implementation also has: `/score?include_recommendations=true` computes three deterministic
peril route plans and the whole `ScoreBreakdown` *before* the optional AI call, but
`explain_routes` defaults to a `Deadline` and `recommend.py` neither passes one nor catches it
— so `DeadlineExceeded` escaped `except GroundingError` and 504'd the endpoint, throwing away
finished deterministic work. I confirmed it still live on `f3cd237` with a probe test (status
504) before changing anything. That fix is this branch. Backend **1251 passed, 1 skipped, 31
deselected**.

## Decisions / surprises

Two rows in `docs/decisions.md`: the `/score` degradation, and the collision as a process
decision.

**The fix is at the call site, not in `recommend.py`.** So a future caller of
`recommendation_items` inherits the same trap. `grep -rn "recommendation_items" backend/app`
has exactly one call site today, so this is a BLOCKERS line rather than a refactor.

**Why the collision happened, concretely.** `docs/playbook/README.md` is the only
claim-staking mechanism in this repo and it is written at session **END**. Two people asking
"what is the next unblocked session?" at the same time get the same answer and neither finds
out until `git push` is rejected. That is not a people problem; the mechanism has no way to
express "started".

**What I should have done differently:** pushed the empty branch immediately after
`git worktree add`, before writing any code. `git branch -r` would then have been the lock,
and the teammate would have seen `origin/s11-33-photo-jpeg` already existed. That costs one
command.

## Questions for teammates

- **@P1 / @P2 — the claim convention is the one thing to settle before the next parallel
  batch.** Three sessions are unstarted. Either a `CLAIMED` column written at session START,
  or push the empty branch first so `git branch -r` is the lock. I would take the second: no
  new convention to remember and it is already how git works.
- **Nobody owns `backend/app/rate_limit.py`.** Both S11.29 implementations independently
  reached the same conclusion — the daily AI budget counts calls, not tokens, and closing
  that needs `rate_limit.py`. It is defensible as-is (every call site has its own
  `max_tokens`), but it needs either an owner or an explicit "known limitation" decision
  before submission.

## Next steps

1. The claim convention, before anyone starts another session in parallel.
2. **S11.49** still owes every live AI check — it needs credit (AUD-002), which is still the
   oldest open owner item.
3. The iOS app-suite count in BLOCKERS' header is still S11.8's from 2026-09-30, with a great
   many sessions landed since. Whoever next has a simulator owes a full `xcodebuild test` and
   a fresh stamp. A type-check is not a test run.
