# backend/ — Python FastAPI service

Models + routing (S0.2/S1.1/S1.2), FastAPI service (S1.6), grounded AI layer (S3.1). Read the root `CLAUDE.md` first; run/deploy/curl docs in `README.md`.

Current state:

- `app/models.py` — pydantic HomeModel (the schema's executable half) + geometry validators
- `app/validate.py` — `python3 -m app.validate <file>` (JSON Schema + pydantic, run from backend/)
- `app/routing/` — `egress.py` (threshold checks), `graph.py` (NavGraph builder), `engine.py`
 (Dijkstra primary/secondary + bottlenecks), `plan.py` (RoutePlan models),
 CLI `python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty`
- `app/main.py` + `app/config.py` — FastAPI: open `/health`; bearer-token `/routes`, `/convert`,
 `/explain`, `/score`. Fails closed without `BACKEND_BEARER_TOKEN`. Deploy blueprint:
 `render.yaml` (repo root)
- `app/ai/grounded.py` — corpus-grounded explanations: cached corpus system block, tool-use
 structured output, server-side citation validation with reject/retry
- `app/scoring/` — explainable 0–100 preparedness score (S3.5): `score.py` (pure
 `compute_score`, weights as constants), `checklist.py` (deterministic items), `findings.py`
 (the S3.2 interface — carries a TODO(integration)), `recommend.py` (the only AI call here;
 its items never score). Weights + hand-calculations: `docs/preparedness-score-weights.md`,
 which `tests/test_scoring.py` asserts — change the two together or the doc lies
- `scripts/render_graphs.py` — dev-only matplotlib graph renderings → docs/graphs/
- `tests/` — pytest; run `python3 -m pytest` from backend/. Live-API golden tests are
 `-m live` only: `ANTHROPIC_API_KEY=... python3 -m pytest tests/test_ai_live.py -m live -v`
- `requirements.txt` — runtime deps (fastapi/uvicorn/anthropic/…); `requirements-dev.txt` adds matplotlib

Planned structure (playbook §2.3):

- `app/api/` — FastAPI routes: `/health`, `/convert`, `/routes`, `/analyze`, `/explain`, `/chat`, `/score`
- `app/routing/` — deterministic graph build + Dijkstra path search (S1.1/S1.2, owner P1)
- `app/convert/` — RoomPlan export → HomeModel converter (S1.5)
- `app/ai/` — grounded Claude integration + hand-rolled agent tool-use loop (S3.x)
- `app/scoring/` — explainable preparedness score (S3.5)
- `corpus/` — curated FEMA/NFPA/Red Cross excerpts as markdown + `sources.json` + `egress_thresholds.json` (S0.4)
- `tests/` — pytest; fixtures from `../schema/fixtures/`

Conventions: Python 3.11+, fully typed, pydantic v2 models generated from `schema/homemodel.schema.json` semantics, pure functions in routing (no I/O), `ANTHROPIC_API_KEY` from env only.
