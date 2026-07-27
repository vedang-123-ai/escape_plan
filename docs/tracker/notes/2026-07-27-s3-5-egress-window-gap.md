# S3.5 (defect) — undersized bedroom windows were invisible without /analyze

- **Who:** P3 (Claude Code)
- **Date(s):** 2026-07-27
- **Status when I stopped:** Fixed and pushed to `main`. Backend suite **238 → 242 passed**,
  12 deselected. One related issue deliberately *not* fixed — flagged for P1 in `TODO.md`.

## What happened

Two things, and the first one is a mistake worth recording.

**1. I duplicated S3.5.** I planned a session off `docs/tracker/board.md` in a clone that
turned out to be **59 commits behind `origin/main`**, and never fetched first. The board was
11 days stale and listed S3.5 as BLOCKED with the whole P3 lane empty. In reality S3.5 was
merged 2026-07-16 — backend *and* iOS (`ScoreScreen.swift`, `ScoreModels.swift`,
`APIClient+Score.swift`), with screenshot evidence. I built a complete parallel implementation
of `backend/app/scoring/` before discovering this at push time. It was never pushed to `main`;
it survives locally on branch `s35-preparedness-score` and should be deleted once anything
worth keeping is out of it.

The two implementations converged closely — same five components, same 30/25/20/15/10 weights,
same proportional treatment, same hand-reproducible worked examples — which is reassuring
about the spec but doesn't make the duplicate work worth anything.

**2. Diffing the two surfaced one real gap, and it was a safety gap.** On `twostory.json`
with no `/analyze` run, the checklist was 9 items and none of them mentioned the planted
kids'-bedroom escape window — 0.4 m wide against the 0.508 m IRC R310 minimum, i.e. a window
a child cannot climb out of. Chain of reasons:

- the whole-house router raises no `no_secondary_egress` RoutePlan finding for that room (its
  secondary route legitimately leaves by a different downstairs exit — `decisions.md`
  2026-07-16), so `route_items` had nothing to mirror;
- `finding_items` only reports what the S3.2 agent found, and the agent only runs on `/analyze`;
- so the danger was visible **only if someone happened to run the AI agent**, even though
  `routing.egress.check_egress` — the same function the engine and the agent both call —
  answers it deterministically, for free, with no model involved.

Fix: `checklist.egress_window_items()`, non-scoring (same double-counting logic as
`route_items`), cited `irc-2021-r310`, scoped to sleeping rooms because that's R310's actual
scope. `build_checklist`/`compute_score` take an optional `thresholds` arg so existing callers
are unaffected; `/score` passes the thresholds it already loads for routing.

## Decisions / surprises

Both promoted to `docs/decisions.md`.

- The egress-items decision, above.
- **The process rule:** `git fetch` before trusting any tracker file to describe current
  state. Committed docs describe the commit they live in, not the remote. The 2026-07-23
  tracker consolidation made status a mechanism rather than a habit — but a mechanism can't
  help if the clone predates it.

**Flagged for P1, deliberately not fixed (`TODO.md` → Backend):** `/score` defaults
`findings=[]`, so the 20-point "No open safety findings" component pays out **in full on a
home that has never been analysed** — bungalow and twostory both read 75/100 with nobody
having audited them. "We didn't look" and "we looked and it's clean" produce the same number.
The fix (distinguish absent from empty; report *not assessed*; expose `max_possible` so the UI
can render "55 / 80") changes `ScoreBreakdown`, the Swift `ScoreScreen`/`ScoreModels`
contract, and every worked example in the weights doc — too wide to do unilaterally, and it's
P1's call whether the honesty is worth the churn this close to the demo milestone.

## Questions for teammates

- **@P1:** the `findings=[]` question above is the one thing I want a decision on. My view is
  that it's worth fixing — a preparedness score that awards 20/100 for an audit that never
  happened is the kind of thing a judge could poke at — but it is not my call.
- **@Anish:** your S3.5 is good and I did not touch its design. The only behavioural change is
  additive: undersized bedroom windows now appear on the checklist without `/analyze`. Your 39
  tests pass unchanged; I updated the shared `_scored` helper to pass thresholds so the tests
  exercise what the endpoint actually returns.

## Next steps

1. **P1:** rule on the un-analysed-home scoring question in `TODO.md` → Backend.
2. Delete the local `s35-preparedness-score` / `-backup` branches once P1 has confirmed
   nothing else in them is wanted. Nothing in them is currently referenced.
3. Unchanged from before: the iOS `agent_finding.<id>` threading TODO (2026-07-23) still
   stands and is unrelated to this session.
