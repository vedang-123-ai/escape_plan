# S11.31 — Backend hygiene: honest /convert errors and /health commit

- **Who:** P3
- **Date(s):** 2026-10-04
- **Status when I stopped:** code merged; `/health` commit live check recorded in BLOCKERS.

## What happened
- `ConversionError` added to `converter.py`; `/convert` returns a curated 422 for it, a logged 500 for anything else.
- `/health` gained `commit` (RENDER_GIT_COMMIT or "unknown").
- Fixed the 3 PytestRemovedIn10Warning (function-scoped fixtures).
- Mutation checks: hard-coded commit, 500 to 422, no ConversionError, leaky 422 text. Each failed a new test, then restored.
- ecc:python-reviewer: two findings, both acted on (catch only ConversionError; version-proof fixtures).

## Decisions / surprises
- Mongo index retry skipped (S11.30 dropped). Logged in decisions.md.
- Another agent switched the shared checkout's branch; I worked in a worktree (`../ep-s11-31`). My first patch carried that agent's `main.py` edits; I restored them in their tree.

## Questions for teammates
- None.

## Next steps
- Run the curl in BLOCKERS after deploy. S11.46 does the CI half.
