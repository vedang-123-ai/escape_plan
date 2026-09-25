# backend/ — Python FastAPI service

Read the root `CLAUDE.md` first; run, deploy and curl docs are in `README.md`. Create the venv once:
`python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` (it is gitignored), then run tests with
`.venv/bin/python -m pytest tests/ -m "not live"`.

## Layout

- `app/models.py` — pydantic HomeModel (the schema's executable half) and geometry validators.
  `app/validate.py` — `python3 -m app.validate <file>`. `app/schema_migrator.py` — upgrades on-disk versions.
- `app/routing/` — pure and deterministic: `egress.py`, `graph.py` (NavGraph), `engine.py` (Dijkstra primary/secondary,
  bottlenecks, obstruction analysis), `plan.py`, `perils/` (earthquake and tornado objectives, shelters),
  `object_hazards.py` (the S7 hazard rules). CLI: `python3 -m app.routing plan ../schema/fixtures/twostory.json --pretty`.
- `app/convert/` — RoomPlan export to HomeModel converter (pure).
- `app/scoring/` — explainable 0-100 readiness score: `score.py`, `checklist.py`, `findings.py`, `recommend.py` (the
  only AI call here; its items never score). Weights and hand calculations: `docs/preparedness-score-weights.md`,
  asserted by `tests/test_scoring.py`. Change the two together or the doc lies.
- `app/ai/` — the AI layer: `grounded.py` (cached corpus block, structured output, server-side citation validation with
  retry), `agent.py` (hand-rolled tool-use loop, 8 tools that all call the deterministic engines, capped at 15
  iterations), `chat/`, `builder.py` (draft `HomeModel` from text or photo, every element tagged `ai_plan`).
- `app/builder/` — the `/build` intake helpers. `app/api_chat.py` — `/chat`.
- `app/main.py` + `app/config.py` — the FastAPI app. Compute and AI routes are bearer-token gated (fails closed without
  `BACKEND_BEARER_TOKEN`); `/auth/me` and `/homes*` take the per-user JWT instead; open are only `/health`, `/health/db`,
  `/auth/register` and `/auth/login`. `tests/test_route_guards.py` walks `app.routes` and fails any route outside that
  allow-list that answers without credentials. Deploy blueprint: `render.yaml`.
- `app/api_auth.py`, `app/auth/`, `app/cloud_models.py`, `app/cloud_repo.py`, `app/database.py` — optional accounts and sync
  (`/auth/register`, `/auth/login`, `/auth/me`, `/homes`). JWT and Argon2id; MongoDB on `pymongo.AsyncMongoClient`,
  disabled when `MONGODB_URI` is unset. `tests/test_cloud_mongo.py` is marked `mongo` and skipped by default.
- `corpus/` — curated FEMA/NFPA/Red Cross/USFA markdown, `sources.json`, `egress_thresholds.json`,
  `object_hazard_thresholds.json`. Rules: `.claude/rules/paths/corpus.md`; validate with `python3 corpus/validate.py`.
- `tests/` — pytest; fixtures from `../schema/fixtures/`. Live-API tests are `-m live` only and need a funded key.

## Endpoints

Open: `GET /health`, `GET /health/db`, `POST /auth/register`, `POST /auth/login`. Bearer-token: `POST /routes`, `/evacuate`, `/convert`, `/score`,
`/diff_obstructions` (all deterministic); `POST /explain`, `/analyze`, `/build`, `/chat` (AI, 502 without a funded key);
per-user JWT: `GET`/`DELETE /auth/me` and `/homes*`. The deterministic half never depends on the AI half.

Conventions: Python 3.11+, fully typed, pydantic v2, pure functions in routing and scoring (no I/O, no globals),
`ANTHROPIC_API_KEY` from env only.
