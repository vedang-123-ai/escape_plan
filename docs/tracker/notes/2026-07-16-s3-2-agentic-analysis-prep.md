# S3.2 — Agentic home analysis (prep)

- **Who:** P3 (Claude Code, terminal 1 of a 4-way parallel session)
- **Date(s):** 2026-07-16
- **Status when I stopped:** Code + tests complete and passing. Labeled PREP, not DONE — no ANTHROPIC_API_KEY was available, so every test scripts the Anthropic client rather than calling the real model.

## What happened

Built the tool-use agent loop in `backend/app/ai/agent.py`: six tools
(`get_home_summary`, `get_room`, `list_openings`, `compute_routes`,
`check_egress`, `search_corpus`) plus a `submit_findings` terminal tool, all
read-only wrappers over the real S0.2 HomeModel, S1.1 egress checker, and
S1.2 routing engine — the agent never computes a route or egress verdict
itself. Wired `/analyze` into `backend/app/main.py` (bearer-token gated, same
pattern as `/explain`). 22 new tests in `backend/tests/test_agent.py`, all
against real fixtures and real engine output; only the model call is faked via
a small `ScriptedClient`. Full suite (122 tests) passes with no regressions.

Created a local `.venv` in the worktree to install `requirements.txt` — none
existed yet in this checkout; already gitignored, nothing to add to
tools-used.md.

Generated a rendered example trace at `docs/agent-trace-example/` (JSON +
README) showing the apartment single-exit finding end to end, including the
server-side evidence-link check.

## Decisions / surprises

Full entries in `docs/decisions.md` (4 new rows, newest-first at top), but the
one worth flagging loudly: **the twostory.json "kids' room" planted issue
doesn't actually trip the engine's `no_secondary_egress` finding** — the
engine's secondary-route search is satisfied by a different exterior exit
anywhere in the house, and the Kids' Bedroom's secondary route just goes back
downstairs through a different door. The room's window genuinely fails egress
on its own (confirmed via `check_egress`: 0.4m width vs 0.508m required), so
it's a real planted issue — it just surfaces at the room/opening level, not
the whole-house RoutePlan level. This is *why* `check_egress` exists as an
agent tool separate from `compute_routes`, and the test suite demonstrates the
agent catching it correctly. Not a bug in S1.2 (already signed off, don't
reopen it) — just a nuance worth knowing before judges or teammates expect a
literal `no_secondary_egress` RouteFinding for that room.

## Questions for teammates

@P1 — when a real ANTHROPIC_API_KEY exists, this needs one live run (same
shape as your pending S3.1 step): confirm the real model actually inspects
systematically and produces findings as sound as the scripted tests assume.
Also worth a 2-minute read of the twostory decision above before the pitch,
in case the demo script implies the RoutePlan itself flags the kids' room.

## Next steps

Whoever picks this up next: run `cd backend && ANTHROPIC_API_KEY=... python3 -m pytest tests/ -m live -v` once a key exists (note: no `test_agent_live.py` exists yet — would need to be added, mirroring `test_ai_live.py`'s pattern, to get a golden live run and flip this from PREP to DONE). Until then this branch (`s32-agentic-analysis`, worktree `../ep-s32`) is ready to merge as-is.
