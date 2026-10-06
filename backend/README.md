# Escape Plan backend

FastAPI service wrapping the deterministic routing engine (S1.2) and the grounded
AI layer (S3.1). Routing is never done by AI; the AI layer only explains and audits,
grounded in `corpus/`.

## Run locally

```bash
cd backend
python3.12 -m venv .venv && source .venv/bin/activate   # macOS's own python3 is 3.9, too old
pip install -r requirements-dev.txt # requirements.txt plus pytest and matplotlib (graph renders)
export BACKEND_BEARER_TOKEN=dev-local-token
export ANTHROPIC_API_KEY=sk-ant-... # needed for the AI routes: /explain, /chat, /analyze, /build, and /score with include_recommendations (502 without it)
uvicorn app.main:app --reload --port 8000
```

Tests: `python3 -m pytest tests/` (from `backend/`). Live-API golden tests:
see § AI tests below.

## Endpoints

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /health` | none | liveness / platform health check |
| `POST /routes` | bearer | HomeModel (+ optional constraints, `peril`) → RoutePlan, deterministic. The engine plans fire, earthquake and tornado; the iOS app requests and draws **fire only** |
| `POST /convert` | bearer | `{scan: <RoomPlan export>, home_name?}` → validated HomeModel (S1.5 converter) |
| `POST /explain` | bearer | HomeModel + RoutePlan (+ optional profile) → cited, structured explanation (S3.1) |
| `POST /score` | bearer | HomeModel (+ constraints, `/analyze` findings, checklist state) → 0–100 preparedness score + breakdown + checklist (S3.5) |

Interactive docs at `http://localhost:8000/docs`.

### curl examples

```bash
BASE=http://localhost:8000
TOKEN=dev-local-token

# health (no auth)
curl -s $BASE/health

# routes for a fixture home
python3 - <<'EOF' > /tmp/routes-req.json
import json; print(json.dumps({"home": json.load(open("../schema/fixtures/twostory.json"))}))
EOF
curl -s -X POST $BASE/routes \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 --data @/tmp/routes-req.json | python3 -m json.tool | head -40

# routes with profile constraints (mobility-limited: no stairs, no windows)
python3 - <<'EOF' > /tmp/routes-req.json
import json
print(json.dumps({
 "home": json.load(open("../schema/fixtures/twostory.json")),
 "constraints": {"avoid_stairs": True, "avoid_windows": True},
}))
EOF
curl -s -X POST $BASE/routes \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 --data @/tmp/routes-req.json | python3 -m json.tool | head -40

# convert a RoomPlan export (synthetic fixture shown)
python3 - <<'EOF' > /tmp/convert-req.json
import json
print(json.dumps({"scan": json.load(open("../schema/fixtures/scans/synthetic-bungalow.roomplan.json")), "home_name": "My Home"}))
EOF
curl -s -X POST $BASE/convert \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 --data @/tmp/convert-req.json | python3 -m json.tool | head -30

# grounded explanation of a computed plan (needs ANTHROPIC_API_KEY on the server)
python3 - <<'EOF' > /tmp/explain-req.json
import json, urllib.request
home = json.load(open("../schema/fixtures/twostory.json"))
req = urllib.request.Request(
 "http://localhost:8000/routes",
 data=json.dumps({"home": home}).encode(),
 headers={"Authorization": "Bearer dev-local-token", "Content-Type": "application/json"},
)
plan = json.load(urllib.request.urlopen(req))
print(json.dumps({"home": home, "route_plan": plan}))
EOF
curl -s -X POST $BASE/explain \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 --data @/tmp/explain-req.json | python3 -m json.tool

# preparedness score (deterministic — no API key needed unless you ask for
# recommendations). twostory with an empty checklist scores 66; see
# docs/preparedness-score-weights.md for the hand-calculation. The example below
# ticks the meeting point and scores 71 (checked 2026-10-05).
python3 - <<'EOF' > /tmp/score-req.json
import json
print(json.dumps({
 "home": json.load(open("../schema/fixtures/twostory.json")),
 "checklist_state": {"practice.meeting_point": True},
}))
EOF
curl -s -X POST $BASE/score \
 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
 --data @/tmp/score-req.json | python3 -m json.tool | head -40
```

## AI tests (S3.1)

Deterministic tests (citation validator, fabricated-source rejection, prompt
construction) run with the normal suite. Live-API tests (5 golden fixture+route
snapshots + the red-team deferral) are skipped unless the key is present:

```bash
cd backend && ANTHROPIC_API_KEY=sk-ant-... python3 -m pytest tests/test_ai_live.py -m live -v
```

Golden snapshots land in `tests/golden/` on first run (review them by hand,
commit them); later runs compare structure + citations against the snapshot.

## Deploy (Render free tier) — HUMAN STEPS

Everything is prepared in `render.yaml` at the repo root. A human must do the
following once (P3/Claude cannot create the account):

1. Create an account at https://render.com (sign in with the team GitHub).
2. Dashboard → **New → Blueprint**, pick this GitHub repo, branch `main`.
 Render reads `render.yaml` and proposes the `escape-plan-backend` web service. Apply.
3. When prompted for env vars: `BACKEND_BEARER_TOKEN` is auto-generated by Render
 (Dashboard → service → Environment → reveal it and copy it into the team
 password note); paste the real `ANTHROPIC_API_KEY` (it is marked `sync: false`,
 so Render asks for it — it never touches git). **`MONGODB_URI` (S8.1) is also
 `sync: false` and is OPTIONAL** — leave it blank and the backend deploys and runs
 exactly as before, with `/health/db` reporting `"disabled"`. If you do set it,
 **percent-escape the username and password** (`urllib.parse.quote_plus`): an
 Atlas password containing `@`, `/` or `:` pasted raw is rejected by the driver.
 That no longer takes the service down — the layer stays disabled and logs the
 reason — but cloud sync silently will not work until it is fixed.
3b. **If you set `MONGODB_URI`, two more things are required — both learned the hard
 way on 2026-09-15, and neither is obvious from a green deploy log.**
 - **Allow-list Render in Atlas**: Atlas → Network Access → Add IP Address →
 **`0.0.0.0/0`**. Render's free tier has no static egress IPs, so there is nothing
 narrower to allow-list. Without it the service deploys clean and `/health/db`
 reports `"unreachable"` — the URI parsed, nothing can connect. Your laptop works
 regardless, because Atlas allow-lists your IP automatically at cluster setup,
 which makes this look like a code problem when it is a firewall one. The database
 user's password is then the only protection: keep it long, random and alphanumeric.
 - **Set `JWT_SECRET_KEY` by hand on an existing service.** `render.yaml` declares it
 `generateValue: true`, but that only fires on a *new* blueprint apply — an existing
 service will not pick it up. Until it is set, `/auth/*` and `/homes` return 503 by
 design (`auth_enabled` needs both a database and a secret). Minimum 32 bytes;
 changing it later invalidates every issued token.
4. Wait for the first deploy; the service URL looks like
 `https://escape-plan-backend.onrender.com`.
5. Verify from a terminal (then from the phone on cellular):

 ```bash
 BASE=https://escape-plan-backend.onrender.com TOKEN=<from-password-note>
 curl -s $BASE/health
 curl -s $BASE/health/db   # S8.1: {"database":"disabled"|"ok"|"unreachable"}
 # "unreachable" with MONGODB_URI set is almost always the Atlas allow-list, step 3b
 # then the /routes curl example above with these BASE/TOKEN
 ```

6. Post `BASE` + token in the team password note (S1.6 handoff) so P2 can wire
 `APIClient.swift`.

Notes: the free tier sleeps after ~15 min idle; the first request after sleep
takes ~30-60 s (cold start), subsequent ones are fast — warm the service before
the <2 s acceptance check and before demos. Render deploys a push to `main` only after its GitHub checks pass (`autoDeployTrigger: checksPass` in render.yaml; the dashboard setting must agree, see BLOCKERS S11.46).
