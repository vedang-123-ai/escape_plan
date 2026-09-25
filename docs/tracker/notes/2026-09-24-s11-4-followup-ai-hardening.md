# S11.4 follow-up: AI hardening (four logged items)

- **Who:** agent run, orchestrated (branch `s11-4-followup-ai-hardening`, worktree `ep-s11-4f`)
- **Date(s):** 2026-09-24
- **Status when I stopped:** all four items closed and verified. Backend 788 -> 843 passed, 1 skipped,
  29 deselected. Corpus valid, unchanged. grounding-auditor CLEAN; its 7 non-blocking findings were handled
  (5 fixed, 1 in decisions.md, and 1 removed at the root by sharing the orphan list with validate.py). Not merged. That is the orchestrator's job.

## What happened

1. **`ANTHROPIC_MODEL` swap.** API facts came from the claude-api skill. Forced `tool_choice` returns a 400 on
   Fable 5.1, Mythos 5.1 and Opus 5.5. The bigger finding is that `thinking={"type":"disabled"}`, sent by
   grounded, chat and agent, also returns a 400 on Fable 5 and 5.1, Mythos 5 and 5.1, and Opus 5.5. Switching
   `/explain` to `tool_choice=auto` would therefore not have made the model swappable, so the fix went into
   the config layer. `app/ai/model_support.py` holds the tables, `config.get_settings` refuses an unsupported
   model, and `tests/test_ai_model_support.py` records every request from all five call sites and checks each
   one against every supported model.
2. **`threshold_m` in the tool description.** The requested wording, "only a standard when the finding carries
   a citation", would have been wrong, because every object-hazard finding carries a citation. The description
   instead classifies by rule, and a test checks that classification against the engine over all fixtures.
3. **Exact-id corpus match.** The stricter test went red only on `usgs-earthquake`, as predicted. My first
   version exempted that id by name. `s11-1-followup-orphan-cites` then merged to `main` and kept the source,
   because its removal is blocked on S11.10. The exemption now comes from `ORPHAN_SOURCE_EXCEPTIONS` in
   `backend/corpus/validate.py`, so the corpus validator and this test share one list.
4. **`/build` evals.** `/build` returns no prose, so the three cases grade the `BuildResult`. Their probes are
   scripted tool-call turns replayed through the real `run_builder`. The cases are: a request with no house in
   it builds nothing, stated dimensions are used exactly, and no rooms are invented.

## Decisions / surprises

- Three rows in `docs/decisions.md`, all dated 2026-09-24.
- Surprise: the builder is the only AI call site that omits `thinking`, so it already runs adaptive thinking
  on sonnet-5, unlike the other three. This is not a bug, but it is inconsistent with the latency reasoning
  in the other files.
- Surprise: the agent's kickoff user message is still fire-only ("fire escape safety issues"). The positioning
  test checks system prompts only, so it missed this. Logged in BLOCKERS.

## Questions for teammates

- S11.10: when you re-point the Drill aftershock card, delete the `usgs-earthquake` source and its
  `ORPHAN_SOURCE_EXCEPTIONS` entry together. `test_ai.py` then needs no edit.

## Next steps

- After credits are topped up, run `pytest backend/tests/evals -m live`. It should score 16 cases, including
  the 3 builder cases.
- Tick the S11.3 `threshold_m` line and the S11.1 substring-check line in BLOCKERS. This branch closed both,
  but they sit under other sessions' headings.
