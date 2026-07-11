# 2026-07-10 — kickoff state (S0.1/S0.2/S0.4/S1.1/S1.2 done)

- **Who:** P3 (Claude), directed by P1
- **Status:** Phase 0 nearly done (only S0.3 left), P1's backend lane two sessions into Phase 1. Ahead of schedule.

## What happened
- S0.2 + S1.1 + S1.2 executed and committed (`8a31a7a`). 59 pytest tests green;
  corpus validator green; fixtures + invalid fixtures + route samples all committed.
- Tracker system (this folder) created.

## Decisions / surprises
- All engine constants (window penalty 12, stair cost 6, reuse penalty 25) documented in
  decisions.md — expect judge Q&A on these.
- Fixtures have PLANTED issues on purpose (apartment single exit; kids' window too small).
  Don't "fix" them — S3.2's agent tests assert they're found.

## Questions for teammates
- @P1: read `backend/app/` + `docs/schema-summary.md` + `docs/corpus-summary.md`. CAC judges
  ask the team to explain their code — everything P3 wrote needs a human owner who understands it.
- @P1: optional — record the S1.2 CLI demo gif (`cd backend && python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty`).
- @P2: S0.3 is unblocked. Start from `docs/schema-summary.md`; the stock Core Data template
  is meant to be replaced wholesale; decide root vs `ios/` project location (decisions.md).

## Next steps
- P2 → S0.3. P3 → S1.6 (needs a human for the Render/Railway account + ANTHROPIC_API_KEY).
