# backend/ — Python FastAPI service

Partially scaffolded: models + routing landed in S0.2/S1.1/S1.2; FastAPI wrapper comes in S1.6. Read the root `CLAUDE.md` first.

Current state:

- `app/models.py` — pydantic HomeModel (the schema's executable half) + geometry validators
- `app/validate.py` — `python3 -m app.validate <file>` (JSON Schema + pydantic, run from backend/)
- `app/routing/` — `egress.py` (threshold checks), `graph.py` (NavGraph builder), `engine.py`
  (Dijkstra primary/secondary + bottlenecks), `plan.py` (RoutePlan models),
  CLI `python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty`
- `scripts/render_graphs.py` — dev-only matplotlib graph renderings → docs/graphs/
- `tests/` — pytest; run `python3 -m pytest backend/tests/` from the repo root
- `requirements.txt` — pydantic, jsonschema, pytest (+ matplotlib dev-only)

Planned structure (playbook §2.3):

- `app/api/` — FastAPI routes: `/health`, `/convert`, `/routes`, `/analyze`, `/explain`, `/chat`, `/score`
- `app/routing/` — deterministic graph build + Dijkstra path search (S1.1/S1.2, owner P1)
- `app/convert/` — RoomPlan export → HomeModel converter (S1.5)
- `app/ai/` — grounded Claude integration + hand-rolled agent tool-use loop (S3.x)
- `app/scoring/` — explainable preparedness score (S3.5)
- `corpus/` — curated FEMA/NFPA/Red Cross excerpts as markdown + `sources.json` + `egress_thresholds.json` (S0.4)
- `tests/` — pytest; fixtures from `../schema/fixtures/`

Conventions: Python 3.11+, fully typed, pydantic v2 models generated from `schema/homemodel.schema.json` semantics, pure functions in routing (no I/O), `ANTHROPIC_API_KEY` from env only.
