# backend/ — Python FastAPI service

Not yet scaffolded (happens in S1.6; corpus lands earlier in S0.4). Read the root `CLAUDE.md` first.

Planned structure (playbook §2.3):

- `app/api/` — FastAPI routes: `/health`, `/convert`, `/routes`, `/analyze`, `/explain`, `/chat`, `/score`
- `app/routing/` — deterministic graph build + Dijkstra path search (S1.1/S1.2, owner P1)
- `app/convert/` — RoomPlan export → HomeModel converter (S1.5)
- `app/ai/` — grounded Claude integration + hand-rolled agent tool-use loop (S3.x)
- `app/scoring/` — explainable preparedness score (S3.5)
- `corpus/` — curated FEMA/NFPA/Red Cross excerpts as markdown + `sources.json` + `egress_thresholds.json` (S0.4)
- `tests/` — pytest; fixtures from `../schema/fixtures/`

Conventions: Python 3.11+, fully typed, pydantic v2 models generated from `schema/homemodel.schema.json` semantics, pure functions in routing (no I/O), `ANTHROPIC_API_KEY` from env only.
