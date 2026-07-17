# S3.5 — Preparedness score + checklist (backend half)

- **Who:** P3 (Claude Code, `../ep-s35` lane, branch `s35-score`)
- **Date(s):** 2026-07-16
- **Status when I stopped:** Backend half complete and acceptance-verified — scoring engine, `/score`, checklist generation, weights doc, 34 new tests green (134 total, 6 live deselected). **S3.5 is NOT DONE:** the iOS score screen + count-up animation (P2) are untouched, and the findings path has never seen a real S3.2 payload.

## What happened

Built `backend/app/scoring/`:

- `score.py` — `compute_score(home, plan, findings, state) -> ScoreBreakdown`. Pure: no I/O, no network, no clock. Weights are module constants. Five components, each carrying `earned_points`, `max_points`, a plain-language `detail` ("4 of 5 rooms have a primary escape route") and a `rationale` — the breakdown is built to render as a tappable list, so P2 should need no extra endpoint.
- `checklist.py` — deterministic item generation with stable ids. Smoke-alarm items come from the home itself (one per bedroom, one outside each sleeping area, one per level, plus monthly test + 10-year replacement) — which is literally what `corpus/smoke-alarms-usfa.md:40` prescribes, so the corpus wrote this function for me.
- `findings.py` — the S3.2 interface, see Integration points.
- `recommend.py` — the one impure module: calls S3.1's `explain_routes` and maps recommendations to **non-scoring** items.
- `/score` in `main.py` — thin wrapper, bearer auth like the rest, recomputes the RoutePlan from `home` + `constraints`.

Weights doc: `docs/preparedness-score-weights.md`. It justifies each weight, cites the corpus where a weight rests on a safety claim, and hand-calculates all three fixtures. Every number on that page is asserted in `tests/test_scoring.py` — that pairing is what keeps "reproducible by hand" honest instead of aspirational. Baselines (no findings, empty checklist): bungalow **75**, apartment **50**, twostory **75**.

Acceptance: pytest green; reviewer can reproduce any fixture by hand from the doc; checklist completion moves the score deterministically (`test_each_bungalow_alarm_item_is_worth_3`, `test_one_alarm_item_moves_twostory_by_15_over_7`, `test_meeting_point_item_is_worth_5`).

No new dependencies — `tools-used.md` unchanged.

## Decisions / surprises

Three rows promoted to `docs/decisions.md`. The two that a reviewer is most likely to argue with:

- **Proportional route components + per-finding deductions**, deviating from the playbook's all-or-nothing wording. Rationale in the decisions log; the short version is that an all-or-nothing score can't show progress, and a score that can't show progress won't get used.
- **The apartment caps at 75 even fully checklisted.** Not a bug — the routes components are 55 of 100 by design, so no amount of box-ticking substitutes for a second way out. Worth saying out loud in the demo; it's the clearest illustration that the score isn't vibes.

Surprise worth flagging: **the score depends on the profile.** `/score` honours `constraints`, so scoring the two-story under Grandpa's `mobility_limited` profile (`avoid_stairs`) strands the upstairs rooms and drops the score below 75. I think that's correct — the home genuinely is less ready for him — but it means "the score" is per-profile, not per-home, and nobody has decided what number the home screen shows when profiles disagree. **@P2 / @P1: that's a product decision, not a backend one.**

## Integration points

- **`app/scoring/findings.py` — the load-bearing assumption.** `Finding` is transcribed from the agent contract in `docs/playbook/S3-2.md` (`{severity: high|med|low, room_ids, finding, evidence, recommendation, citation}`), not imported from S3.2, which was in `../ep-s32` while I worked. Marked `TODO(integration)`. On merge: if S3.2 defines an equivalent model, **delete mine and re-export theirs from that path** so the scoring imports don't move. Narrow surface — scoring reads only `severity` — but two specific drifts break things:
  - severity spelling: `"med"` vs `"medium"` → `SEVERITY_DEDUCTIONS` keys and the weights-doc table must follow. `Finding` is `extra="ignore"` so unknown S3.2 fields won't 422, but a renamed severity **will** silently fail validation at the endpoint.
  - stable finding ids: the checklist synthesizes positional `agent_finding.<index>` ids. If S3.2 gives findings a real id, key on it — otherwise a re-analysis that reorders findings scrambles any persisted done-state.
- **S3.1 (`app/ai/grounded.py`)** — used as-is via `explain_routes`; I added no live tests, so `tests/test_ai_live.py` is exactly as S3.1 left it. `/score`'s AI path is mocked in tests. Nobody has ever run `include_recommendations: true` against the real API — that needs the key-gated run, and it may be worth adding a `score_recommendations` golden case to `test_ai_live.py` once a key is around.
- **S2.4 persistence** — `checklist_state` is a flat `dict[str, bool]` (item id → done) on the home document. Ids are stable per home; `alarm.bedroom.<room_id>` etc. Renaming a room is safe; deleting one orphans its item's state harmlessly.
- **S4.2 drill mode** — set `practice.drill_recent: true` on drill completion. Worth 5 points, so the demo's score visibly jumps.
- **P2 / iOS** — `ScoreBreakdown.components` is the breakdown screen in order; `score` is the count-up target.

## Questions for teammates

- **@P1:** the per-finding deduction table (high 10 / med 4 / low 1) is my judgement call, not from the corpus — no source grades severity numerically. If you disagree, it's three constants in `score.py` + one table in the weights doc + the test expectations. Also: does S3.2 emit `"med"` or `"medium"`?
- **@P2:** what does the home screen show when two profiles score differently (see the surprise above)? Lowest? The no-constraints number? Per-profile cards?
- **@P1:** should `include_recommendations` get a live golden case before we call S3.5 done?

## Next steps

1. Merge `s35-score` (backend-only; touches `main.py`, new `app/scoring/`, new tests, docs) — conflicts likely only in `main.py` imports if another lane also touched it.
2. On S3.2 merge, work the `findings.py` TODO(integration) list above, then re-run `python3 -m pytest` from `backend/`.
3. Hand P2 `docs/preparedness-score-weights.md` + `ScoreBreakdown` for the score screen.
4. Answer the profile-vs-score product question before the demo script (S5.1) freezes.
