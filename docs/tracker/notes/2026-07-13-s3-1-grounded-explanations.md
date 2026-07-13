# S3.1 — Grounded explanations + recommendations

- **Who:** P1 driving P3 (Claude Code)
- **Date(s):** 2026-07-13
- **Status when I stopped:** code complete; deterministic tests green; live golden run blocked on ANTHROPIC_API_KEY (one command for P1)

## What happened

- `backend/app/ai/grounded.py`: system prompt = hard grounding rules (never route, never
  invent, cite everything, 911-first, family language) + the full corpus embedded as tagged
  `<corpus_doc>` blocks with `cache_control: ephemeral` on the corpus block; cache hits/misses
  logged per call with token counts.
- `POST /explain` (bearer-auth): HomeModel + RoutePlan (+ optional Profile) → schema-enforced
  structured output via forced tool-use (`submit_explanation`, pydantic-derived JSON schema):
  summary, per-room explanations, recommendations each {claim, action, source_citation}.
  Temperature 0.2.
- Server-side citation validation: citable ids = exactly the `sources` array of sources.json
  (compilation ids like `fire-facts-stats` are not citable). Invalid citation → `is_error`
  tool_result fed back, up to 2 retries → `GroundingError` → HTTP 502.
- Tests: 14 deterministic (validator accepts real/rejects fabricated source, empty-recs
  rejected, prompt embeds all 7 corpus docs + cache_control, retry-then-succeed and
  give-up-after-retries with a faked client, endpoint 401/200/502). Live tests in
  `tests/test_ai_live.py` behind a `live` marker (excluded by default via pytest.ini):
  5 golden fixture+route cases (incl. constraints and profile variants) + the red-team
  "should I jump from the second floor?" deferral test. First live run writes snapshots to
  `tests/golden/` for hand review; latency recorded per case.

## Decisions / surprises

- **Honest status:** ANTHROPIC_API_KEY was not present in P3's shell environment, so the live
  golden tests have NOT been executed. Everything deterministic is verified; the live run is
  one command (below). Not claiming the "valid cited JSON on all fixtures" or "p95 <6s" boxes
  until it runs.
- Golden tests assert structural stability (room coverage + citation overlap), not exact text —
  model wording isn't deterministic even at temp 0.2. Promoted to decisions.md.
- `answer_grounded_question()` shares the cached system prompt and is the S3.3 chat entry point.

## Questions for teammates

- @P1: run `cd backend && ANTHROPIC_API_KEY=sk-ant-... python3 -m pytest tests/test_ai_live.py -m live -v`,
  hand-review `tests/golden/*.json` + `red_team_jump.txt`, commit them, and paste 3 sample
  outputs in the team channel (that's the S3.1 handoff artifact). Check p95 <6s from the
  recorded `latency_s` values (run twice to see cache-hit latency).

## Next steps

- P1 live run above → flip S3.1 to DONE in board/checklist.
- S3.2 (agentic analysis) can start now; it reuses `build_system_blocks()` and the fixtures'
  planted issues (apartment single exit, kids' room no secondary egress).
