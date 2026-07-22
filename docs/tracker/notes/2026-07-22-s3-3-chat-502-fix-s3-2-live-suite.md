# S3.3 fix + S3.2 prep — /chat 500→502 + test_agent_live.py

- **Who:** P3 (Claude Code)
- **Date(s):** 2026-07-22
- **Status when I stopped:** backend 197 tests green (`-m "not live"`), corpus valid; live agent suite exists but has never run against a real key

## What happened

- Fixed the "S3.3 (found, not fixed)" decisions.md finding: `api_chat.post_chat` now catches
  the base `GroundingError` (the unset-`ANTHROPIC_API_KEY` path from `service._client()`) in
  the same 502 clause as `ChatGroundingError`, mirroring `/explain` and `/analyze` in
  `main.py`. Key subtlety: `ChatGroundingError` does NOT subclass `GroundingError` — they're
  sibling `Exception` subclasses, which is exactly why the original handler missed it.
- Regression test `test_chat_endpoint_maps_missing_key_grounding_error_to_502` in
  `tests/test_chat.py`. Verified it fails on the pre-fix code (git stash) and passes on the fix.
- Wrote `backend/tests/test_agent_live.py` — the S3.2 live acceptance suite the board flagged
  as missing. Mirrors `test_ai_live.py`: `pytest.mark.live` + key-skipif, autouse bearer-token
  fixture, first-run golden snapshots to `tests/golden/agent_<case>.json` (findings + dropped +
  tool names, not full trace payloads) with `pytest.skip("review and commit")`.
  - `test_apartment_agent_flags_single_exit` — d_entry bottleneck flagged, keyword match.
  - `test_twostory_agent_flags_kids_bedroom_window` — r_bed_kids/w_kids flagged (written to
    the check_egress semantics per the 2026-07-16 decisions row, not the literal playbook
    "no secondary egress" wording).
  - Shared hard invariants: not truncated, <60s, every finding's evidence resolves into the
    trace, every citation in `valid_source_ids()`.

## Decisions / surprises

- One combined `except (ChatGroundingError, GroundingError)` clause rather than two — one 502
  site. Promoted to decisions.md.
- No new dependencies → tools-used.md untouched.

## Questions for teammates

- @P1: key session is now pure run-and-review — `ANTHROPIC_API_KEY=... python3 -m pytest
  tests/test_agent_live.py tests/test_ai_live.py tests/test_chat_live.py -m live -v`, then
  review + commit `tests/golden/`.

## Next steps

P1's key session (Render + local env var, run all three live suites, hand-review goldens)
clears S3.1/S3.2/S3.3 in one sitting.
