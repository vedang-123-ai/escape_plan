# S1.6 — Backend scaffold + deploy

- **Who:** P1 driving P3 (Claude Code)
- **Date(s):** 2026-07-13
- **Status when I stopped:** code complete + tested locally; deploy blocked-on-human (Render account)

## What happened

- `backend/app/main.py` + `config.py`: FastAPI with open `GET /health` and bearer-token
  `POST /routes` ({home, constraints?} → RoutePlan). Thin wrappers — all logic stays in
  `app.routing`. Token compared constant-time; service **fails closed** (refuses to serve)
  if `BACKEND_BEARER_TOKEN` is unset. `ANTHROPIC_API_KEY` plumbed through Settings.
- 10 API tests in `backend/tests/test_api.py` (auth reject/wrong-token, all 3 fixtures,
  constraints applied, invalid/unknown-field 422s, fail-closed). Whole suite: 79 pass.
- `render.yaml` blueprint at repo root (free tier, rootDir backend, health check on /health,
  auto-generated token, ANTHROPIC_API_KEY sync:false). Curl examples + exact deploy steps in
  `backend/README.md`. matplotlib moved to `requirements-dev.txt` to keep the deploy image lean.
- Verified no key material in git history (`git grep`); corpus validator still green.

## Decisions / surprises

- Deploy + phone-on-cellular acceptance marked **blocked-on-human** in board/checklist, not
  claimed done — P3 cannot create the hosting account. All promoted to decisions.md.
- Render free tier sleeps after ~15 min idle → warm the service before the <2 s check and demos.

## Questions for teammates

- @P1: do the deploy (backend/README.md § Deploy, ~5 min), put base URL + token in the team
  password note, and run the phone-on-cellular check to flip S1.6 to DONE.
- @P2: `APIClient.swift` wiring (playbook mentions doing it together) needs S0.3 first —
  the curl examples define the exact request/response shapes.

## Next steps

- P1 human deploy step above; then check the remaining S1.6 boxes in checklist.md.
