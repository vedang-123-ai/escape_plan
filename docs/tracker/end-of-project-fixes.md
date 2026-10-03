# End-of-project fixes

_Opened 2026-10-02. Problems Anish chose to deal with at the end, after the S11 sessions. Each one also has a line in
[`BLOCKERS.md`](BLOCKERS.md) under "Owner review 2026-10-02" (the board stays the source of truth); this file holds
the detail. Remove an item here only when it is fixed and personally verified._

## 1. The free server can't keep up with a real-sized house (P1, before filming)

**What Anish saw:** in the House tab with the 12-room Ranch House, "Choose a room…" for the fire simulation showed
"The server is busy. Try again in a moment.", and above it "AI features are unavailable right now — the server needs
attention."

**Measured 2026-10-02** against `https://escape-plan-backend.onrender.com` with `demo-homes/ranch-house.homeplan.json`:

| Request | Demo home | Ranch House |
|---|---|---|
| `POST /routes` (fire) | 0.39 s | 6.6–7.6 s, three runs |
| `POST /score` | ~1 s | 20.6 s |
| `POST /evacuate` alone | — | 0.8 s, 200 |

**Cause:** Render's free instance (`render.yaml`: `plan: free`, a single `uvicorn` process) runs one request at a time
on a fraction of a CPU. Opening House sends score, routes and then the simulation together; the queue builds and
Render's front door turns requests away with 503 (shown as "busy") and 502. The app is fine: alone, each request
succeeds.

**Fix options:** Render paid tier (~$7/month; already AUD-032, logged for S11.13). Also worth measuring where the 7 s
goes, since the engine is far faster locally.

## 2. A gateway 502 is shown as "AI features are unavailable" (P2)

`escape_plan/Networking/BackendFailure.swift` maps every HTTP 502 to `.aiUnavailable`. The backend uses 502 for "an
operator must fix the AI", but Render's proxy also returns 502 when the server is overloaded or restarting. On
`/routes`, `/score` or `/evacuate`, which never use AI, that message is wrong. **Fix:** only say "AI" for the AI
operations (`/chat`, `/explain`, `/analyze`, `/build`), or check for the backend's own JSON `detail` body before
choosing the message.

## 3. The server has no Anthropic key at all (P0 for the Assistant)

`POST /chat` on the live server returns `502 {"detail":"ANTHROPIC_API_KEY is not configured on the server"}`
(2026-10-02). AUD-002 says "credits"; the real state is that the key is missing from Render's environment. Until it is
set, the Assistant tab and Import Plan fail in the demo. **Fix (owner):** add `ANTHROPIC_API_KEY` in Render → the
service → Environment, with credits on the account, then re-run the `/chat` call above.

## 4. Feature trim (owner decision pending)

Anish thinks Hazard Hunt and some other features are pointless for the demo. The full list with recommendations is
[`../demo/feature-inventory.md`](../demo/feature-inventory.md). Once its `Decision` column is filled in, one cleanup
session hides or removes what is cut (Hazard Hunt also feeds earthquake findings and checklist items, so cutting it
needs a check of what the score loses).

## 5. Test runs leave leftover homes in the simulator (P3)

UI tests create homes ("New Home", "Demo Home (scanned)") and never remove them; 61 piled up by 2026-10-02 and were
moved to a scratch backup by hand. They are simulator-only and never reach a phone. **Fix:** have the UI tests start
from a clean app container, or delete what they create.

## 6. The Ranch House test home is not committed

`demo-homes/ranch-house.homeplan.json` (12 rooms, 5 exits, 5 people, scan vs hand-added items marked) and its
generator `demo-homes/make_ranch_house.py` live only in Anish's working copy. It is valid against the schema, pydantic
and Swift `EditorValidation`, and routes every room for all three perils. **Decide:** commit it as a fixture or a
built-in demo home, or leave it local.
